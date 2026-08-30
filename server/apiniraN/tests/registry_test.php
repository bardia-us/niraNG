<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/registry.php';

function assert_same($expected, $actual, string $message): void
{
    if ($expected !== $actual) {
        throw new RuntimeException($message . ': expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

$temporary = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'nirang-registry-' . bin2hex(random_bytes(8)) . '.sqlite';
putenv('NIRAN_REGISTRY_DB=' . $temporary);

try {
    $pdo = registry_database();
    assert_same('1.1.1', registry_minimum_version($pdo, 'android'), 'default Android minimum version');
    assert_same('0.3.1', registry_minimum_version($pdo, 'windows'), 'default Windows minimum version');
    assert_same(true, registry_is_outdated('1.1.0+12', '1.1.1'), '1.1.0 must be outdated');
    assert_same(false, registry_is_outdated('1.1.1+13', '1.1.1'), '1.1.1 must be controllable');
    assert_same(true, registry_is_outdated('0.3.0+3', '0.3.1'), 'niraN 0.3.0 must be outdated');
    assert_same(false, registry_is_outdated('0.3.1+4', '0.3.1'), 'niraN 0.3.1 must be controllable');

    $allowed = registry_access_state('1.1.1', '1.1.1', 'allowed', false);
    assert_same('allowed', $allowed['status'], 'current allowed device');
    assert_same(false, $allowed['reinstalled_after_block'], 'normal registration is not reinstall bypass');

    $reinstalled = registry_access_state('1.1.1', '1.1.1', 'blocked', true);
    assert_same('blocked', $reinstalled['status'], 'blocked key stays blocked');
    assert_same(true, $reinstalled['reinstalled_after_block'], 'new installation on blocked key is detected');

    $outdated = registry_access_state('1.1.0', '1.1.1', 'allowed', false);
    assert_same('outdated', $outdated['status'], 'legacy version is shown as uncontrollable');

    $columns = [];
    foreach ($pdo->query('PRAGMA table_info(installations)') as $column) {
        $columns[] = $column['name'];
    }
    foreach (['device_key', 'access_token_hash', 'reinstalled_after_block', 'bypass_attempts', 'last_access_status', 'schema_version'] as $column) {
        assert_same(true, in_array($column, $columns, true), 'migration column ' . $column);
    }

    $deviceKey = str_repeat('a', 64);
    $pdo->exec('DROP INDEX idx_installations_unique_device_key');
    $insert = $pdo->prepare(
        'INSERT INTO installations (
            installation_id, app_version, first_seen, last_seen, created_at, updated_at,
            device_key, device_name, reinstalled_after_block, bypass_attempts
         ) VALUES (
            :installation_id, :app_version, :first_seen, :last_seen, :created_at, :updated_at,
            :device_key, :device_name, :reinstalled_after_block, :bypass_attempts
         )'
    );
    $insert->execute([
        ':installation_id' => '11111111-1111-4111-8111-111111111111', ':app_version' => '1.1.1',
        ':first_seen' => '2026-08-01T00:00:00+00:00', ':last_seen' => '2026-08-10T00:00:00+00:00',
        ':created_at' => '2026-08-01T00:00:00+00:00', ':updated_at' => '2026-08-10T00:00:00+00:00',
        ':device_key' => $deviceKey, ':device_name' => 'Old installation',
        ':reinstalled_after_block' => 0, ':bypass_attempts' => 0,
    ]);
    $insert->execute([
        ':installation_id' => '22222222-2222-4222-8222-222222222222', ':app_version' => '1.1.1',
        ':first_seen' => '2026-08-20T00:00:00+00:00', ':last_seen' => '2026-08-29T00:00:00+00:00',
        ':created_at' => '2026-08-20T00:00:00+00:00', ':updated_at' => '2026-08-29T00:00:00+00:00',
        ':device_key' => $deviceKey, ':device_name' => 'Current installation',
        ':reinstalled_after_block' => 1, ':bypass_attempts' => 2,
    ]);
    registry_merge_duplicate_devices($pdo);
    $merged = $pdo->query("SELECT * FROM installations WHERE device_key = '{$deviceKey}'")->fetchAll();
    assert_same(1, count($merged), 'same device key is merged into one row');
    assert_same('22222222-2222-4222-8222-222222222222', $merged[0]['installation_id'], 'latest installation id survives');
    assert_same('2026-08-01T00:00:00+00:00', $merged[0]['first_seen'], 'original first seen is preserved');
    assert_same(1, (int)$merged[0]['reinstalled_after_block'], 'reinstall marker is preserved');
    assert_same(2, (int)$merged[0]['bypass_attempts'], 'bypass attempts are preserved');

    echo "registry tests passed\n";
} finally {
    unset($pdo);
    @unlink($temporary);
    @unlink($temporary . '-wal');
    @unlink($temporary . '-shm');
}
