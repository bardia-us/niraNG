<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function respond(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function registry_database(): PDO
{
    $configured = getenv('NIRAN_REGISTRY_DB');
    $path = is_string($configured) && $configured !== ''
        ? $configured
        : dirname(__DIR__) . DIRECTORY_SEPARATOR . '.niran-private' . DIRECTORY_SEPARATOR . 'device-registry.sqlite';
    $directory = dirname($path);
    if (!is_dir($directory) && !mkdir($directory, 0700, true) && !is_dir($directory)) {
        throw new RuntimeException('Registry storage is unavailable');
    }
    $pdo = new PDO('sqlite:' . $path, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
    $pdo->exec('PRAGMA busy_timeout = 5000');
    $pdo->exec('PRAGMA journal_mode = WAL');
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS installations (
            installation_id TEXT PRIMARY KEY,
            device_model TEXT NOT NULL DEFAULT \'\',
            device_name TEXT NOT NULL DEFAULT \'\',
            windows_username TEXT NOT NULL DEFAULT \'\',
            windows_version TEXT NOT NULL DEFAULT \'\',
            platform TEXT NOT NULL DEFAULT \'windows\',
            manufacturer TEXT NOT NULL DEFAULT \'\',
            model TEXT NOT NULL DEFAULT \'\',
            os_version TEXT NOT NULL DEFAULT \'\',
            app_name TEXT NOT NULL DEFAULT \'niraN\',
            app_version TEXT NOT NULL,
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )'
    );
    $columns = [];
    foreach ($pdo->query('PRAGMA table_info(installations)') as $column) {
        $columns[(string)$column['name']] = true;
    }
    if (!isset($columns['device_name'])) {
        $pdo->exec("ALTER TABLE installations ADD COLUMN device_name TEXT NOT NULL DEFAULT ''");
    }
    if (!isset($columns['windows_username'])) {
        $pdo->exec("ALTER TABLE installations ADD COLUMN windows_username TEXT NOT NULL DEFAULT ''");
    }
    $migrations = [
        'platform' => "TEXT NOT NULL DEFAULT 'windows'",
        'manufacturer' => "TEXT NOT NULL DEFAULT ''",
        'model' => "TEXT NOT NULL DEFAULT ''",
        'os_version' => "TEXT NOT NULL DEFAULT ''",
        'app_name' => "TEXT NOT NULL DEFAULT 'niraN'",
    ];
    foreach ($migrations as $columnName => $definition) {
        if (!isset($columns[$columnName])) {
            $pdo->exec("ALTER TABLE installations ADD COLUMN {$columnName} {$definition}");
        }
    }
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_installations_last_seen ON installations(last_seen DESC)');
    return $pdo;
}

function valid_text($value, int $max): ?string
{
    if (!is_string($value)) {
        return null;
    }
    $value = trim($value);
    if ($value === '' || strlen($value) > $max || preg_match('//u', $value) !== 1) {
        return null;
    }
    if (preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', $value) === 1) {
        return null;
    }
    return $value;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, ['ok' => false, 'error' => 'method_not_allowed']);
}

$contentType = strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0]));
if ($contentType !== 'application/json') {
    respond(415, ['ok' => false, 'error' => 'application_json_required']);
}

$contentLength = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);
if ($contentLength <= 0 || $contentLength > 8192) {
    respond(413, ['ok' => false, 'error' => 'invalid_payload_size']);
}

$raw = file_get_contents('php://input', false, null, 0, 8193);
if (!is_string($raw) || strlen($raw) > 8192) {
    respond(413, ['ok' => false, 'error' => 'invalid_payload_size']);
}

try {
    $payload = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
} catch (JsonException $exception) {
    respond(400, ['ok' => false, 'error' => 'invalid_json']);
}
if (!is_array($payload) || substr(ltrim($raw), 0, 1) !== '{') {
    respond(400, ['ok' => false, 'error' => 'invalid_payload']);
}

$schemaVersion = $payload['schema_version'] ?? null;
if ($schemaVersion !== 1 && $schemaVersion !== 2 && $schemaVersion !== 3) {
    respond(400, ['ok' => false, 'error' => 'unsupported_schema']);
}
$required = $schemaVersion === 3
    ? [
        'schema_version', 'platform', 'installation_id', 'device_name',
        'manufacturer', 'model', 'os_version', 'app_name', 'app_version',
        'first_seen', 'last_seen',
    ]
    : ($schemaVersion === 2 ? [
        'schema_version', 'installation_id', 'device_name', 'windows_username',
        'windows_version', 'app_version', 'first_seen', 'last_seen',
    ] : [
        'schema_version', 'installation_id', 'device_model', 'windows_version',
        'app_version', 'first_seen', 'last_seen',
    ]);
if (array_diff(array_keys($payload), $required) !== [] ||
    array_diff($required, array_keys($payload)) !== []) {
    respond(400, ['ok' => false, 'error' => 'invalid_fields']);
}

$installationId = valid_text($payload['installation_id'] ?? null, 36);
$deviceModel = $schemaVersion === 1
    ? valid_text($payload['device_model'] ?? null, 160)
    : '';
$deviceName = $schemaVersion >= 2
    ? valid_text($payload['device_name'] ?? null, 160)
    : '';
$windowsUsername = $schemaVersion === 2
    ? valid_text($payload['windows_username'] ?? null, 160)
    : '';
$windowsVersion = $schemaVersion < 3
    ? valid_text($payload['windows_version'] ?? null, 160)
    : '';
$platform = $schemaVersion === 3
    ? valid_text($payload['platform'] ?? null, 16)
    : 'windows';
$manufacturer = $schemaVersion === 3
    ? valid_text($payload['manufacturer'] ?? null, 160)
    : '';
$model = $schemaVersion === 3
    ? valid_text($payload['model'] ?? null, 160)
    : '';
$osVersion = $schemaVersion === 3
    ? valid_text($payload['os_version'] ?? null, 160)
    : ($windowsVersion ?? '');
$appName = $schemaVersion === 3
    ? valid_text($payload['app_name'] ?? null, 32)
    : 'niraN';
$appVersion = valid_text($payload['app_version'] ?? null, 32);
$firstSeen = valid_text($payload['first_seen'] ?? null, 40);
$lastSeen = valid_text($payload['last_seen'] ?? null, 40);

if ($installationId === null ||
    preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i', $installationId) !== 1 ||
    ($schemaVersion === 1 && $deviceModel === null) ||
    ($schemaVersion === 2 && ($deviceName === null || $windowsUsername === null)) ||
    ($schemaVersion < 3 && $windowsVersion === null) ||
    ($schemaVersion === 3 && (
        $platform !== 'android' || $deviceName === null || $manufacturer === null ||
        $model === null || $osVersion === null || $appName !== 'niraNG'
    )) ||
    $appVersion === null ||
    preg_match('/^[0-9A-Za-z][0-9A-Za-z.+_-]{0,31}$/', $appVersion) !== 1 ||
    $firstSeen === null || $lastSeen === null) {
    respond(422, ['ok' => false, 'error' => 'validation_failed']);
}

try {
    new DateTimeImmutable($firstSeen);
    new DateTimeImmutable($lastSeen);
} catch (Exception $exception) {
    respond(422, ['ok' => false, 'error' => 'invalid_timestamp']);
}

try {
    $pdo = registry_database();
    $now = (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);
    if ($schemaVersion === 3) {
        $identityUpdates = 'platform = excluded.platform,
           device_name = excluded.device_name,
           manufacturer = excluded.manufacturer,
           model = excluded.model,
           os_version = excluded.os_version,
           app_name = excluded.app_name';
    } elseif ($schemaVersion === 2) {
        $identityUpdates = 'platform = excluded.platform,
           device_name = excluded.device_name,
           windows_username = excluded.windows_username,
           windows_version = excluded.windows_version,
           os_version = excluded.os_version,
           app_name = excluded.app_name';
    } else {
        $identityUpdates = 'platform = excluded.platform,
           device_model = excluded.device_model,
           windows_version = excluded.windows_version,
           os_version = excluded.os_version,
           app_name = excluded.app_name';
    }
    $statement = $pdo->prepare(
        'INSERT INTO installations (
            installation_id, device_model, device_name, windows_username,
            windows_version, platform, manufacturer, model, os_version,
            app_name, app_version,
            first_seen, last_seen, created_at, updated_at
         ) VALUES (
            :installation_id, :device_model, :device_name, :windows_username,
            :windows_version, :platform, :manufacturer, :model, :os_version,
            :app_name, :app_version,
            :first_seen, :last_seen, :created_at, :updated_at
         ) ON CONFLICT(installation_id) DO UPDATE SET ' . $identityUpdates . ',
            app_version = excluded.app_version,
            last_seen = excluded.last_seen,
            updated_at = excluded.updated_at'
    );
    $statement->execute([
        ':installation_id' => strtolower($installationId),
        ':device_model' => $deviceModel ?? '',
        ':device_name' => $deviceName ?? '',
        ':windows_username' => $windowsUsername ?? '',
        ':windows_version' => $windowsVersion ?? '',
        ':platform' => $platform,
        ':manufacturer' => $manufacturer ?? '',
        ':model' => $model ?? '',
        ':os_version' => $osVersion,
        ':app_name' => $appName,
        ':app_version' => $appVersion,
        ':first_seen' => $firstSeen,
        ':last_seen' => $lastSeen,
        ':created_at' => $now,
        ':updated_at' => $now,
    ]);
    respond(200, ['ok' => true, 'schema_version' => 3]);
} catch (Throwable $exception) {
    respond(503, ['ok' => false, 'error' => 'registry_unavailable']);
}
