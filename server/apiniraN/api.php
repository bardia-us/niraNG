<?php
declare(strict_types=1);

require_once __DIR__ . '/registry.php';
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function respond(int $status, array $body): void
{
    header('Content-Type: application/json; charset=utf-8');
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function valid_text($value, int $max, bool $allowEmpty = false): ?string
{
    if (!is_string($value)) return null;
    $value = trim($value);
    if ((!$allowEmpty && $value === '') || strlen($value) > $max || preg_match('//u', $value) !== 1) return null;
    return preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $value) === 1 ? null : $value;
}

function valid_installation_id($value): ?string
{
    $value = valid_text($value, 36);
    return $value !== null && preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $value) === 1
        ? strtolower($value) : null;
}

function valid_device_key($value): ?string
{
    $value = valid_text($value, 64);
    return $value !== null && preg_match('/^[0-9a-f]{64}$/', $value) === 1 ? strtolower($value) : null;
}

function require_exact_fields(array $payload, array $required): void
{
    if (array_diff(array_keys($payload), $required) !== [] || array_diff($required, array_keys($payload)) !== []) {
        respond(400, ['ok' => false, 'error' => 'invalid_fields']);
    }
}

function parse_timestamp($value): ?string
{
    $value = valid_text($value, 40);
    if ($value === null) return null;
    try {
        new DateTimeImmutable($value);
        return $value;
    } catch (Exception $exception) {
        return null;
    }
}

function upsert_registration(PDO $pdo, array $record, ?string $tokenHash, bool $reinstalledAfterBlock): void
{
    if ($record['device_key'] !== null) {
        $existing = $pdo->prepare(
            'SELECT installation_id FROM installations WHERE device_key = :device_key LIMIT 1'
        );
        $existing->execute([':device_key' => $record['device_key']]);
        $currentInstallation = $existing->fetchColumn();
        if (is_string($currentInstallation)) {
            $statement = $pdo->prepare(
                'UPDATE installations SET
                    installation_id = :installation_id,
                    device_model = :device_model, device_name = :device_name,
                    windows_username = :windows_username, windows_version = :windows_version,
                    platform = :platform, manufacturer = :manufacturer, model = :model,
                    os_version = :os_version, app_name = :app_name, app_version = :app_version,
                    last_seen = :last_seen, updated_at = :updated_at,
                    access_token_hash = COALESCE(:access_token_hash, access_token_hash),
                    reinstalled_after_block = MAX(reinstalled_after_block, :reinstalled_after_block),
                    bypass_attempts = bypass_attempts + :bypass_attempts,
                    last_access_status = :last_access_status,
                    schema_version = :schema_version
                 WHERE device_key = :device_key'
            );
            $statement->execute([
                ':installation_id' => $record['installation_id'],
                ':device_model' => $record['device_model'], ':device_name' => $record['device_name'],
                ':windows_username' => $record['windows_username'], ':windows_version' => $record['windows_version'],
                ':platform' => $record['platform'], ':manufacturer' => $record['manufacturer'],
                ':model' => $record['model'], ':os_version' => $record['os_version'],
                ':app_name' => $record['app_name'], ':app_version' => $record['app_version'],
                ':last_seen' => $record['last_seen'], ':updated_at' => registry_now(),
                ':access_token_hash' => $tokenHash,
                ':reinstalled_after_block' => $reinstalledAfterBlock ? 1 : 0,
                ':bypass_attempts' => $reinstalledAfterBlock ? 1 : 0,
                ':last_access_status' => $record['last_access_status'],
                ':schema_version' => $record['schema_version'], ':device_key' => $record['device_key'],
            ]);
            return;
        }
    }
    $statement = $pdo->prepare(
        'INSERT INTO installations (
            installation_id, device_model, device_name, windows_username, windows_version,
            platform, manufacturer, model, os_version, app_name, app_version,
            first_seen, last_seen, created_at, updated_at, device_key,
            access_token_hash, reinstalled_after_block, bypass_attempts, last_access_status
            , schema_version
         ) VALUES (
            :installation_id, :device_model, :device_name, :windows_username, :windows_version,
            :platform, :manufacturer, :model, :os_version, :app_name, :app_version,
            :first_seen, :last_seen, :created_at, :updated_at, :device_key,
            :access_token_hash, :reinstalled_after_block, :bypass_attempts, :last_access_status
            , :schema_version
         ) ON CONFLICT(installation_id) DO UPDATE SET
            device_model = excluded.device_model, device_name = excluded.device_name,
            windows_username = excluded.windows_username, windows_version = excluded.windows_version,
            platform = excluded.platform, manufacturer = excluded.manufacturer, model = excluded.model,
            os_version = excluded.os_version, app_name = excluded.app_name, app_version = excluded.app_version,
            last_seen = excluded.last_seen, updated_at = excluded.updated_at, device_key = excluded.device_key,
            access_token_hash = COALESCE(excluded.access_token_hash, installations.access_token_hash),
            reinstalled_after_block = MAX(installations.reinstalled_after_block, excluded.reinstalled_after_block),
            bypass_attempts = installations.bypass_attempts + excluded.bypass_attempts,
            last_access_status = excluded.last_access_status,
            schema_version = excluded.schema_version'
    );
    $statement->execute([
        ':installation_id' => $record['installation_id'], ':device_model' => $record['device_model'],
        ':device_name' => $record['device_name'], ':windows_username' => $record['windows_username'],
        ':windows_version' => $record['windows_version'], ':platform' => $record['platform'],
        ':manufacturer' => $record['manufacturer'], ':model' => $record['model'],
        ':os_version' => $record['os_version'], ':app_name' => $record['app_name'],
        ':app_version' => $record['app_version'], ':first_seen' => $record['first_seen'],
        ':last_seen' => $record['last_seen'], ':created_at' => registry_now(), ':updated_at' => registry_now(),
        ':device_key' => $record['device_key'], ':access_token_hash' => $tokenHash,
        ':reinstalled_after_block' => $reinstalledAfterBlock ? 1 : 0,
        ':bypass_attempts' => $reinstalledAfterBlock ? 1 : 0,
        ':last_access_status' => $record['last_access_status'],
        ':schema_version' => $record['schema_version'],
    ]);
}

function handle_registration(PDO $pdo, array $payload, int $schema): void
{
    $fields = $schema === 5
        ? ['action', 'schema_version', 'platform', 'installation_id', 'device_key', 'device_name', 'windows_username', 'windows_version', 'app_name', 'app_version', 'first_seen', 'last_seen']
        : ($schema === 4
        ? ['action', 'schema_version', 'platform', 'installation_id', 'device_key', 'device_name', 'manufacturer', 'model', 'os_version', 'app_name', 'app_version', 'first_seen', 'last_seen']
        : ($schema === 3
            ? ['schema_version', 'platform', 'installation_id', 'device_name', 'manufacturer', 'model', 'os_version', 'app_name', 'app_version', 'first_seen', 'last_seen']
            : ($schema === 2
                ? ['schema_version', 'installation_id', 'device_name', 'windows_username', 'windows_version', 'app_version', 'first_seen', 'last_seen']
                : ['schema_version', 'installation_id', 'device_model', 'windows_version', 'app_version', 'first_seen', 'last_seen'])));
    require_exact_fields($payload, $fields);
    $installationId = valid_installation_id($payload['installation_id'] ?? null);
    $version = registry_valid_version($payload['app_version'] ?? null);
    $firstSeen = parse_timestamp($payload['first_seen'] ?? null);
    $lastSeen = parse_timestamp($payload['last_seen'] ?? null);
    $deviceKey = $schema >= 4 ? valid_device_key($payload['device_key'] ?? null) : null;
    if ($installationId === null || $version === null || $firstSeen === null || $lastSeen === null || ($schema >= 4 && $deviceKey === null)) {
        respond(422, ['ok' => false, 'error' => 'validation_failed']);
    }
    $android = $schema === 3 || $schema === 4;
    $platform = $android ? 'android' : 'windows';
    $minimum = registry_minimum_version($pdo, $platform);
    $record = [
        'installation_id' => $installationId,
        'device_model' => $schema === 1 ? valid_text($payload['device_model'] ?? null, 160) : '',
        'device_name' => $schema >= 2 ? valid_text($payload['device_name'] ?? null, 160) : '',
        'windows_username' => ($schema === 2 || $schema === 5) ? valid_text($payload['windows_username'] ?? null, 160) : '',
        'windows_version' => (!$android) ? valid_text($payload['windows_version'] ?? null, 160) : '',
        'platform' => $schema >= 3 ? valid_text($payload['platform'] ?? null, 16) : 'windows',
        'manufacturer' => $android ? valid_text($payload['manufacturer'] ?? null, 160) : '',
        'model' => $android ? valid_text($payload['model'] ?? null, 160) : '',
        'os_version' => $android ? valid_text($payload['os_version'] ?? null, 160) : valid_text($payload['windows_version'] ?? null, 160),
        'app_name' => $schema >= 3 ? valid_text($payload['app_name'] ?? null, 32) : 'niraN',
        'app_version' => $version, 'first_seen' => $firstSeen, 'last_seen' => $lastSeen,
        'device_key' => $deviceKey, 'last_access_status' => 'unknown', 'schema_version' => $schema,
    ];
    foreach (['device_model', 'device_name', 'windows_username', 'windows_version', 'platform', 'manufacturer', 'model', 'os_version', 'app_name'] as $field) {
        if ($record[$field] === null) respond(422, ['ok' => false, 'error' => 'validation_failed']);
    }
    if ($android && ($record['platform'] !== 'android' || $record['app_name'] !== 'niraNG')) {
        respond(422, ['ok' => false, 'error' => 'validation_failed']);
    }
    if (!$android && ($record['platform'] !== 'windows' || $record['app_name'] !== 'niraN')) {
        respond(422, ['ok' => false, 'error' => 'validation_failed']);
    }

    $outdated = registry_is_outdated($version, $minimum);
    if ($deviceKey === null) {
        $record['last_access_status'] = 'outdated';
        upsert_registration($pdo, $record, null, false);
        respond(426, registry_access_payload(false, false, $minimum, true, 'remote_control_unavailable'));
    }

    $pdo->beginTransaction();
    try {
        $lookup = $pdo->prepare('SELECT access_status, reason FROM device_keys WHERE device_key = :device_key LIMIT 1');
        $lookup->execute([':device_key' => $deviceKey]);
        $keyRecord = $lookup->fetch();
        if (!is_array($keyRecord)) {
            $insert = $pdo->prepare(
                'INSERT INTO device_keys (device_key, access_status, reason, blocked_at, created_at, updated_at, last_seen)
                 VALUES (:device_key, \'allowed\', \'\', NULL, :now, :now, :last_seen)'
            );
            $insert->execute([':device_key' => $deviceKey, ':now' => registry_now(), ':last_seen' => $lastSeen]);
            $keyRecord = ['access_status' => 'allowed', 'reason' => ''];
        } else {
            $touch = $pdo->prepare('UPDATE device_keys SET last_seen = :last_seen, updated_at = :updated_at WHERE device_key = :device_key');
            $touch->execute([':last_seen' => $lastSeen, ':updated_at' => registry_now(), ':device_key' => $deviceKey]);
        }
        $prior = $pdo->prepare('SELECT 1 FROM installations WHERE device_key = :device_key AND installation_id <> :installation_id LIMIT 1');
        $prior->execute([':device_key' => $deviceKey, ':installation_id' => $installationId]);
        $decision = registry_access_state($version, $minimum, (string)$keyRecord['access_status'], $prior->fetchColumn() !== false);
        $blocked = $decision['blocked'];
        $reinstallAfterBlock = $decision['reinstalled_after_block'];
        $token = !$blocked && !$outdated ? rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=') : null;
        $record['last_access_status'] = $decision['status'];
        upsert_registration($pdo, $record, $token === null ? null : registry_token_hash($token), $reinstallAfterBlock);
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $exception;
    }
    if ($blocked) {
        respond(403, registry_access_payload(false, true, $minimum, false, $keyRecord['reason'] !== '' ? $keyRecord['reason'] : 'blocked_by_administrator'));
    }
    if ($outdated) respond(426, registry_access_payload(false, false, $minimum, true, 'update_required'));
    $response = registry_access_payload(true, false, $minimum, false, 'allowed');
    $response['schema_version'] = $schema;
    $response['platform'] = $platform;
    $response['access_token'] = $token;
    respond(200, $response);
}

function authenticate_device(PDO $pdo, array $payload): array
{
    $schema = $payload['schema_version'] ?? null;
    if ($schema === 4) {
        require_exact_fields($payload, ['action', 'schema_version', 'installation_id', 'device_key', 'app_version']);
        $expectedPlatform = 'android';
        $expectedApp = 'niraNG';
    } elseif ($schema === 5) {
        require_exact_fields($payload, ['action', 'schema_version', 'platform', 'installation_id', 'device_key', 'app_name', 'app_version']);
        $expectedPlatform = valid_text($payload['platform'] ?? null, 16);
        $expectedApp = valid_text($payload['app_name'] ?? null, 32);
        if ($expectedPlatform !== 'windows' || $expectedApp !== 'niraN') {
            respond(422, ['ok' => false, 'error' => 'validation_failed']);
        }
    } else {
        respond(400, ['ok' => false, 'error' => 'unsupported_schema']);
    }
    $minimum = registry_minimum_version($pdo, $expectedPlatform);
    $installationId = valid_installation_id($payload['installation_id'] ?? null);
    $deviceKey = valid_device_key($payload['device_key'] ?? null);
    $version = registry_valid_version($payload['app_version'] ?? null);
    $token = registry_bearer_token();
    if ($installationId === null || $deviceKey === null || $version === null || $token === null) {
        respond(401, registry_access_payload(false, false, $minimum, false, 'invalid_device_credentials'));
    }
    $statement = $pdo->prepare(
        'SELECT d.access_status, d.reason, i.platform, i.app_name, i.schema_version
         FROM installations i JOIN device_keys d ON d.device_key = i.device_key
         WHERE i.installation_id = :installation_id AND i.device_key = :device_key
           AND i.access_token_hash = :token_hash LIMIT 1'
    );
    $statement->execute([':installation_id' => $installationId, ':device_key' => $deviceKey, ':token_hash' => registry_token_hash($token)]);
    $device = $statement->fetch();
    if (!is_array($device) || $device['platform'] !== $expectedPlatform || $device['app_name'] !== $expectedApp || (int)$device['schema_version'] !== $schema) {
        respond(401, registry_access_payload(false, false, $minimum, false, 'invalid_device_credentials'));
    }
    $decision = registry_access_state($version, $minimum, (string)$device['access_status'], false);
    $outdated = $decision['outdated'];
    $blocked = $decision['blocked'];
    $status = $decision['status'];
    $touch = $pdo->prepare(
        'UPDATE installations SET app_version = :app_version, last_seen = :last_seen, updated_at = :updated_at,
         last_access_status = :status WHERE installation_id = :installation_id'
    );
    $touch->execute([':app_version' => $version, ':last_seen' => registry_now(), ':updated_at' => registry_now(), ':status' => $status, ':installation_id' => $installationId]);
    if ($blocked) respond(403, registry_access_payload(false, true, $minimum, false, $device['reason'] !== '' ? $device['reason'] : 'blocked_by_administrator'));
    if ($outdated) respond(426, registry_access_payload(false, false, $minimum, true, 'update_required'));
    return ['minimum' => $minimum, 'platform' => $expectedPlatform];
}

function proxy_subscription(PDO $pdo, array $payload): void
{
    $access = authenticate_device($pdo, $payload);
    $environmentKey = $access['platform'] === 'windows'
        ? 'NIRAN_WINDOWS_SUBSCRIPTION_UPSTREAM'
        : 'NIRANG_ANDROID_SUBSCRIPTION_UPSTREAM';
    $upstream = getenv($environmentKey);
    if (!is_string($upstream) || $upstream === '') {
        $upstream = getenv('NIRANG_SUBSCRIPTION_UPSTREAM');
    }
    if (!is_string($upstream) || preg_match('#^https://#i', $upstream) !== 1 || !function_exists('curl_init')) {
        respond(503, ['ok' => false, 'error' => 'subscription_unavailable']);
    }
    $forwardHeaders = [];
    $curl = curl_init($upstream);
    curl_setopt_array($curl, [
        CURLOPT_RETURNTRANSFER => true, CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_CONNECTTIMEOUT => 8, CURLOPT_TIMEOUT => 20, CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
        CURLOPT_HTTPHEADER => ['Accept: text/plain, application/json', 'Cache-Control: no-cache'],
        CURLOPT_USERAGENT => $access['platform'] === 'windows' ? 'niraN-registry/0.3.1' : 'niraNG-registry/1.1.1',
        CURLOPT_HEADERFUNCTION => static function ($handle, string $line) use (&$forwardHeaders): int {
            $parts = explode(':', $line, 2);
            if (count($parts) === 2) {
                $name = strtolower(trim($parts[0]));
                if (in_array($name, ['subscription-userinfo', 'etag', 'last-modified'], true)) $forwardHeaders[$name] = trim($parts[1]);
            }
            return strlen($line);
        },
    ]);
    $body = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $contentType = (string)curl_getinfo($curl, CURLINFO_CONTENT_TYPE);
    curl_close($curl);
    if (!is_string($body) || $status < 200 || $status > 299 || strlen($body) > 4 * 1024 * 1024) {
        respond(502, ['ok' => false, 'error' => 'subscription_upstream_failed']);
    }
    header('Content-Type: ' . ($contentType !== '' ? $contentType : 'text/plain; charset=utf-8'));
    foreach ($forwardHeaders as $name => $value) header($name . ': ' . $value);
    header('Content-Length: ' . strlen($body));
    http_response_code(200);
    echo $body;
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, ['ok' => false, 'error' => 'method_not_allowed']);
}
$contentType = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0]));
if ($contentType !== 'application/json') respond(415, ['ok' => false, 'error' => 'application_json_required']);
$length = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($length <= 0 || $length > 8192) respond(413, ['ok' => false, 'error' => 'invalid_payload_size']);
$raw = file_get_contents('php://input', false, null, 0, 8193);
try {
    $payload = is_string($raw) ? json_decode($raw, true, 16, JSON_THROW_ON_ERROR) : null;
} catch (JsonException $exception) {
    respond(400, ['ok' => false, 'error' => 'invalid_json']);
}
if (!is_array($payload) || substr(ltrim((string)$raw), 0, 1) !== '{') respond(400, ['ok' => false, 'error' => 'invalid_payload']);

try {
    $pdo = registry_database();
    $schema = $payload['schema_version'] ?? null;
    $action = $payload['action'] ?? 'register';
    if (!is_int($schema) || !in_array($schema, [1, 2, 3, 4, 5], true)) respond(400, ['ok' => false, 'error' => 'unsupported_schema']);
    if ($action === 'register') handle_registration($pdo, $payload, $schema);
    if ($action === 'status') {
        $access = authenticate_device($pdo, $payload);
        respond(200, registry_access_payload(true, false, $access['minimum'], false, 'allowed'));
    }
    if ($action === 'subscription') proxy_subscription($pdo, $payload);
    respond(400, ['ok' => false, 'error' => 'unsupported_action']);
} catch (Throwable $exception) {
    respond(503, ['ok' => false, 'error' => 'registry_unavailable']);
}
