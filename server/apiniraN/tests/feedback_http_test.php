<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once dirname(__DIR__).'/registry.php';
require_once dirname(__DIR__).'/feedback.php';
require_once dirname(__DIR__).'/admin_auth.php';
$directory = sys_get_temp_dir().'/nira-feedback-http-'.bin2hex(random_bytes(8));
mkdir($directory,0700);
putenv('NIRAN_REGISTRY_DB='.$directory.'/registry.sqlite');
$pdo = registry_database();
feedback_initialize($pdo);
$token = rtrim(strtr(base64_encode(random_bytes(32)),'+/','-_'),'=');
$installation = '12345678-1234-4123-8123-123456789abc';
$device = str_repeat('a',64);
$now = registry_now();
$pdo->prepare('INSERT INTO device_keys (device_key,created_at,updated_at,last_seen) VALUES (?,?,?,?)')->execute([$device,$now,$now,$now]);
$pdo->prepare('INSERT INTO installations (installation_id,device_name,app_version,first_seen,last_seen,created_at,updated_at,device_key,platform,app_name,schema_version,app_build,access_token_hash,access_token_expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)')->execute([$installation,'<script>fixture-device</script>','9.0.0',$now,$now,$now,$now,$device,'android','niraNG',7,999,registry_token_hash($token),gmdate('c',time()+3600)]);
foreach (['bardia-us/niraNG','bardia-us/niraN'] as $repo) {
    registry_set_default($pdo,'latest_release_'.hash('sha256',strtolower($repo)),'9.0.0');
    registry_set_default($pdo,'latest_release_checked_'.hash('sha256',strtolower($repo)),(string)time());
}
$socket = stream_socket_server('tcp://127.0.0.1:0',$errno,$error);
$address = stream_socket_get_name($socket,false); fclose($socket);
$port = (int)substr(strrchr($address,':'),1);
$server = proc_open([PHP_BINARY,'-S','127.0.0.1:'.$port,'-t',dirname(__DIR__)],[0=>['pipe','r'],1=>['file',$directory.'/server.log','a'],2=>['file',$directory.'/server.log','a']],$pipes);
if (!is_resource($server)) throw new RuntimeException('Fixture server unavailable');
$checks = 0;
$expect = static function(bool $ok, string $label) use (&$checks): void { if (!$ok) throw new RuntimeException($label); $checks++; };
$request = static function(array $payload, bool $authorized = true) use ($port,$token): array {
    $headers = "Content-Type: application/json\r\n" . ($authorized ? 'Authorization: Bearer '.$token."\r\n" : '');
    $context = stream_context_create(['http'=>['method'=>'POST','header'=>$headers,'content'=>json_encode($payload,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR),'ignore_errors'=>true,'timeout'=>5]]);
    $body = file_get_contents('http://127.0.0.1:'.$port.'/api.php',false,$context);
    $headers = http_get_last_response_headers(); preg_match('/\s(\d{3})\s/',$headers[0]??'',$match);
    return [(int)($match[1]??0),json_decode((string)$body,true,32,JSON_THROW_ON_ERROR)];
};
$payload = static function(array $extra = []) use ($installation,$device): array {
    return $extra+['action'=>'feedback','schema_version'=>7,'installation_id'=>$installation,'device_key'=>$device,'app_version'=>'9.0.0','app_build'=>999,'request_timestamp'=>time(),'request_nonce'=>rtrim(strtr(base64_encode(random_bytes(16)),'+/','-_'),'='),'report_id'=>'12345678-1234-4123-8123-123456789aaa','message'=>'<script>fixture-message</script>'];
};
$panel = static function(array $seed, array $post = [], array $get = []) use ($directory): string {
    $input = ['database'=>$directory.'/registry.sqlite','sessions'=>$directory,'session_id'=>bin2hex(random_bytes(16)),'seed'=>$seed,'method'=>$post===[]?'GET':'POST','post'=>$post,'get'=>$get];
    $process = proc_open([PHP_BINARY,__DIR__.'/panel_request.php',json_encode($input,JSON_THROW_ON_ERROR)],[1=>['pipe','w'],2=>['pipe','w']],$streams);
    if (!is_resource($process)) throw new RuntimeException('Panel fixture unavailable');
    $html = stream_get_contents($streams[1]); $errors = stream_get_contents($streams[2]);
    fclose($streams[1]); fclose($streams[2]);
    if (proc_close($process)!==0 || $errors!=='') throw new RuntimeException('Panel fixture failed: '.$errors);
    return $html;
};
try {
    for ($i=0;$i<60;$i++) { $probe=@fsockopen('127.0.0.1',$port); if($probe){fclose($probe);break;} usleep(50000); }
    $expect($request($payload(),false)[0]===401,'Bearer required');
    $expect($request($payload(['installation_id'=>'12345678-1234-4123-8123-123456789abd']))[0]===401,'Cannot impersonate another installation');
    $expect($request($payload(['request_timestamp'=>time()-1000]))[0]===400,'Stale timestamp rejected');
    $expect($request($payload(['message'=>str_repeat('x',4001)]))[0]===422,'Message size bounded');
    $expect($request($payload(['identity'=>['device_name'=>'spoof']]))[0]===400,'Identity cannot be client supplied');
    $expect($request($payload(['diagnostics'=>['raw_log'=>'secret']]))[0]===422,'Unknown diagnostic schema rejected');
    $pdo->prepare('UPDATE installations SET access_token_expires_at=?')->execute([gmdate('c',time()-1)]);
    $expect($request($payload())[0]===401,'Expired device rejected');
    $pdo->prepare('UPDATE installations SET access_token_expires_at=?')->execute([gmdate('c',time()+3600)]);
    $pdo->exec("UPDATE device_keys SET access_status='blocked'");
    $expect($request($payload())[0]===403,'Blocked device rejected');
    $pdo->exec("UPDATE device_keys SET access_status='allowed'");
    $config = "{\"test\":\"</textarea><script>fixture-config</script>\"}";
    $extra = ['selected_server'=>['id'=>'owned','name'=>'Profile','protocol'=>'vless','core'=>'xray'],'selected_config'=>$config];
    $response = $request($payload($extra)); $expect($response[0]===201 && $response[1]['duplicate']===false,'Authenticated report created');
    $response = $request($payload($extra)); $expect($response[0]===200 && $response[1]['duplicate']===true,'Retry idempotent with fresh nonce');
    $expect($request($payload($extra+['message'=>'changed']))[0]===409,'Report ID cannot overwrite original');
    $expect((int)$pdo->query('SELECT COUNT(*) FROM feedback_reports')->fetchColumn()===1,'Rejected requests did not insert');
    $saved = $pdo->query('SELECT * FROM feedback_reports')->fetch();
    $expect($saved['selected_config']===$config,'Selected config preserved');
    $identity = json_decode($saved['identity_json'],true,16,JSON_THROW_ON_ERROR);
    $expect($identity['device_name']==='<script>fixture-device</script>' && !isset($identity['access_token_hash']),'Identity from registration excludes auth secret');
    $hash = password_hash('fixture-administrator-password',PASSWORD_DEFAULT);
    $authState = ['auth_version'=>1,'username'=>'admin','password_hash'=>$hash,'generation'=>bin2hex(random_bytes(24))];
    registry_set_default($pdo,'admin_auth_v1',json_encode($authState,JSON_THROW_ON_ERROR));
    $seed = ['csrf'=>'fixture-csrf','authenticated'=>true,'generation'=>$authState['generation']];
    $html = $panel($seed,[],['feedback_id'=>(int)$saved['id']]);
    $expect(str_contains($html,'1 unread') && str_contains($html,'Copy configuration'),'Unread badge and copy UI');
    $expect(!str_contains($html,'<script>fixture-message</script>') && str_contains($html,'&lt;script&gt;fixture-message&lt;/script&gt;'),'Message escaped');
    $expect(!str_contains($html,'</textarea><script>fixture-config') && str_contains($html,'&lt;/textarea&gt;&lt;script&gt;fixture-config'),'Config cannot escape textarea');
    $expect($pdo->query('SELECT read_at FROM feedback_reports')->fetchColumn()===null,'GET does not mark read');
    foreach ([['authenticated'=>true],['pending'=>$authState['generation'],'pending_until'=>time()+300]] as $incomplete) {
        $html = $panel($incomplete+['csrf'=>'fixture-csrf'],['action'=>'feedback_read','feedback_id'=>(string)$saved['id'],'csrf'=>'fixture-csrf'],['feedback_id'=>(int)$saved['id']]);
        $expect(!str_contains($html,'fixture-message') && !str_contains($html,'fixture-config'),'Legacy or pending session cannot view reports');
        $expect($pdo->query('SELECT read_at FROM feedback_reports')->fetchColumn()===null,'Legacy or pending session cannot mark read');
    }
    $html = $panel(['csrf'=>'fixture-csrf'],[],['feedback_id'=>(int)$saved['id']]);
    $expect(!str_contains($html,'fixture-message') && !str_contains($html,'fixture-config'),'Unauthenticated panel reveals no report');
    $post = ['action'=>'feedback_read','feedback_id'=>(string)$saved['id'],'csrf'=>'forged'];
    $panel($seed,$post); $expect($pdo->query('SELECT read_at FROM feedback_reports')->fetchColumn()===null,'Forged CSRF cannot mark read');
    $post['csrf']='fixture-csrf'; $panel($seed,$post);
    $expect($pdo->query('SELECT read_at FROM feedback_reports')->fetchColumn()!==null,'Authenticated CSRF-protected read');
    $emptyPhase = ['frames'=>0,'interval_samples'=>0,'build_over_budget_frames'=>0,'raster_over_budget_frames'=>0,'total_over_budget_frames'=>0,'build_ms'=>null,'raster_ms'=>null,'total_span_ms'=>null,'flutter_interval_ms'=>null];
    $metrics = ['schema_version'=>1,'requested_duration_ms'=>20000,'duration_ms'=>20000,'sample_limit_reached'=>false,'refresh_rate_hz'=>120,
        'display'=>['pixel_ratio'=>3,'width_px'=>1080,'height_px'=>2400],
        'device'=>['manufacturer'=>'<script>fixture-ui</script>','model'=>'Model','android_sdk'=>null,'soc_model'=>null,'power_save'=>null,'thermal_status'=>null],
        'settings'=>['performance_mode'=>false,'glass_ready'=>true],'scenes'=>['feedback'],
        'phases'=>['all'=>$emptyPhase,'initial_5s'=>$emptyPhase,'warm'=>$emptyPhase]];
    $uiPayload = $payload(['report_id'=>'12345678-1234-4123-8123-123456789aab','ui_metrics'=>$metrics]);
    unset($uiPayload['message']);
    $response = $request($uiPayload);
    $expect($response[0]===201, 'Authenticated metrics-only report without text accepted');
    $uiId = (int)$pdo->query("SELECT id FROM feedback_reports WHERE report_id='12345678-1234-4123-8123-123456789aab'")->fetchColumn();
    $html = $panel($seed,[],['feedback_id'=>$uiId]);
    $expect(str_contains($html,'Flutter UI performance') && str_contains($html,'Flutter UI metrics attached'), 'Admin metrics view copy and inbox marker');
    $expect(!str_contains($html,'<script>fixture-ui</script>') && str_contains($html,'&lt;script&gt;fixture-ui&lt;/script&gt;'), 'Metrics label escaped in admin textarea');
    $badUi = $payload(['ui_metrics'=>$metrics+['raw_frames'=>[]]]);
    $expect($request($badUi)[0]===422,'Raw frame attachment rejected');
    $privateHtml = $panel(['csrf'=>'fixture-csrf'],[],['feedback_id'=>$uiId]);
    $expect(!str_contains($privateHtml,'fixture-ui'),'Unauthenticated panel cannot see metrics');
    $expect($request($payload(['message'=>str_repeat('x',100000)]))[0]===413,'Oversized HTTP body rejected');
    $expect($request($payload(['action'=>'status','message'=>str_repeat('x',9000)]))[0]===413,'Old action retains original body limit');
} finally {
    proc_terminate($server); foreach($pipes as $pipe) if(is_resource($pipe)) fclose($pipe); proc_close($server);
    unset($pdo,$request,$panel,$server);
    foreach(new DirectoryIterator($directory) as $file) if($file->isFile()) unlink($file->getPathname());
    rmdir($directory);
}
echo 'Feedback HTTP/admin: '.$checks." checks passed\n";
