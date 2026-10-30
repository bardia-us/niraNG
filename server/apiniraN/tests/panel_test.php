<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/registry.php';
if (is_file(dirname(__DIR__) . '/panel.php')) require_once dirname(__DIR__) . '/panel.php';

function panel_assert($expected, $actual, string $message): void
{
    if ($expected !== $actual) throw new RuntimeException($message . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
}

function panel_request(array $input): array
{
    $process = proc_open([PHP_BINARY, __DIR__ . '/panel_request.php', json_encode($input, JSON_THROW_ON_ERROR)], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    if (!is_resource($process)) throw new RuntimeException('Cannot start PHP integration request');
    $output = stream_get_contents($pipes[1]);
    $errors = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    panel_assert(0, proc_close($process), 'integration request exits cleanly: ' . $errors);
    panel_assert('', $errors, 'integration request has no PHP warnings');
    $parts = explode("\nPANEL_TEST_STATE:", $output);
    return ['html' => $parts[0], 'state' => json_decode($parts[1], true, 32, JSON_THROW_ON_ERROR)];
}

$directory = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'niran-panel-test-' . bin2hex(random_bytes(8));
mkdir($directory, 0700);
$databasePath = $directory . DIRECTORY_SEPARATOR . 'registry.sqlite';
putenv('NIRAN_REGISTRY_DB=' . $databasePath);
$pdo = registry_database();
$password = 'fixture-admin-password';
$hash = password_hash($password, PASSWORD_DEFAULT);
$base = ['database' => $databasePath, 'sessions' => $directory, 'hash' => $hash];
$request = static function (array $overrides) use ($base): array {
    return panel_request(array_replace($base, ['session_id' => bin2hex(random_bytes(16)), 'seed' => ['csrf' => 'fixture-csrf']], $overrides));
};
$failures = [];
$run = static function (string $name, callable $test) use (&$failures): void {
    try { $test(); echo "PASS {$name}\n"; }
    catch (Throwable $error) { $failures[] = $name; echo "FAIL {$name}: {$error->getMessage()}\n"; }
};
try {
    foreach (['bardia-us/niraNG' => '1.1.9', 'bardia-us/niraN' => '0.3.9'] as $repo => $version) {
        registry_set_default($pdo, 'latest_release_' . hash('sha256', strtolower($repo)), $version);
    }
    $key = str_repeat('a', 64);
    $pdo->prepare('INSERT INTO device_keys (device_key, created_at, updated_at, last_seen) VALUES (?, ?, ?, ?)')->execute([$key, registry_now(), registry_now(), registry_now()]);
    $insert = $pdo->prepare('INSERT INTO installations (installation_id, device_name, app_version, first_seen, last_seen, created_at, updated_at, device_key, platform, app_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
    foreach ([['one', 'Pixel <script>alert(1)</script> 50%_!', $key, 'android', 'niraNG'], ['two', 'Office Windows', str_repeat('b', 64), 'windows', 'niraN']] as [$id, $name, $deviceKey, $platform, $app]) {
        $insert->execute([$id, $name, '2.0.0', registry_now(), registry_now(), registry_now(), registry_now(), $deviceKey, $platform, $app]);
    }

    require_once dirname(__DIR__).'/admin_auth.php';
    $save = static function(array $value)use($pdo): void {
        $pdo->prepare('INSERT INTO admin_settings (setting_key,setting_value,updated_at) VALUES (?,?,?) ON CONFLICT(setting_key) DO UPDATE SET setting_value=excluded.setting_value')->execute(['admin_auth_v1',json_encode($value),registry_now()]);
    };
    $fresh = static function()use($save,$hash): array { $value=['auth_version'=>1,'username'=>'admin','password_hash'=>$hash,'generation'=>bin2hex(random_bytes(24))]; $save($value); return $value; };
    $seed = static function()use($pdo): array { $value=panel_auth($pdo)->state(); return ['csrf'=>'fixture-csrf','authenticated'=>true,'generation'=>$value['generation'],'admin_ip'=>'192.0.2.10']; };
    $fresh();
    $run('five wrong passwords survive fresh cookies and changing IP',static function()use($request,$fresh,$password): void {
        $fresh();
        for($i=0;$i<5;$i++) $request(['method'=>'POST','ip'=>'192.0.2.'.($i+20),'post'=>['action'=>'login','username'=>'admin','csrf'=>'fixture-csrf','password'=>'wrong']]);
        $result=$request(['method'=>'POST','ip'=>'198.51.100.1','post'=>['action'=>'login','username'=>'admin','csrf'=>'fixture-csrf','password'=>$password]]);
        panel_assert(429,$result['state']['status'],'account rate limited'); panel_assert(false,!empty($result['state']['session']['authenticated']),'correct password denied during lock');
    });
    $run('authenticated sessions survive IP change and ignore forwarded headers',static function()use($request,$fresh,$seed): void {
        $fresh(); $result=$request(['seed'=>$seed(),'ip'=>'192.0.2.11','forwarded'=>'1.2.3.4']);
        panel_assert(true,str_contains($result['html'],'Office Windows'),'address change does not log out a real session');
        panel_assert(null,panel_remote_ip(['REMOTE_ADDR'=>'invalid','HTTP_X_FORWARDED_FOR'=>'192.0.2.10']),'forwarded headers never replace the peer');
    });
    $run('rendered search matches literal wildcards, device key and escapes HTML/SQL',static function()use($request,$fresh,$seed): void {
        $fresh(); $result=$request(['seed'=>$seed(),'get'=>['q'=>'50%_!']]);
        panel_assert(false,str_contains($result['html'],'Office Windows'),'literal wildcard filter'); panel_assert(true,str_contains($result['html'],'&lt;script&gt;'),'device HTML escaped');
        $result=$request(['seed'=>$seed(),'get'=>['q'=>str_repeat('b',64)]]); panel_assert(true,str_contains($result['html'],'Office Windows'),'full key filter'); panel_assert(false,str_contains($result['html'],'Pixel'),'key excludes unrelated device');
        $result=$request(['seed'=>$seed(),'get'=>['q'=>"' OR 1=1 -- <script>"]]); panel_assert(false,str_contains($result['html'],'Office Windows'),'SQL payload remains data'); panel_assert(true,str_contains($result['html'],'&lt;script&gt;'),'search HTML escaped');
    });
    $run('platform UI and separate password-manager form semantics',static function()use($request,$fresh,$seed): void {
        $fresh(); $html=$request(['seed'=>$seed()])['html']; panel_assert(true,str_contains($html,'class="platform android"'),'Android icon'); panel_assert(true,str_contains($html,'class="platform windows"'),'Windows icon'); panel_assert(true,str_contains($html,'autocomplete="new-password"'),'security new password');
        $html=$request([])['html']; panel_assert(true,str_contains($html,'id="nira-registry-login"'),'branded registry login'); panel_assert(true,str_contains($html,'autocomplete="username"'),'username semantics'); panel_assert(true,str_contains($html,'autocomplete="current-password"'),'password semantics');
    });
    $run('concurrent sessions cannot lose failures in SQLite transaction',static function()use($pdo,$base,$fresh,$password,$request): void {
        $fresh(); $processes=[];
        for($i=0;$i<8;$i++) { $input=$base+['session_id'=>bin2hex(random_bytes(16)),'seed'=>['csrf'=>'fixture-csrf'],'method'=>'POST','post'=>['action'=>'login','username'=>'admin','csrf'=>'fixture-csrf','password'=>'bad']]; $proc=proc_open([PHP_BINARY,__DIR__.'/panel_request.php',json_encode($input,JSON_THROW_ON_ERROR)],[1=>['pipe','w'],2=>['pipe','w']],$pipes); $processes[]=[$proc,$pipes]; }
        foreach($processes as [$proc,$pipes]) {stream_get_contents($pipes[1]);$errors=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);panel_assert(0,proc_close($proc),'parallel request clean');panel_assert('',$errors,'no warnings');}
        $state=panel_auth($pdo)->state(); panel_assert(5,$state['limits']['password:account']['count'],'all concurrent failures counted'); panel_assert(true,$state['limits']['password:account']['until']>time(),'persistent lock');
    });
    $run('successful login regenerates session and uses secure scoped cookies',static function()use($request,$fresh,$password): void {
        $fresh(); $id=bin2hex(random_bytes(16)); $result=$request(['session_id'=>$id,'method'=>'POST','post'=>['action'=>'login','username'=>'admin','password'=>$password,'csrf'=>'fixture-csrf']]);
        panel_assert(true,$result['state']['session']['authenticated']??false,'login complete'); panel_assert(false,$id===$result['state']['session_id'],'session regenerated'); panel_assert(true,$result['state']['cookie']['secure'],'HTTPS cookie');panel_assert(true,$result['state']['cookie']['httponly'],'HTTP only');panel_assert('Strict',$result['state']['cookie']['samesite'],'strict session cookie');panel_assert('/apiniraN/',$result['state']['cookie']['path'],'separate realm path');
    });
    $run('strict mode rejects attacker-selected unknown session IDs',static function()use($request): void {
        $id=bin2hex(random_bytes(16)); $result=$request(['session_id'=>$id,'seed'=>null]); panel_assert(false,$id===$result['state']['session_id'],'uninitialized session ID rejected');
    });
    $run('legacy and pending sessions cannot mutate private registry',static function()use($request,$fresh,$pdo,$key): void {
        $value=$fresh();
        foreach([['authenticated'=>true],['pending'=>$value['generation'],'pending_until'=>time()+300]] as $session) { $result=$request(['seed'=>$session+['csrf'=>'fixture-csrf'],'method'=>'POST','post'=>['action'=>'block','device_key'=>$key,'csrf'=>'fixture-csrf']]); panel_assert(false,str_contains($result['html'],'Office Windows'),'no private data before final authentication'); }
        panel_assert('allowed',$pdo->query('SELECT access_status FROM device_keys')->fetchColumn(),'pending cannot mutate device');
    });
    $run('invalid CSRF and HTTP cannot authenticate or mutate',static function()use($request,$fresh,$seed,$pdo,$key,$password): void {
        $fresh(); $before=panel_auth($pdo)->state(); $request(['method'=>'POST','post'=>['action'=>'login','username'=>'admin','password'=>'bad','csrf'=>'forged']]); panel_assert($before,panel_auth($pdo)->state(),'CSRF checked before login limiter');
        $request(['seed'=>$seed(),'method'=>'POST','post'=>['action'=>'block','device_key'=>$key,'csrf'=>'forged']]); panel_assert('allowed',$pdo->query('SELECT access_status FROM device_keys')->fetchColumn(),'CSRF cannot block');
        $result=$request(['https'=>'off','method'=>'POST','post'=>['action'=>'login','username'=>'admin','password'=>$password,'csrf'=>'fixture-csrf']]); panel_assert(400,$result['state']['status'],'HTTP rejected'); panel_assert(false,!empty($result['state']['session']['authenticated']),'HTTP cannot authenticate');
    });
    $run('initial setup needs a private token and stores new identity atomically',static function()use($request,$directory,$password): void {
        $db=$directory.'/fresh.sqlite';
        $base=['database'=>$db,'hash'=>'','setup_token'=>'fixture-host-token','method'=>'POST','post'=>['action'=>'setup','username'=>'new-admin','password'=>$password,'password_confirmation'=>$password,'csrf'=>'fixture-csrf']];
        $denied=$request($base); panel_assert(false,!empty($denied['state']['session']['authenticated']),'public setup disabled');
        $base['post']['setup_token']='fixture-host-token'; $ok=$request($base);panel_assert(true,$ok['state']['session']['authenticated']??false,'token setup works');
        $base['post']['password']='replacement-password'; $base['post']['password_confirmation']='replacement-password'; $again=$request($base);panel_assert(false,!empty($again['state']['session']['authenticated']),'setup cannot overwrite existing account');
        unset($base['post']['password_confirmation'],$base['post']['setup_token']);$base['post']['action']='login';$base['post']['password']=$password;panel_assert(true,$request($base)['state']['session']['authenticated']??false,'initial credentials still valid');
    });
} finally {
    unset($save, $fresh, $seed, $pdo, $insert);
    // Exact test-owned directory only; no production registry is ever touched.
    foreach (new DirectoryIterator($directory) as $file) if ($file->isFile()) unlink($file->getPathname());
    rmdir($directory);
}
if ($failures !== []) exit(1);
echo "panel tests passed\n";
