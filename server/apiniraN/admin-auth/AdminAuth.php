<?php
declare(strict_types=1);
require_once __DIR__.'/vendor/autoload.php';
final class NiraAdminRateLimit extends DomainException { public function __construct(public readonly int $retryAfter) { parent::__construct('Too many attempts. Try again in '.$retryAfter.' seconds.'); } }

/** Storage adapters must serialize the WHOLE callback and persist returned error results too. */
final class NiraAdminAuth
{
    private Closure $read;
    private Closure $transaction;
    private array $config;
    private int $retryAfter=0;
    public function __construct(callable $read, callable $transaction, array $config)
    {
        $this->read=Closure::fromCallable($read); $this->transaction=Closure::fromCallable($transaction); $this->config=$config;
    }
    private function now(): int { return isset($this->config['clock']) ? ($this->config['clock'])() : time(); }
    public function state(): array
    {
        $state=($this->read)();
        if (($state['auth_version']??1)!==1) throw new RuntimeException('Unsupported authentication schema; restore matching source.');
        return $state;
    }
    private function mutate(callable $callback): array
    {
        return ($this->transaction)(function(array &$state) use($callback): array {
            if (($state['auth_version']??1)!==1) throw new RuntimeException('Unsupported authentication schema; restore matching source.');
            $state['auth_version']=1;
            return $callback($state);
        });
    }
    public static function https(): bool
    {
        return in_array(strtolower((string)($_SERVER['HTTPS']??'')),['on','1'],true) || (string)($_SERVER['SERVER_PORT']??'')==='443';
    }
    public function start(): void
    {
        if (!self::https()) throw new DomainException('HTTPS is required for the administrator panel.');
        if (session_status()!==PHP_SESSION_ACTIVE) {
            ini_set('session.use_strict_mode','1'); ini_set('session.use_only_cookies','1'); ini_set('session.use_trans_sid','0');
            session_name($this->config['session']);
            session_set_cookie_params(['lifetime'=>0,'path'=>$this->config['path'],'secure'=>true,'httponly'=>true,'samesite'=>'Strict']);
            session_start();
        }
        header('Cache-Control: no-store'); header('X-Content-Type-Options: nosniff'); header('Referrer-Policy: no-referrer'); header('X-Frame-Options: DENY');
    }
    private function renew(array $session): void
    {
        if (session_status()===PHP_SESSION_ACTIVE) session_regenerate_id(true);
        $_SESSION=$session+['csrf'=>bin2hex(random_bytes(32))];
    }
    public function csrf(): string
    {
        if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) $_SESSION['csrf']=bin2hex(random_bytes(32));
        return $_SESSION['csrf'];
    }
    public function validCsrf($token): bool { return is_string($token) && hash_equals($this->csrf(),$token); }
    private function current(array $state): bool
    {
        if (empty($_SESSION['authenticated']) || !isset($_SESSION['generation'],$state['generation']) || !is_string($_SESSION['generation']) || !hash_equals($state['generation'],$_SESSION['generation'])) return false;
        if (isset($this->config['bind_ip']) && $this->config['bind_ip'] && (!isset($_SESSION['admin_ip']) || !hash_equals($_SESSION['admin_ip'], $this->ip()))) return false;
        if (isset($_SESSION['trusted_selector'])) {
            $device=$state['trusted'][$_SESSION['trusted_selector']]??null;
            if (!is_array($device) || $device['expires']<=$this->now()) return false;
        }
        return true;
    }
    public function authenticated(): bool { return $this->current($this->state()); }
    public function pending(): bool
    {
        $state=$this->state();
        return isset($_SESSION['pending'],$_SESSION['pending_until'],$state['generation']) && $_SESSION['pending_until']>$this->now() && is_string($_SESSION['pending']) && hash_equals($state['generation'],$_SESSION['pending']);
    }
    public function status(): array
    {
        $state=$this->state();
        $devices=[];
        if ($this->current($state)) foreach($state['trusted']??[] as $selector=>$device) if ($device['expires']>$this->now()) $devices[]=['selector'=>$selector,'created'=>$device['created'],'expires'=>$device['expires'],'current'=>($_SESSION['trusted_selector']??null)===$selector];
        return ['authenticated'=>$this->current($state),'pending_2fa'=>$this->pending(),'two_factor_enabled'=>!empty($state['totp']),'username'=>$this->current($state)?($state['username']??'admin'):'','devices'=>$devices,'csrf'=>$this->csrf()];
    }
    private function ip(): string { return (string)($_SERVER['REMOTE_ADDR']??'unavailable'); } // Never consult forwarded headers.
    private function limited(array &$state,string $stage,callable $verify): bool
    {
        $now=$this->now(); $keys=[$stage.':account',$stage.':ip:'.hash('sha256',$this->ip())];
        foreach($state['limits']??[] as $key=>$item) if (($item['until']??0)<=$now && ($item['time']??0)<$now-600) unset($state['limits'][$key]);
        foreach($keys as $key) if (($state['limits'][$key]['until']??0)>$now) { $this->retryAfter=$state['limits'][$key]['until']-$now; return false; }
        $valid=$verify();
        foreach($keys as $key) {
            if ($valid) { unset($state['limits'][$key]); continue; }
            $item=$state['limits'][$key]??['count'=>0,'time'=>$now,'until'=>0];
            if ($item['until']>0 && $item['until']<=$now) $item=['count'=>0,'time'=>$now,'until'=>0];
            $item['count']=min(5,$item['count']+1); $item['time']=$now;
            if ($item['count']>=5) $item['until']=$now+60;
            $state['limits'][$key]=$item;
        }
        return $valid;
    }
    private function key(): string
    {
        $name=$this->config['key_env']; $value=getenv($name);
        if (!is_string($value) || $value==='') $value=$_SERVER[$name]??$_ENV[$name]??'';
        $key=is_string($value)?base64_decode($value,true):false;
        if (!is_string($key) || strlen($key)!==32) throw new DomainException('Configure a separate 32-byte base64 '.$name.' outside the web root before setting up 2FA. See ADMIN_AUTH.md.');
        return $key;
    }
    private function encrypt(string $secret): array
    {
        $iv=random_bytes(12); $tag='';
        $cipher=openssl_encrypt($secret,'aes-256-gcm',$this->key(),OPENSSL_RAW_DATA,$iv,$tag,$this->config['realm'],16);
        if (!is_string($cipher)) throw new RuntimeException('Secret encryption unavailable.');
        return ['iv'=>base64_encode($iv),'tag'=>base64_encode($tag),'cipher'=>base64_encode($cipher)];
    }
    private function decrypt(array $value): string
    {
        $iv=base64_decode($value['iv']??'',true); $tag=base64_decode($value['tag']??'',true); $cipher=base64_decode($value['cipher']??'',true);
        if (!is_string($iv) || strlen($iv)!==12 || !is_string($tag) || strlen($tag)!==16 || !is_string($cipher)) throw new RuntimeException('Invalid encrypted authentication data.');
        $secret=openssl_decrypt($cipher,'aes-256-gcm',$this->key(),OPENSSL_RAW_DATA,$iv,$tag,$this->config['realm']);
        if (!is_string($secret)) throw new RuntimeException('Authentication key does not match. Restore the correct external key.');
        return $secret;
    }
    private function otp(string $secret): OTPHP\TOTP { return OTPHP\TOTP::create($secret,30,'sha1',6); }
    private function consume(array &$state,$code,bool $recovery=true): bool
    {
        if (!is_string($code)) return false;
        if (preg_match('/\A[0-9]{6}\z/D',$code)===1) {
            $otp=$this->otp($this->decrypt($state['totp'])); $step=intdiv($this->now(),30);
            foreach([$step,$step-1,$step+1] as $candidate) {
                if ($candidate>($state['last_step']??-1) && hash_equals($otp->at($candidate*30),$code)) { $state['last_step']=$candidate; return true; }
            }
        } elseif ($recovery && preg_match('/\A[a-f0-9]{8}-[a-f0-9]{8}\z/D',$code)===1) {
            foreach($state['recovery']??[] as $index=>$hash) if (hash_equals($hash,hash('sha256',$code))) { unset($state['recovery'][$index]); $state['recovery']=array_values($state['recovery']); return true; }
        }
        return false;
    }
    private function credentials(array $state,$password): bool
    {
        return is_string($password) && strlen($password)<=1024 && isset($state['password_hash']) && password_verify($password,$state['password_hash']);
    }
    private function proof(array &$state,array $input): bool
    {
        if (!$this->limited($state,'password',fn()=>$this->credentials($state,$input['current_password']??null))) return false;
        return empty($state['totp']) || $this->limited($state,'otp',function()use(&$state,$input){return $this->consume($state,$input['code']??null);});
    }
    private function complete(array $state,?string $selector=null): void
    {
        $session=['authenticated'=>true,'generation'=>$state['generation'],'admin_ip'=>$this->ip()];
        if ($selector!==null) $session['trusted_selector']=$selector;
        $this->renew($session);
    }
    private function cookie(?string $value,int $expires=0): void
    {
        setcookie($this->config['cookie'],$value??'',['expires'=>$value===null?1:$expires,'path'=>$this->config['path'],'secure'=>true,'httponly'=>true,'samesite'=>'Lax']);
        if ($value===null) unset($_COOKIE[$this->config['cookie']]); else $_COOKIE[$this->config['cookie']]=$value;
    }
    private function trust(array &$state): ?array
    {
        $raw=$_COOKIE[$this->config['cookie']]??'';
        if (!is_string($raw) || preg_match('/\A([a-f0-9]{32})\.([a-f0-9]{64})\z/D',$raw,$match)!==1) return null;
        $selector=$match[1]; $device=$state['trusted'][$selector]??null;
        if (!is_array($device)) return null;
        if ($device['expires']<=$this->now() || !hash_equals($device['hash'],hash('sha256',$match[2]))) { unset($state['trusted'][$selector]); return null; }
        $validator=bin2hex(random_bytes(32)); $state['trusted'][$selector]['hash']=hash('sha256',$validator);
        return ['selector'=>$selector,'value'=>$selector.'.'.$validator,'expires'=>$device['expires']];
    }
    private function issue(array &$state): array
    {
        foreach($state['trusted']??[] as $selector=>$device) if ($device['expires']<=$this->now()) unset($state['trusted'][$selector]);
        if (count($state['trusted']??[])>=20) array_shift($state['trusted']);
        $selector=bin2hex(random_bytes(16)); $validator=bin2hex(random_bytes(32)); $expires=$this->now()+15*86400;
        $state['trusted'][$selector]=['hash'=>hash('sha256',$validator),'created'=>$this->now(),'expires'=>$expires];
        return ['selector'=>$selector,'value'=>$selector.'.'.$validator,'expires'=>$expires];
    }
    private function recovery(array &$state): array
    {
        $codes=[]; for($i=0;$i<10;$i++) $codes[]=bin2hex(random_bytes(4)).'-'.bin2hex(random_bytes(4));
        $state['recovery']=array_map(static fn($code)=>hash('sha256',$code),$codes); return $codes;
    }
    private function invalidate(array &$state): void { $state['generation']=bin2hex(random_bytes(24)); $state['trusted']=[]; }
    private function password($value): string
    {
        if (!is_string($value) || strlen($value)<10 || strlen($value)>72) throw new InvalidArgumentException('Use a password between 10 and 72 bytes.');
        return $value;
    }
    private function username($value): string
    {
        if (!is_string($value) || preg_match('/\A[a-zA-Z0-9_.@-]{3,100}\z/D',$value)!==1) throw new InvalidArgumentException('Username: 3–100 letters, digits, _, ., @ or -.');
        return $value;
    }
    public function action(array $input): array
    {
        $this->retryAfter=0;
        if (($input['code']??'')==='' && isset($input['recovery_code'])) $input['code']=$input['recovery_code'];
        $action=$input['action']??'';
        if ($action==='logout') { $this->renew([]); return ['success'=>true,'csrf'=>$this->csrf()]; }
        if ($action==='setup') { $this->username($input['username']??null); $this->password($input['password']??null); }
        if ($action==='change_password') $this->password($input['password']??null);
        if ($action==='change_username') $this->username($input['username']??null);
        $result=$this->mutate(function(array &$state)use($action,$input): array {
            $error=['error'=>'Invalid credentials or verification code. Wait one minute after five failures.'];
            if ($action==='setup') {
                if (!empty($state['password_hash']) || !$this->limited($state,'password',function()use($input){$token=$this->config['setup_token']??''; return is_string($token) && $token!=='' && is_string($input['setup_token']??null) && hash_equals($token,$input['setup_token']);})) return $error;
                $state['username']=$input['username']; $state['password_hash']=password_hash($input['password'],PASSWORD_DEFAULT); $this->invalidate($state);
                return ['complete'=>$state];
            }
            if ($action==='login') {
                $valid=$this->limited($state,'password',fn()=>$this->credentials($state,$input['password']??null) && is_string($input['username']??null) && hash_equals($state['username']??'admin',$input['username']));
                if (!$valid) return $error;
                if (empty($state['generation'])) $state['generation']=bin2hex(random_bytes(24));
                if (empty($state['totp'])) return ['complete'=>$state];
                $trust=$this->trust($state);
                return $trust!==null ? ['complete'=>$state,'trust'=>$trust] : ['pending'=>$state['generation']];
            }
            if ($action==='verify_2fa') {
                if (!$this->pending() || !hash_equals($state['generation']??'',$_SESSION['pending']??'')) return $error;
                if (empty($state['totp']) || !$this->limited($state,'otp',function()use(&$state,$input){return $this->consume($state,$input['code']??null);})) return $error;
                $trust=($input['remember']??'')==='1'?$this->issue($state):null;
                return ['complete'=>$state,'trust'=>$trust];
            }
            if (!$this->current($state)) return ['error'=>'unauthorized'];
            if ($action==='revoke_device' || $action==='revoke_all_devices') {
                if ($action==='revoke_all_devices') $state['trusted']=[];
                else { $selector=$input['selector']??null; if (!is_string($selector) || preg_match('/\A[a-f0-9]{32}\z/D',$selector)!==1) return $error; unset($state['trusted'][$selector]); }
                return ['success'=>true];
            }
            if ($action==='confirm_2fa') {
                $enrollment=$_SESSION['enrollment']??null;
                if (!is_array($enrollment) || ($enrollment['until']??0)<=$this->now() || !empty($state['totp']) || !hash_equals($state['generation'],$enrollment['generation']??'')) return $error;
                $candidate=$state; $candidate['totp']=$enrollment['secret']; $candidate['last_step']=-1;
                if (!$this->limited($state,'otp',function()use(&$candidate,$input){return $this->consume($candidate,$input['code']??null,false);})) return $error;
                $state['totp']=$candidate['totp']; $state['last_step']=$candidate['last_step']; $codes=$this->recovery($state); $this->invalidate($state);
                return ['complete'=>$state,'recovery_codes'=>$codes];
            }
            if (!$this->proof($state,$input)) return $error;
            if ($action==='begin_2fa') {
                if (!empty($state['totp'])) return ['error'=>'Disable existing 2FA with your password and a fresh code before resetting it.'];
                $otp=OTPHP\TOTP::generate(null,20); $otp->setLabel($state['username']); $otp->setIssuer($this->config['issuer']);
                return ['enrollment'=>['secret'=>$this->encrypt($otp->getSecret()),'generation'=>$state['generation'],'until'=>$this->now()+600],'uri'=>$otp->getProvisioningUri(),'manual_secret'=>$otp->getSecret()];
            }
            if ($action==='change_password') $state['password_hash']=password_hash($input['password'],PASSWORD_DEFAULT);
            elseif ($action==='change_username') $state['username']=$input['username'];
            elseif ($action==='disable_2fa') { unset($state['totp'],$state['last_step'],$state['recovery']); }
            elseif ($action==='regenerate_recovery') {
                if (empty($state['totp'])) return $error;
                $codes=$this->recovery($state); $this->invalidate($state); return ['complete'=>$state,'recovery_codes'=>$codes];
            } else throw new InvalidArgumentException('Unknown authentication action.');
            $this->invalidate($state); return ['complete'=>$state];
        });
        if (isset($result['error'])) { if ($this->retryAfter>0) throw new NiraAdminRateLimit($this->retryAfter); throw new DomainException($result['error']); }
        if (isset($result['pending'])) { $this->renew(['pending'=>$result['pending'],'pending_until'=>$this->now()+300]); $this->cookie(null); }
        if (isset($result['complete'])) {
            $trust=$result['trust']??null; $this->complete($result['complete'],$trust['selector']??null);
            if (is_array($trust)) $this->cookie($trust['value'],$trust['expires']);
            elseif ($action!=='login') $this->cookie(null);
        }
        if (isset($result['enrollment'])) $_SESSION['enrollment']=$result['enrollment'];
        if (isset($result['uri'])) {
            // Bacon performs all QR encoding; render integer modules only. No XMLWriter/GD/Imagick dependency.
            $matrix=BaconQrCode\Encoder\Encoder::encode($result['uri'],BaconQrCode\Common\ErrorCorrectionLevel::M())->getMatrix();
            $size=$matrix->getWidth()+8; $path='';
            for($y=0;$y<$matrix->getHeight();$y++) for($x=0;$x<$matrix->getWidth();$x++) if ($matrix->get($x,$y)===1) $path.='M'.($x+4).' '.($y+4).'h1v1h-1z';
            $result['qr_svg']='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '.$size.' '.$size.'" shape-rendering="crispEdges"><path fill="#fff" d="M0 0h'.$size.'v'.$size.'H0z"/><path fill="#000" d="'.$path.'"/></svg>';
        }
        unset($result['complete'],$result['pending'],$result['trust'],$result['enrollment']);
        return ['success'=>true]+$result+['csrf'=>$this->csrf(),'pending_2fa'=>$this->pending()];
    }
}
