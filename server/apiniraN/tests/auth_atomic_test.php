<?php
declare(strict_types=1);
// Both production storage adapters; only test-owned temporary directories are configured.
function fixture_auth(array $input): NiraAdminAuth {
    putenv('NIRAN_ADMIN_TOTP_KEY='.$input['key']);putenv('NIRA_SUB_ADMIN_TOTP_KEY='.$input['key']);
    if ($input['app']==='registry') {
        putenv('NIRAN_REGISTRY_DB='.$input['directory'].'/registry.sqlite');
        require_once dirname(__DIR__).'/registry.php';require_once dirname(__DIR__).'/admin_auth.php';
        return panel_auth(registry_database());
    }
    putenv('NIRA_STORAGE_DIR='.$input['directory']);
    require_once $input['my_sub'].'/shared/auth.php';return nira_auth();
}
if (($argv[1]??'')==='--request') {
    $input=json_decode($argv[2],true,32,JSON_THROW_ON_ERROR);$auth=fixture_auth($input);
    $_SESSION=['pending'=>$input['generation'],'pending_until'=>time()+300];$_COOKIE=[];$_SERVER['REMOTE_ADDR']='192.0.2.20';
    try {$auth->action(['action'=>'verify_2fa','code'=>$input['code']]);$ok=$auth->authenticated();}catch(DomainException $expected){$ok=false;}
    echo json_encode(['authenticated'=>$ok]);exit;
}
require_once dirname(__DIR__).'/admin-auth/AdminAuth.php';
$mySub=getenv('NIRA_TEST_MYSUB_ROOT')?:dirname(__DIR__,4).'/my-sub';
$root=sys_get_temp_dir().'/nira-auth-atomic-'.bin2hex(random_bytes(8));mkdir($root,0700);
$checks=[];
try {
    foreach(['registry','my-sub'] as $app) {
        $dir=$root.'/'.$app;mkdir($dir,0700);$key=random_bytes(32);$generation=bin2hex(random_bytes(24));$secret='GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';$recovery=bin2hex(random_bytes(4)).'-'.bin2hex(random_bytes(4));
        $iv=random_bytes(12);$tag='';$aad=$app==='registry'?'nira-registry-admin:v1':'nira-subscription-admin:v1';
        $cipher=openssl_encrypt($secret,'aes-256-gcm',$key,OPENSSL_RAW_DATA,$iv,$tag,$aad);
        $step=intdiv(time(),30);$state=['auth_version'=>1,'username'=>'fixture-admin','password_hash'=>password_hash('fixture-password',PASSWORD_DEFAULT),'generation'=>$generation,'totp'=>['iv'=>base64_encode($iv),'tag'=>base64_encode($tag),'cipher'=>base64_encode($cipher)],'last_step'=>$step-1,'recovery'=>[hash('sha256',$recovery)]];
        if ($app==='registry') {
            putenv('NIRAN_REGISTRY_DB='.$dir.'/registry.sqlite');require_once dirname(__DIR__).'/registry.php';$pdo=registry_database();
            $pdo->prepare('INSERT INTO admin_settings (setting_key,setting_value,updated_at) VALUES (?,?,?)')->execute(['admin_auth_v1',json_encode($state),registry_now()]);unset($pdo);
        } else file_put_contents($dir.'/auth.state.php',"<?php http_response_code(404); exit; ?>\n".json_encode($state));
        foreach(['TOTP'=>OTPHP\TOTP::create($secret)->at($step*30),'recovery'=>$recovery] as $kind=>$code) {
            $input=['app'=>$app,'directory'=>$dir,'key'=>base64_encode($key),'generation'=>$generation,'my_sub'=>$mySub,'code'=>$code];$workers=[];
            for($i=0;$i<2;$i++) {$process=proc_open([PHP_BINARY,__FILE__,'--request',json_encode($input,JSON_THROW_ON_ERROR)],[1=>['pipe','w'],2=>['pipe','w']],$pipes);if(!is_resource($process))throw new RuntimeException('Worker unavailable');$workers[]=[$process,$pipes];}
            $success=0;
            foreach($workers as [$process,$pipes]) {$output=stream_get_contents($pipes[1]);$error=stream_get_contents($pipes[2]);fclose($pipes[1]);fclose($pipes[2]);if(proc_close($process)!==0 || $error!=='')throw new RuntimeException('Fixture worker failed: '.$error);$value=json_decode($output,true,32,JSON_THROW_ON_ERROR);$success+=(int)$value['authenticated'];}
            if($success!==1)throw new RuntimeException($app.' '.$kind.' concurrent replay was accepted');$checks[]=$app.' '.$kind;
        }
    }
} finally {
    // Only the verified test-owned tree, no application directory or real state.
    $iterator=new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root,FilesystemIterator::SKIP_DOTS),RecursiveIteratorIterator::CHILD_FIRST);
    foreach($iterator as $file) {$file->isDir()?rmdir($file->getPathname()):unlink($file->getPathname());}unset($iterator);rmdir($root);
}
foreach($checks as $label)echo 'PASS atomic concurrent '.$label."\n";
