<?php
declare(strict_types=1);

final class FeedbackRateLimit extends DomainException
{
    public function __construct(public readonly int $retryAfter)
    {
        parent::__construct('feedback_rate_limited');
    }
}

/** Feedback stays in the existing private SQLite file, never in web-root files or logs. */
function feedback_initialize(PDO $pdo): void
{
    $pdo->exec('CREATE TABLE IF NOT EXISTS feedback_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_id TEXT NOT NULL,
        device_key TEXT NOT NULL,
        installation_id TEXT NOT NULL,
        identity_json TEXT NOT NULL,
        message TEXT NOT NULL,
        diagnostics_json TEXT NULL,
        ui_metrics_json TEXT NULL,
        selected_server_json TEXT NULL,
        selected_config TEXT NULL,
        content_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        read_at INTEGER NULL,
        UNIQUE(device_key, report_id)
    )');
    $columns = $pdo->query('PRAGMA table_info(feedback_reports)')->fetchAll(PDO::FETCH_COLUMN, 1);
    if (!in_array('ui_metrics_json', $columns, true)) {
        try { $pdo->exec('ALTER TABLE feedback_reports ADD COLUMN ui_metrics_json TEXT NULL'); }
        catch (PDOException $error) {
            // A second worker may have completed this additive migration meanwhile.
            if (!in_array('ui_metrics_json', $pdo->query('PRAGMA table_info(feedback_reports)')->fetchAll(PDO::FETCH_COLUMN, 1), true)) throw $error;
        }
    }
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_feedback_unread ON feedback_reports(read_at, id DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_feedback_device ON feedback_reports(device_key, id DESC)');
    $pdo->exec('CREATE TABLE IF NOT EXISTS feedback_rate_limits (
        device_key TEXT NOT NULL, window_start INTEGER NOT NULL, window_seconds INTEGER NOT NULL,
        request_count INTEGER NOT NULL, PRIMARY KEY(device_key, window_start, window_seconds)
    )');
}

function feedback_text($value, int $limit, bool $empty = false): ?string
{
    if (!is_string($value) || strlen($value) > $limit || preg_match('//u', $value) !== 1
        || preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $value) === 1
        || (!$empty && trim($value) === '')) return null;
    return $value;
}

function feedback_diagnostics($value): ?array
{
    if (!is_array($value) || array_diff(array_keys($value), ['metadata', 'rows', 'stale']) !== []
        || !isset($value['metadata'], $value['rows'], $value['stale']) || !is_bool($value['stale'])
        || !is_array($value['metadata']) || !is_array($value['rows']) || !array_is_list($value['rows'])
        || count($value['rows']) > 4) return null;
    $metadata = $value['metadata'];
    if (array_diff(['app','androidSdk','state','network'], array_keys($metadata)) !== []) return null;
    $enums = [
        'state' => ['disconnected','preparing','connecting','connected','restarting','switching','reconnecting','stopping','error'],
        'network' => ['none','wifi','mobile','other'], 'engine' => ['xray','sing-box','aether','unknown'],
        'mode' => ['masque','wireguard','wireguard-over-masque','warp-in-warp','masque-in-masque'],
        'psiphon' => ['off','chain','reverse','only'],
        'fingerprint' => ['native','chrome','chrome-120','firefox','semi-python','go'],
        'ipFamily' => ['v4','v6','both'],
    ];
    if (array_diff(array_keys($metadata), array_merge(['app','androidSdk','carrier'], array_keys($enums))) !== []) return null;
    foreach ($metadata as $key => $item) {
        if ($key === 'app') {
            if (!is_string($item) || preg_match('/^niraNG [0-9A-Za-z.+_-]{1,64} \([0-9]{1,10}\)$/D', $item) !== 1) return null;
        } elseif ($key === 'carrier') {
            if (feedback_text($item, 80) === null || preg_match('/[\r\n\t]/', $item) === 1) return null;
        } elseif ($key === 'androidSdk') {
            if (!is_int($item) || $item < 21 || $item > 1000) return null;
        } elseif (!is_string($item) || !in_array($item, $enums[$key], true)) return null;
    }
    $details = ['direct_https_ok','direct_https_failed','direct_unknown','network_changed','no_network','network_present','core_error','disconnected','busy','core_running','core_missing',
        'no_probe_input','not_tested','https_ok','tcp_ok','tcp_failed','tcp_unavailable','timeout','dns_failed','tls_failed','proxy_unreachable','probe_failed'];
    $seen = [];
    foreach ($value['rows'] as $row) {
        if (!is_array($row) || count($row) !== 4 || array_diff(array_keys($row), ['name','status','detail','ms']) !== []
            || !in_array($row['name'] ?? null, ['network','core','tcp','https'], true)
            || isset($seen[$row['name']]) || !in_array($row['status'] ?? null, ['pass','fail','unknown','warning'], true)
            || !in_array($row['detail'] ?? null, $details, true) || !array_key_exists('ms', $row)
            || ($row['ms'] !== null && (!is_int($row['ms']) || $row['ms'] < 0 || $row['ms'] > 600000))) return null;
        $seen[$row['name']] = true;
    }
    if (strlen(json_encode($value, JSON_THROW_ON_ERROR)) > 16384) return null;
    return $value;
}

/** Closed, aggregate-only Flutter measurements: never raw frames, routes or logs. */
function feedback_ui_metrics($value): ?array
{
    $object = static fn($item, array $keys): bool => is_array($item)
        && count($item) === count($keys) && array_diff(array_keys($item), $keys) === [];
    $integer = static fn($item, int $min, int $max): bool => is_int($item) && $item >= $min && $item <= $max;
    $number = static fn($item, float $min, float $max): bool => (is_int($item) || is_float($item))
        && is_finite((float)$item) && $item >= $min && $item <= $max;
    $label = static fn($item): bool => feedback_text($item, 80) !== null && preg_match('/[\r\n\t]/', $item) !== 1;
    if (!$object($value, ['schema_version','requested_duration_ms','duration_ms','sample_limit_reached','refresh_rate_hz','display','device','settings','scenes','phases'])
        || $value['schema_version'] !== 1 || $value['requested_duration_ms'] !== 20000
        || !$integer($value['duration_ms'], 0, 21000) || !is_bool($value['sample_limit_reached'])
        || ($value['refresh_rate_hz'] !== null && !$number($value['refresh_rate_hz'], 1, 1000))) return null;
    $display = $value['display'];
    if (!$object($display, ['pixel_ratio','width_px','height_px']) || !$number($display['pixel_ratio'], 0.01, 10)
        || !$integer($display['width_px'], 1, 20000) || !$integer($display['height_px'], 1, 20000)) return null;
    $device = $value['device'];
    if (!$object($device, ['manufacturer','model','android_sdk','soc_model','power_save','thermal_status'])
        || !$label($device['manufacturer']) || !$label($device['model']) || ($device['android_sdk'] !== null && !$integer($device['android_sdk'], 21, 1000))
        || ($device['soc_model'] !== null && !$label($device['soc_model'])) || ($device['power_save'] !== null && !is_bool($device['power_save']))
        || ($device['thermal_status'] !== null && !$integer($device['thermal_status'], 0, 6))) return null;
    $settings = $value['settings'];
    if (!$object($settings, ['performance_mode','glass_ready']) || !is_bool($settings['performance_mode']) || !is_bool($settings['glass_ready'])) return null;
    if (!is_array($value['scenes']) || !array_is_list($value['scenes']) || count($value['scenes']) > 8) return null;
    foreach ($value['scenes'] as $scene) if (!in_array($scene, ['startup','home','servers','settings','feedback','other'], true)) return null;
    if (count(array_unique($value['scenes'])) !== count($value['scenes'])) return null;
    if (!$object($value['phases'], ['all','initial_5s','warm'])) return null;
    foreach ($value['phases'] as $phase) {
        if (!$object($phase, ['frames','interval_samples','build_over_budget_frames','raster_over_budget_frames','total_over_budget_frames','build_ms','raster_ms','total_span_ms','flutter_interval_ms'])) return null;
        foreach (['frames','interval_samples','build_over_budget_frames','raster_over_budget_frames','total_over_budget_frames'] as $key) if (!$integer($phase[$key], 0, 4096)) return null;
        if ($phase['build_over_budget_frames'] > $phase['frames'] || $phase['raster_over_budget_frames'] > $phase['frames'] || $phase['total_over_budget_frames'] > $phase['frames']) return null;
        foreach (['build_ms','raster_ms','total_span_ms','flutter_interval_ms'] as $key) {
            $stats = $phase[$key];
            $samples = $phase[$key === 'flutter_interval_ms' ? 'interval_samples' : 'frames'];
            if ($samples === 0) { if ($stats !== null) return null; continue; }
            if (!$object($stats, ['p50','p95','p99','max'])) return null;
            foreach ($stats as $item) if (!$number($item, 0, 60000)) return null;
            if ($stats['p50'] > $stats['p95'] || $stats['p95'] > $stats['p99'] || $stats['p99'] > $stats['max']) return null;
        }
    }
    if (strlen(json_encode($value, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)) > 24576) return null;
    return $value;
}

function feedback_content(array $payload): array
{
    $message = feedback_text(array_key_exists('message', $payload) ? $payload['message'] : '', 4000, true);
    $metrics = array_key_exists('ui_metrics', $payload) ? feedback_ui_metrics($payload['ui_metrics']) : null;
    $diagnostics = array_key_exists('diagnostics', $payload) ? feedback_diagnostics($payload['diagnostics']) : null;
    $server = $payload['selected_server'] ?? null;
    $config = array_key_exists('selected_config', $payload) ? feedback_text($payload['selected_config'], 65536) : null;
    if ($message === null || (array_key_exists('diagnostics', $payload) && $diagnostics === null)
        || (array_key_exists('ui_metrics', $payload) && $metrics === null)
        || (trim($message) === '' && $diagnostics === null && $metrics === null)
        || (array_key_exists('selected_config', $payload) && $config === null)) {
        throw new InvalidArgumentException('invalid_feedback');
    }
    if (array_key_exists('selected_server', $payload)) {
        if (!is_array($server) || count($server) !== 4 || array_diff(array_keys($server), ['id','name','protocol','core']) !== []
            || feedback_text($server['id'] ?? null, 160) === null || feedback_text($server['name'] ?? null, 512) === null
            || !is_string($server['protocol'] ?? null) || preg_match('/^[a-zA-Z0-9_-]{1,32}$/D', $server['protocol']) !== 1
            || !in_array($server['core'] ?? null, ['xray','sing-box','aether','unknown'], true)) {
            throw new InvalidArgumentException('invalid_feedback');
        }
    }
    if ($config !== null && $server === null) throw new InvalidArgumentException('invalid_feedback');
    $content = ['message' => $message, 'diagnostics' => $diagnostics, 'selected_server' => $server, 'selected_config' => $config];
    // Omit absent metrics so stored hashes from older clients remain idempotent.
    if ($metrics !== null) $content['ui_metrics'] = $metrics;
    return $content;
}

function feedback_canonical($value)
{
    if (!is_array($value)) return $value;
    if (!array_is_list($value)) ksort($value, SORT_STRING);
    foreach ($value as &$item) $item = feedback_canonical($item);
    unset($item);
    return $value;
}

/** Writer reservation keeps idempotency, quotas and insertion atomic across PHP workers. */
function feedback_store(PDO $pdo, array $identity, string $reportId, array $content, ?int $now = null): array
{
    feedback_initialize($pdo);
    $timestamp = $now ?? time();
    $hash = hash('sha256', json_encode(feedback_canonical($content), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
    $pdo->exec('BEGIN IMMEDIATE');
    try {
        $prior = $pdo->prepare('SELECT content_hash FROM feedback_reports WHERE device_key = ? AND report_id = ?');
        $prior->execute([$identity['device_key'], $reportId]);
        $previous = $prior->fetchColumn();
        if (is_string($previous)) {
            if (!hash_equals($previous, $hash)) throw new DomainException('report_id_conflict');
            $pdo->exec('COMMIT');
            return ['ok' => true, 'report_id' => $reportId, 'duplicate' => true];
        }
        foreach ([600 => 3, 86400 => 20] as $seconds => $limit) {
            $start = intdiv($timestamp, $seconds) * $seconds;
            $rate = $pdo->prepare('INSERT INTO feedback_rate_limits (device_key,window_start,window_seconds,request_count) VALUES (?,?,?,1)
                ON CONFLICT(device_key,window_start,window_seconds) DO UPDATE SET request_count = request_count + 1');
            $rate->execute([$identity['device_key'], $start, $seconds]);
            $count = $pdo->prepare('SELECT request_count FROM feedback_rate_limits WHERE device_key = ? AND window_start = ? AND window_seconds = ?');
            $count->execute([$identity['device_key'], $start, $seconds]);
            if ((int)$count->fetchColumn() > $limit) throw new FeedbackRateLimit($start + $seconds - $timestamp);
        }
        $encode = static fn($value): ?string => $value === null ? null : json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $insert = $pdo->prepare('INSERT INTO feedback_reports (report_id,device_key,installation_id,identity_json,message,diagnostics_json,selected_server_json,selected_config,content_hash,created_at,ui_metrics_json)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)');
        $insert->execute([$reportId, $identity['device_key'], $identity['installation_id'], $encode($identity), $content['message'],
            $encode($content['diagnostics']), $encode($content['selected_server']), $content['selected_config'], $hash, $timestamp, $encode($content['ui_metrics'] ?? null)]);
        $pdo->prepare('DELETE FROM feedback_rate_limits WHERE window_start < ?')->execute([$timestamp - 172800]);
        $pdo->prepare('DELETE FROM feedback_reports WHERE created_at < ?')->execute([$timestamp - 90 * 86400]);
        $pdo->prepare('DELETE FROM feedback_reports WHERE device_key = ? AND id NOT IN
            (SELECT id FROM feedback_reports WHERE device_key = ? ORDER BY id DESC LIMIT 100)')->execute([$identity['device_key'], $identity['device_key']]);
        $pdo->exec('DELETE FROM feedback_reports WHERE id NOT IN (SELECT id FROM feedback_reports ORDER BY id DESC LIMIT 5000)');
        $pdo->exec('COMMIT');
        return ['ok' => true, 'report_id' => $reportId, 'duplicate' => false];
    } catch (Throwable $exception) {
        $pdo->exec('ROLLBACK');
        throw $exception;
    }
}

function feedback_inbox(PDO $pdo, bool $unreadOnly, int $before = 0): array
{
    feedback_initialize($pdo);
    // Fetch bodies only on the selected detail page; the inbox stays bounded and light.
    $query = 'SELECT id,report_id,identity_json,message,created_at,read_at, selected_config IS NOT NULL AS has_config, ui_metrics_json IS NOT NULL AS has_ui_metrics FROM feedback_reports WHERE 1=1';
    if ($unreadOnly) $query .= ' AND read_at IS NULL';
    if ($before > 0) $query .= ' AND id < :before';
    $statement = $pdo->prepare($query . ' ORDER BY id DESC LIMIT 50');
    $statement->execute($before > 0 ? [':before' => $before] : []);
    return $statement->fetchAll();
}

function feedback_read(PDO $pdo, int $id): bool
{
    $statement = $pdo->prepare('UPDATE feedback_reports SET read_at = COALESCE(read_at, :now) WHERE id = :id');
    $statement->execute([':now' => time(), ':id' => $id]);
    return $statement->rowCount() > 0;
}
