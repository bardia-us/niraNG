<?php
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once dirname(__DIR__) . '/feedback.php';

$checks = 0;
function feedback_expect(bool $condition, string $label): void
{
    global $checks;
    if (!$condition) throw new RuntimeException($label);
    $checks++;
}
function feedback_reject(callable $run, string $message): void
{
    try { $run(); } catch (InvalidArgumentException | DomainException $error) {
        feedback_expect($error->getMessage() === $message, 'Expected rejection: ' . $message);
        return;
    }
    throw new RuntimeException('Accepted invalid input: ' . $message);
}

$pdo = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
feedback_initialize($pdo);
feedback_initialize($pdo);
$diagnostics = ['metadata' => ['app' => 'niraNG 1.2.5 (4056)', 'androidSdk' => 35, 'state' => 'connected', 'network' => 'wifi', 'engine' => 'aether', 'mode' => 'masque', 'psiphon' => 'off', 'fingerprint' => 'native', 'ipFamily' => 'v4'],
    'rows' => [['name' => 'https', 'status' => 'pass', 'detail' => 'https_ok', 'ms' => 222]], 'stale' => false];
$content = feedback_content(['message' => "گزارش <script>alert(1)</script>", 'diagnostics' => $diagnostics,
    'selected_server' => ['id' => 'fixture', 'name' => 'Admin-owned profile', 'protocol' => 'vless', 'core' => 'xray'],
    'selected_config' => '{"test":"selected config"}']);
feedback_expect($content['diagnostics'] === $diagnostics, 'Current native diagnostics accepted');
feedback_expect(feedback_content(['message' => '', 'diagnostics' => $diagnostics])['message'] === '', 'Diagnostic-only report accepted');
foreach ([['message' => ''], ['message' => str_repeat('x', 4001)], ['message' => "\xFF"], ['message' => 'x', 'diagnostics' => $diagnostics + ['raw_log' => 'secret']],
    ['message' => 'x', 'diagnostics' => array_replace($diagnostics, ['metadata' => ['token' => 'secret']])],
    ['message' => 'x', 'diagnostics' => array_replace($diagnostics, ['rows' => [['name' => 'https','status' => 'fail','detail' => 'raw exception token','ms' => null]]])],
    ['message' => 'x', 'diagnostics' => array_replace($diagnostics, ['rows' => [['name' => 'https','status' => 'fail','detail' => 'timeout','ms' => -1]]])],
    ['message' => 'x', 'selected_config' => 'config without selection'],
    ['message' => 'x', 'selected_server' => ['id'=>'x','name'=>'x','protocol'=>'vless','core'=>'xray','token'=>'secret']]] as $invalid) {
    feedback_reject(static fn() => feedback_content($invalid), 'invalid_feedback');
}
// Additive migration keeps existing content and old idempotency hashes unchanged.
$legacy = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]);
$legacy->exec('CREATE TABLE feedback_reports (id INTEGER PRIMARY KEY, report_id TEXT,device_key TEXT,installation_id TEXT,identity_json TEXT,message TEXT,diagnostics_json TEXT,selected_server_json TEXT,selected_config TEXT,content_hash TEXT,created_at INTEGER,read_at INTEGER, UNIQUE(device_key,report_id))');
$legacy->exec("INSERT INTO feedback_reports (id,message,content_hash) VALUES (1,'preserved','original-hash')");
feedback_initialize($legacy); feedback_initialize($legacy);
feedback_expect($legacy->query('SELECT message || content_hash FROM feedback_reports WHERE id=1')->fetchColumn() === 'preservedoriginal-hash', 'Migration preserves existing report');
feedback_expect($legacy->query('SELECT ui_metrics_json FROM feedback_reports WHERE id=1')->fetchColumn() === null, 'Migration adds nullable metrics column');
$emptyPhase = ['frames'=>0,'interval_samples'=>0,'build_over_budget_frames'=>0,'raster_over_budget_frames'=>0,'total_over_budget_frames'=>0,'build_ms'=>null,'raster_ms'=>null,'total_span_ms'=>null,'flutter_interval_ms'=>null];
$metrics = ['schema_version'=>1,'requested_duration_ms'=>20000,'duration_ms'=>20000,'sample_limit_reached'=>false,'refresh_rate_hz'=>120.0,
    'display'=>['pixel_ratio'=>3.0,'width_px'=>1080,'height_px'=>2400],
    'device'=>['manufacturer'=>'Fixture','model'=>'Model','android_sdk'=>35,'soc_model'=>null,'power_save'=>false,'thermal_status'=>null],
    'settings'=>['performance_mode'=>false,'glass_ready'=>true],'scenes'=>['home','feedback'],
    'phases'=>['all'=>$emptyPhase,'initial_5s'=>$emptyPhase,'warm'=>$emptyPhase]];
feedback_expect(feedback_content(['ui_metrics'=>$metrics])['ui_metrics'] === $metrics, 'UI metrics-only report without message accepted');
feedback_expect(!array_key_exists('ui_metrics', $content), 'Absent metrics leave legacy content hash input unchanged');
feedback_reject(static fn() => feedback_content(['message'=>null,'ui_metrics'=>$metrics]), 'invalid_feedback');
$legacyHash = hash('sha256',json_encode(feedback_canonical($content),JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR));
$legacy->prepare('INSERT INTO feedback_reports (report_id,device_key,installation_id,identity_json,message,content_hash,created_at) VALUES (?,?,?,?,?,?,?)')->execute(['legacy-id',str_repeat('z',64),'fixture','{}','old',$legacyHash,time()]);
feedback_expect(feedback_store($legacy,['device_key'=>str_repeat('z',64),'installation_id'=>'fixture'],'legacy-id',$content)['duplicate'] === true, 'Pre-migration legacy retry stays idempotent');

$populated = $metrics;
$stats = ['p50'=>5.0,'p95'=>8.0,'p99'=>10.0,'max'=>12.0];
$populated['phases']['all'] = ['frames'=>10,'interval_samples'=>9,'build_over_budget_frames'=>1,'raster_over_budget_frames'=>0,'total_over_budget_frames'=>2,'build_ms'=>$stats,'raster_ms'=>$stats,'total_span_ms'=>$stats,'flutter_interval_ms'=>$stats];
feedback_expect(feedback_ui_metrics($populated) === $populated, 'Finite aggregate percentiles accepted');
foreach ([$metrics + ['raw_frames'=>[]], array_replace($metrics,['duration_ms'=>21001]), array_replace($metrics,['refresh_rate_hz'=>INF]),
    array_replace($metrics,['scenes'=>['private route']]), array_replace($metrics,['device'=>array_replace($metrics['device'],['model'=>str_repeat('x',81)])]),
    array_replace($metrics,['phases'=>array_replace($metrics['phases'],['warm'=>array_replace($emptyPhase,['frames'=>1])])])] as $invalidMetrics) {
    feedback_reject(static fn() => feedback_content(['ui_metrics'=>$invalidMetrics]), 'invalid_feedback');
}
$direct = $diagnostics;
$direct['metadata']['carrier'] = 'همراه اول';
$direct['rows'] = [['name'=>'network','status'=>'pass','detail'=>'direct_https_ok','ms'=>56]];
feedback_expect(feedback_diagnostics($direct) === $direct, 'Direct network result and bounded operator accepted');
$direct['metadata']['carrier'] = "bad\ncarrier";
feedback_expect(feedback_diagnostics($direct) === null, 'Carrier control characters rejected');
$identity = ['device_key' => str_repeat('a',64), 'installation_id' => '12345678-1234-4123-8123-123456789abc', 'device_name' => '<img src=x onerror=alert(1)>'];
$now = time();
$result = feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aaa', $content, $now);
feedback_expect($result['duplicate'] === false, 'New report stored');
$result = feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aaa', $content, $now);
feedback_expect($result['duplicate'] === true && (int)$pdo->query('SELECT COUNT(*) FROM feedback_reports')->fetchColumn() === 1, 'Retry idempotent');
$reordered = $content;
$reordered['diagnostics'] = array_reverse($content['diagnostics'], true);
feedback_expect(feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aaa', $reordered, $now)['duplicate'] === true, 'JSON object key ordering does not duplicate a report');
feedback_reject(static fn() => feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aaa', array_replace($content,['message'=>'changed']), $now), 'report_id_conflict');
feedback_expect(count(feedback_inbox($pdo, true)) === 1, 'Unread inbox');
feedback_expect(feedback_read($pdo, 1), 'Mark read');
feedback_expect(feedback_inbox($pdo, true) === [] && count(feedback_inbox($pdo, false)) === 1, 'Read report retained');
foreach (['b','c'] as $suffix) feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aa'.$suffix, $content, $now);
feedback_reject(static fn() => feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aad', $content, $now), 'feedback_rate_limited');
try { feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aad', $content, $now); }
catch (FeedbackRateLimit $error) { feedback_expect($error->retryAfter > 0 && $error->retryAfter <= 600, 'Accurate quota cooldown'); }
feedback_expect((int)$pdo->query('SELECT COUNT(*) FROM feedback_reports')->fetchColumn() === 3, 'Rate limit does not insert');
feedback_expect($pdo->query('SELECT selected_config FROM feedback_reports WHERE id=1')->fetchColumn() === $content['selected_config'], 'Selected config preserved exactly');
$metricsIdentity = array_replace($identity,['device_key'=>str_repeat('m',64)]);
$metricsContent = feedback_content(['ui_metrics'=>$metrics]);
feedback_store($pdo,$metricsIdentity,'metrics-only',$metricsContent,$now);
feedback_expect($pdo->query("SELECT ui_metrics_json FROM feedback_reports WHERE report_id='metrics-only'")->fetchColumn() === json_encode($metrics,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR), 'UI metrics persisted exactly');
feedback_expect(feedback_store($pdo,$metricsIdentity,'metrics-only',$metricsContent,$now)['duplicate'] === true, 'Metrics retry idempotent');
feedback_reject(static fn() => feedback_store($pdo,$metricsIdentity,'metrics-only',feedback_content(['ui_metrics'=>array_replace($metrics,['duration_ms'=>19999])]),$now), 'report_id_conflict');
$pdo->exec("DELETE FROM feedback_reports WHERE report_id='metrics-only'");
// Insert old and excess fixture rows directly; one real insert must prune all bounds atomically.
$insert = $pdo->prepare('INSERT INTO feedback_reports (report_id,device_key,installation_id,identity_json,message,content_hash,created_at) VALUES (?,?,?,?,?,?,?)');
for ($i = 0; $i < 110; $i++) $insert->execute(['fixture-'.$i,$identity['device_key'],'fixture','{}','x','hash',$now]);
$insert->execute(['old','other-device','fixture','{}','x','hash',$now - 91*86400]);
feedback_store($pdo, $identity, '12345678-1234-4123-8123-123456789aae', $content, $now + 601);
feedback_expect((int)$pdo->query('SELECT COUNT(*) FROM feedback_reports')->fetchColumn() === 100, 'Per-device and age retention');
feedback_expect(count(feedback_inbox($pdo, false)) === 50, 'Inbox page bounded');
feedback_expect(count(feedback_inbox($pdo, false, 60)) <= 50, 'Inbox cursor bounded');
// More than three entries are possible across windows, but the device-wide daily cap remains.
$second = new PDO('sqlite::memory:', null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$day = intdiv($now,86400)*86400;
for ($i = 0; $i < 20; $i++) feedback_store($second, $identity, 'daily-'.$i, $content, $day + intdiv($i,3)*601);
try { feedback_store($second, $identity, 'daily-overflow', $content, $day + 8*601); throw new RuntimeException('Daily quota bypassed'); }
catch (FeedbackRateLimit $error) { feedback_expect($error->retryAfter > 600 && $error->retryAfter <= 86400, 'Daily quota returns daily cooldown'); }
echo 'Feedback functions: ' . $checks . " checks passed\n";
