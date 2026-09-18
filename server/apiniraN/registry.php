<?php
declare(strict_types=1);

const NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION = '1.1.1';
const NIRANG_DEFAULT_MINIMUM_ANDROID_BUILD = 0;
const NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION = '0.3.1';

function registry_environment(string $name): ?string
{
    $value = getenv($name);
    if (is_string($value) && $value !== '') return $value;
    $serverValue = $_SERVER[$name] ?? null;
    if (is_string($serverValue) && $serverValue !== '') return $serverValue;
    $environmentValue = $_ENV[$name] ?? null;
    return is_string($environmentValue) && $environmentValue !== ''
        ? $environmentValue
        : null;
}

function registry_database(): PDO
{
    $configured = registry_environment('NIRAN_REGISTRY_DB');
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
            app_build INTEGER NOT NULL DEFAULT 0,
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )'
    );
    registry_add_columns($pdo, 'installations', [
        'device_name' => "TEXT NOT NULL DEFAULT ''",
        'windows_username' => "TEXT NOT NULL DEFAULT ''",
        'platform' => "TEXT NOT NULL DEFAULT 'windows'",
        'manufacturer' => "TEXT NOT NULL DEFAULT ''",
        'model' => "TEXT NOT NULL DEFAULT ''",
        'os_version' => "TEXT NOT NULL DEFAULT ''",
        'app_name' => "TEXT NOT NULL DEFAULT 'niraN'",
        'device_key' => "TEXT NULL",
        'access_token_hash' => "TEXT NULL",
        'access_token_expires_at' => "TEXT NULL",
        'reinstalled_after_block' => "INTEGER NOT NULL DEFAULT 0",
        'bypass_attempts' => "INTEGER NOT NULL DEFAULT 0",
        'last_access_status' => "TEXT NOT NULL DEFAULT 'unknown'",
        'schema_version' => "INTEGER NOT NULL DEFAULT 0",
        'app_build' => "INTEGER NOT NULL DEFAULT 0",
    ]);
    registry_merge_duplicate_devices($pdo);
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS device_keys (
            device_key TEXT PRIMARY KEY,
            access_status TEXT NOT NULL DEFAULT \'allowed\' CHECK(access_status IN (\'allowed\', \'blocked\')),
            reason TEXT NOT NULL DEFAULT \'\',
            blocked_at TEXT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_seen TEXT NOT NULL
        )'
    );
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )'
    );
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_installations_last_seen ON installations(last_seen DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_installations_device_key ON installations(device_key)');
    $pdo->exec(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_installations_unique_device_key
         ON installations(device_key) WHERE device_key IS NOT NULL'
    );
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_installations_token ON installations(access_token_hash)');
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS api_nonces (
            nonce_hash TEXT PRIMARY KEY,
            expires_at INTEGER NOT NULL
        )'
    );
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS api_rate_limits (
            bucket_key TEXT NOT NULL,
            window_start INTEGER NOT NULL,
            request_count INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (bucket_key, window_start)
        )'
    );
    registry_set_default($pdo, 'minimum_controllable_version', NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION);
    $legacyAndroidMinimum = registry_setting(
        $pdo,
        'minimum_controllable_version',
        NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION
    );
    registry_set_default($pdo, 'minimum_android_version', $legacyAndroidMinimum);
    registry_set_default($pdo, 'minimum_android_build', (string)NIRANG_DEFAULT_MINIMUM_ANDROID_BUILD);
    registry_set_default($pdo, 'minimum_windows_version', NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION);
    return $pdo;
}

function registry_merge_duplicate_devices(PDO $pdo): void
{
    $keys = $pdo->query(
        'SELECT device_key FROM installations
         WHERE device_key IS NOT NULL AND device_key <> \'\'
         GROUP BY device_key HAVING COUNT(*) > 1'
    )->fetchAll(PDO::FETCH_COLUMN);
    if ($keys === []) return;

    $select = $pdo->prepare(
        'SELECT installation_id, first_seen, created_at, reinstalled_after_block, bypass_attempts
         FROM installations WHERE device_key = :device_key
         ORDER BY last_seen DESC, updated_at DESC, rowid DESC'
    );
    $delete = $pdo->prepare(
        'DELETE FROM installations
         WHERE device_key = :device_key AND installation_id <> :installation_id'
    );
    $update = $pdo->prepare(
        'UPDATE installations SET first_seen = :first_seen, created_at = :created_at,
         reinstalled_after_block = :reinstalled_after_block,
         bypass_attempts = :bypass_attempts
         WHERE installation_id = :installation_id'
    );
    $pdo->beginTransaction();
    try {
        foreach ($keys as $deviceKey) {
            if (!is_string($deviceKey)) continue;
            $select->execute([':device_key' => $deviceKey]);
            $rows = $select->fetchAll();
            if (count($rows) < 2) continue;
            $survivor = $rows[0];
            $firstSeen = min(array_column($rows, 'first_seen'));
            $createdAt = min(array_column($rows, 'created_at'));
            $reinstalled = max(array_map('intval', array_column($rows, 'reinstalled_after_block')));
            $bypassAttempts = array_sum(array_map('intval', array_column($rows, 'bypass_attempts')));
            $delete->execute([
                ':device_key' => $deviceKey,
                ':installation_id' => $survivor['installation_id'],
            ]);
            $update->execute([
                ':first_seen' => $firstSeen,
                ':created_at' => $createdAt,
                ':reinstalled_after_block' => $reinstalled,
                ':bypass_attempts' => $bypassAttempts,
                ':installation_id' => $survivor['installation_id'],
            ]);
        }
        $pdo->commit();
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $exception;
    }
}

function registry_add_columns(PDO $pdo, string $table, array $definitions): void
{
    $columns = [];
    foreach ($pdo->query('PRAGMA table_info(' . $table . ')') as $column) {
        $columns[(string)$column['name']] = true;
    }
    foreach ($definitions as $name => $definition) {
        if (!isset($columns[$name])) {
            $pdo->exec("ALTER TABLE {$table} ADD COLUMN {$name} {$definition}");
        }
    }
}

function registry_now(): string
{
    return (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM);
}

function registry_set_default(PDO $pdo, string $key, string $value): void
{
    $statement = $pdo->prepare(
        'INSERT OR IGNORE INTO admin_settings (setting_key, setting_value, updated_at)
         VALUES (:key, :value, :updated_at)'
    );
    $statement->execute([':key' => $key, ':value' => $value, ':updated_at' => registry_now()]);
}

function registry_setting(PDO $pdo, string $key, string $fallback): string
{
    $statement = $pdo->prepare('SELECT setting_value FROM admin_settings WHERE setting_key = :key LIMIT 1');
    $statement->execute([':key' => $key]);
    $value = $statement->fetchColumn();
    return is_string($value) && $value !== '' ? $value : $fallback;
}

function registry_minimum_version(PDO $pdo, string $platform): string
{
    if ($platform === 'android') {
        return registry_setting($pdo, 'minimum_android_version', NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION);
    }
    if ($platform === 'windows') {
        return registry_setting($pdo, 'minimum_windows_version', NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION);
    }
    throw new InvalidArgumentException('Unsupported platform');
}

function registry_minimum_android_build(PDO $pdo): int
{
    $value = registry_setting($pdo, 'minimum_android_build', (string)NIRANG_DEFAULT_MINIMUM_ANDROID_BUILD);
    return preg_match('/^[0-9]{1,10}$/', $value) === 1 ? (int)$value : NIRANG_DEFAULT_MINIMUM_ANDROID_BUILD;
}

function registry_valid_build($value): ?int
{
    if (is_int($value)) return $value >= 0 ? $value : null;
    if (is_string($value) && preg_match('/^[0-9]{1,10}$/', $value) === 1) return (int)$value;
    return null;
}

function registry_valid_version($value): ?string
{
    if (!is_string($value)) {
        return null;
    }
    $value = trim($value);
    return preg_match('/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/', $value) === 1 ? $value : null;
}

function registry_is_outdated(string $version, string $minimum): bool
{
    return version_compare(preg_replace('/[-+].*$/', '', $version), preg_replace('/[-+].*$/', '', $minimum), '<');
}

function registry_normalize_release_version(?string $version): ?string
{
    if (!is_string($version)) return null;
    $version = preg_replace('/^v/i', '', trim($version));
    if (!is_string($version)) return null;
    return registry_valid_version($version);
}

function registry_is_latest_version(string $version, ?string $latestVersion): bool
{
    $installed = registry_normalize_release_version($version);
    $latest = registry_normalize_release_version($latestVersion);
    if ($installed === null || $latest === null) return false;
    return version_compare(
        preg_replace('/[-+].*$/', '', $installed),
        preg_replace('/[-+].*$/', '', $latest),
        '=='
    );
}

function registry_fetch_latest_release_version(string $repository): ?string
{
    if (preg_match('/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/', $repository) !== 1) return null;
    $url = 'https://api.github.com/repos/' . $repository . '/releases/latest';
    $body = false;
    if (function_exists('curl_init')) {
        $curl = curl_init($url);
        if ($curl !== false) {
            curl_setopt_array($curl, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CONNECTTIMEOUT => 3,
                CURLOPT_TIMEOUT => 5,
                CURLOPT_HTTPHEADER => [
                    'Accept: application/vnd.github+json',
                    'User-Agent: niraNG-device-registry',
                    'X-GitHub-Api-Version: 2022-11-28',
                ],
            ]);
            $response = curl_exec($curl);
            $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
            if (is_string($response) && $status === 200) $body = $response;
        }
    } else {
        $context = stream_context_create(['http' => [
            'method' => 'GET',
            'timeout' => 5,
            'ignore_errors' => true,
            'header' => "Accept: application/vnd.github+json\r\n"
                . "User-Agent: niraNG-device-registry\r\n"
                . "X-GitHub-Api-Version: 2022-11-28\r\n",
        ]]);
        $response = @file_get_contents($url, false, $context);
        if (is_string($response)) $body = $response;
    }
    if (!is_string($body)) return null;
    $payload = json_decode($body, true);
    return is_array($payload)
        ? registry_normalize_release_version(is_string($payload['tag_name'] ?? null) ? $payload['tag_name'] : null)
        : null;
}

function registry_latest_release_version(PDO $pdo, string $repository, int $cacheSeconds = 600): ?string
{
    $cacheKey = 'latest_release_' . hash('sha256', strtolower($repository));
    $statement = $pdo->prepare(
        'SELECT setting_value, updated_at FROM admin_settings WHERE setting_key = :key LIMIT 1'
    );
    $statement->execute([':key' => $cacheKey]);
    $cached = $statement->fetch();
    $cachedVersion = is_array($cached)
        ? registry_normalize_release_version(is_string($cached['setting_value'] ?? null) ? $cached['setting_value'] : null)
        : null;
    $cachedAt = is_array($cached) && is_string($cached['updated_at'] ?? null)
        ? strtotime($cached['updated_at'])
        : false;
    if ($cachedVersion !== null && $cachedAt !== false && $cachedAt >= time() - $cacheSeconds) {
        return $cachedVersion;
    }

    $latest = registry_fetch_latest_release_version($repository);
    if ($latest === null) return $cachedVersion;
    $save = $pdo->prepare(
        'INSERT INTO admin_settings (setting_key, setting_value, updated_at) VALUES (:key, :value, :updated_at)
         ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at'
    );
    $save->execute([':key' => $cacheKey, ':value' => $latest, ':updated_at' => registry_now()]);
    return $latest;
}

/** Registry presentation policy is independent from Android forced-update builds. */
function registry_display_status(
    string $version,
    string $minimumDisplayVersion,
    string $keyStatus,
    bool $hasDeviceKey,
    ?string $latestDisplayVersion = null
): array {
    $blocked = $hasDeviceKey && $keyStatus === 'blocked';
    $outdated = registry_is_outdated($version, $minimumDisplayVersion);
    return [
        'blocked' => $blocked,
        'outdated' => $outdated,
        'latest' => registry_is_latest_version($version, $latestDisplayVersion),
        'status' => $blocked
            ? 'blocked'
            : ($outdated ? 'outdated' : ($hasDeviceKey && $keyStatus === 'allowed' ? 'allowed' : 'unknown')),
    ];
}

function registry_short_key(?string $key): string
{
    return is_string($key) && strlen($key) === 64 ? substr($key, 0, 8) . '…' . substr($key, -6) : '—';
}

function registry_bearer_token(): ?string
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    return is_string($header) && preg_match('/^Bearer ([A-Za-z0-9_-]{43})$/', $header, $match) === 1
        ? $match[1]
        : null;
}

function registry_token_hash(string $token): string
{
    return hash('sha256', $token);
}

function registry_subscription_auth_headers(
    string $upstream,
    string $secret,
    ?int $timestamp = null,
    ?string $nonce = null
): array {
    if (strlen($secret) < 32) return [];
    $parts = parse_url($upstream);
    if (!is_array($parts) || empty($parts['path'])) {
        throw new InvalidArgumentException('Invalid subscription upstream');
    }
    $target = $parts['path'] . (isset($parts['query']) ? '?' . $parts['query'] : '');
    $timestampText = (string)($timestamp ?? time());
    $nonceValue = $nonce ?? bin2hex(random_bytes(16));
    if (preg_match('/^[0-9a-f]{32}$/', $nonceValue) !== 1) {
        throw new InvalidArgumentException('Invalid subscription nonce');
    }
    $signature = hash_hmac(
        'sha256',
        "GET\n" . $target . "\n" . $timestampText . "\n" . $nonceValue,
        $secret
    );
    return [
        'X-NiraN-Timestamp: ' . $timestampText,
        'X-NiraN-Nonce: ' . $nonceValue,
        'X-NiraN-Signature: ' . $signature,
    ];
}

function registry_access_payload(
    bool $allowed,
    bool $blocked,
    string $minimum,
    bool $updateRequired,
    string $reason,
    int $minimumBuild = 0
): array
{
    return [
        'ok' => $allowed,
        'allowed' => $allowed,
        'blocked' => $blocked,
        'minimum_version' => $minimum,
        'minimum_build' => $minimumBuild,
        'update_required' => $updateRequired,
        'reason' => $reason,
    ];
}

function registry_access_state(
    string $version,
    string $minimum,
    string $keyStatus,
    bool $hasPriorInstallation,
    ?int $appBuild = null,
    int $minimumBuild = 0
): array
{
    $blocked = $keyStatus === 'blocked';
    $outdated = $appBuild === null
        ? registry_is_outdated($version, $minimum)
        : $appBuild < $minimumBuild;
    return [
        'blocked' => $blocked,
        'outdated' => $outdated,
        'status' => $blocked ? 'blocked' : ($outdated ? 'outdated' : 'allowed'),
        'reinstalled_after_block' => $blocked && $hasPriorInstallation,
    ];
}
