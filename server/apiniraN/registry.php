<?php
declare(strict_types=1);

const NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION = '1.1.1';
const NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION = '0.3.1';

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
        'reinstalled_after_block' => "INTEGER NOT NULL DEFAULT 0",
        'bypass_attempts' => "INTEGER NOT NULL DEFAULT 0",
        'last_access_status' => "TEXT NOT NULL DEFAULT 'unknown'",
        'schema_version' => "INTEGER NOT NULL DEFAULT 0",
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
    registry_set_default($pdo, 'minimum_controllable_version', NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION);
    $legacyAndroidMinimum = registry_setting(
        $pdo,
        'minimum_controllable_version',
        NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION
    );
    registry_set_default($pdo, 'minimum_android_version', $legacyAndroidMinimum);
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

function registry_access_payload(bool $allowed, bool $blocked, string $minimum, bool $updateRequired, string $reason): array
{
    return [
        'ok' => $allowed,
        'allowed' => $allowed,
        'blocked' => $blocked,
        'minimum_version' => $minimum,
        'update_required' => $updateRequired,
        'reason' => $reason,
    ];
}

function registry_access_state(string $version, string $minimum, string $keyStatus, bool $hasPriorInstallation): array
{
    $blocked = $keyStatus === 'blocked';
    $outdated = registry_is_outdated($version, $minimum);
    return [
        'blocked' => $blocked,
        'outdated' => $outdated,
        'status' => $blocked ? 'blocked' : ($outdated ? 'outdated' : 'allowed'),
        'reinstalled_after_block' => $blocked && $hasPriorInstallation,
    ];
}
