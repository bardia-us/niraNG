<?php
declare(strict_types=1);
require_once dirname(__DIR__).'/registry.php';
$directory=sys_get_temp_dir().'/nira-capability-http-'.bin2hex(random_bytes(8));mkdir($directory,0700);
putenv('NIRAN_REGISTRY_DB='.$directory.'/registry.sqlite');$pdo=registry_database();
$token=rtrim(strtr(base64_encode(random_bytes(32)),'+/','-_'),'=');
$installation='12345678-1234-4123-8123-123456789abc';$device=str_repeat('a',64);$now=registry_now();
$pdo->prepare('INSERT INTO device_keys (device_key,created_at,updated_at,last_seen) VALUES (?,?,?,?)')->execute([$device,$now,$now,$now]);
$pdo->prepare('INSERT INTO installations (installation_id,app_version,first_seen,last_seen,created_at,updated_at,device_key,platform,app_name,schema_version,app_build,access_token_hash,access_token_expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)')->execute([$installation,'9.0.0',$now,$now,$now,$now,$device,'android','niraNG',7,999,registry_token_hash($token),gmdate('c',time()+3600)]);
$socket=stream_socket_server('tcp://127.0.0.1:0',$errno,$error);$address=stream_socket_get_name($socket,false);fclose($socket);$port=(int)substr(strrchr($address,':'),1);
$env=getenv();$env['NIRANG_ANDROID_SUBSCRIPTION_UPSTREAM']='';$env['NIRAN_WINDOWS_SUBSCRIPTION_UPSTREAM']='';$env['NIRANG_SUBSCRIPTION_UPSTREAM']='';
$server=proc_open([PHP_BINARY,'-S','127.0.0.1:'.$port,'-t',dirname(__DIR__)],[0=>['pipe','r'],1=>['file',$directory.'/server.log','a'],2=>['file',$directory.'/server.log','a']],$pipes,dirname(__DIR__),$env);
if (!is_resource($server)) throw new RuntimeException('Fixture server unavailable');
$request=static function(array $payload,?string $capability='1',bool $authorized=true)use($port,$token): array {
    $headers="Content-Type: application/json\r\n";
    if($capability!==null)$headers.='X-Nira-Profile-Version: '.$capability."\r\n";
    if($authorized)$headers.='Authorization: Bearer '.$token."\r\n";
    $context=stream_context_create(['http'=>['method'=>'POST','header'=>$headers,'content'=>json_encode($payload),'ignore_errors'=>true,'timeout'=>5]]);
    $body=file_get_contents('http://127.0.0.1:'.$port.'/api.php',false,$context);$reply=http_get_last_response_headers();preg_match('/\s(\d{3})\s/',$reply[0]??'',$match);
    return [(int)($match[1]??0),json_decode((string)$body,true,32,JSON_THROW_ON_ERROR)];
};
$payload=static function(array $extra=[])use($installation,$device):array {return $extra+['action'=>'subscription','schema_version'=>7,'installation_id'=>$installation,'device_key'=>$device,'app_version'=>'9.0.0','app_build'=>999,'request_timestamp'=>time(),'request_nonce'=>rtrim(strtr(base64_encode(random_bytes(16)),'+/','-_'),'=')];};
$expect=static function(array $result,int $status,string $error,string $label):void {if($result[0]!==$status || ($result[1]['error']??$result[1]['reason']??null)!==$error)throw new RuntimeException($label.' response mismatch');};
$checks=0;
try {
    for($i=0;$i<60;$i++) {$probe=@fsockopen('127.0.0.1',$port);if($probe){fclose($probe);break;}usleep(50000);}
    // Real authenticated schema-7 subscription reaches the upstream configuration gate without networking.
    foreach(['1','2','01',null] as $header) {$expect($request($payload(),$header),503,'subscription_unavailable','strict exact-body header request');$checks++;}
    $expect($request($payload(['profile_format_version'=>1])),400,'invalid_fields','body contract remains exact');$checks++;
    $expect($request($payload(),'1',false),401,'invalid_device_credentials','capability never bypasses bearer auth');$checks++;
    $pdo->prepare('UPDATE device_keys SET access_status=? WHERE device_key=?')->execute(['blocked',$device]);
    $blocked=$request($payload());if($blocked[0]!==403 || ($blocked[1]['reason']??null)!=='blocked_by_administrator')throw new RuntimeException('Blocked device bypassed authorization');$checks++;
    $pdo->prepare('UPDATE device_keys SET access_status=? WHERE device_key=?')->execute(['allowed',$device]);
    // The authenticated platform may negotiate only the exact supported header.
    if(registry_profile_capability_request_headers('windows',['HTTP_X_NIRA_PROFILE_VERSION'=>'1'])!==['X-Nira-Profile-Version: 1'])throw new RuntimeException('Windows explicit version capability was not forwarded');$checks++;
    $windows='12345678-1234-4123-8123-123456789abd';$windowsKey=str_repeat('b',64);
    $pdo->prepare('INSERT INTO device_keys (device_key,created_at,updated_at,last_seen) VALUES (?,?,?,?)')->execute([$windowsKey,$now,$now,$now]);
    $pdo->prepare('INSERT INTO installations (installation_id,app_version,first_seen,last_seen,created_at,updated_at,device_key,platform,app_name,schema_version,access_token_hash) VALUES (?,?,?,?,?,?,?,?,?,?,?)')->execute([$windows,'9.0.0',$now,$now,$now,$now,$windowsKey,'windows','niraN',5,registry_token_hash($token)]);
    $windowsPayload=['action'=>'subscription','schema_version'=>5,'platform'=>'windows','installation_id'=>$windows,'device_key'=>$windowsKey,'app_name'=>'niraN','app_version'=>'9.0.0'];
    foreach(['1','2','01','1, 1',null] as $header) {
        $expect($request($windowsPayload,$header),503,'subscription_unavailable','Authenticated Windows exact body remains compatible with header on or off');$checks++;
        $capabilityServer=$header===null?[]:['HTTP_X_NIRA_PROFILE_VERSION'=>$header];
        $expected=$header==='1'?['X-Nira-Profile-Version: 1']:[];
        if(registry_profile_capability_request_headers('windows',$capabilityServer)!==$expected)throw new RuntimeException('Windows strict header negotiation mismatch');$checks++;
    }
    $expect($request($windowsPayload,'1',false),401,'invalid_device_credentials','Windows capability cannot bypass bearer auth');$checks++;
    $expect($request($windowsPayload+['profile_format_version'=>1]),400,'invalid_fields','Windows body contract remains exact');$checks++;
    if(registry_profile_capability_request_headers('unknown',['HTTP_X_NIRA_PROFILE_VERSION'=>'1'])!==[])throw new RuntimeException('Unknown platform forwarded profile capability');$checks++;
} finally {
    proc_terminate($server);foreach($pipes as $pipe)if(is_resource($pipe))fclose($pipe);proc_close($server);unset($pdo,$request,$payload);
    foreach(new DirectoryIterator($directory) as $file)if($file->isFile())unlink($file->getPathname());rmdir($directory);
}
echo 'Profile capability HTTP: '.$checks." checks passed\n";
