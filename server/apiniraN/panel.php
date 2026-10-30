<?php
declare(strict_types=1);

/** A single shared administrator account: neither new cookies nor new IPs reset failures. */
function panel_verify_login(PDO $pdo, string $password, string $hash, ?int $now = null): array
{
    $pdo->exec('CREATE TABLE IF NOT EXISTS panel_admin_login (
        account_id INTEGER PRIMARY KEY CHECK(account_id = 1),
        attempts INTEGER NOT NULL DEFAULT 0,
        locked_until INTEGER NOT NULL DEFAULT 0
    )');
    // Reserve the SQLite writer before reading or verifying: concurrent sessions
    // must not overwrite each other's failures or accept a password during a lock.
    $pdo->exec('BEGIN IMMEDIATE');
    try {
        $timestamp = $now ?? time();
        $state = $pdo->query('SELECT attempts, locked_until FROM panel_admin_login WHERE account_id = 1')->fetch();
        $attempts = is_array($state) ? (int)$state['attempts'] : 0;
        $lockedUntil = is_array($state) ? (int)$state['locked_until'] : 0;
        if ($lockedUntil > $timestamp) {
            $pdo->exec('COMMIT');
            return ['authenticated' => false, 'retry_after' => $lockedUntil - $timestamp];
        }
        if ($lockedUntil !== 0) $attempts = 0;
        $authenticated = strlen($password) <= 1024 && password_verify($password, $hash);
        $attempts = $authenticated ? 0 : min(5, $attempts + 1);
        $lockedUntil = $attempts >= 5 ? $timestamp + 60 : 0;
        $save = $pdo->prepare('INSERT INTO panel_admin_login (account_id, attempts, locked_until) VALUES (1, :attempts, :locked_until)
            ON CONFLICT(account_id) DO UPDATE SET attempts = excluded.attempts, locked_until = excluded.locked_until');
        $save->execute([':attempts' => $attempts, ':locked_until' => $lockedUntil]);
        $pdo->exec('COMMIT');
        return ['authenticated' => $authenticated, 'retry_after' => $lockedUntil > 0 ? 60 : 0];
    } catch (Throwable $exception) {
        $pdo->exec('ROLLBACK');
        throw $exception;
    }
}

/** Only the web server's peer address is trusted; forwarded headers are not read. */
function panel_remote_ip(array $server): ?string
{
    $address = $server['REMOTE_ADDR'] ?? null;
    if (!is_string($address) || filter_var($address, FILTER_VALIDATE_IP) === false) return null;
    return inet_ntop(inet_pton($address));
}

function panel_session_ip_matches(array $session, ?string $address): bool
{
    return $address !== null && isset($session['admin_ip']) && is_string($session['admin_ip'])
        && hash_equals($session['admin_ip'], $address);
}

function panel_device_rows(PDO $pdo, string $search): array
{
    $query = 'SELECT i.*, d.access_status, d.reason, d.blocked_at
        FROM installations i LEFT JOIN device_keys d ON d.device_key = i.device_key';
    if ($search !== '') {
        $query .= " WHERE i.device_name LIKE :search ESCAPE '!' OR i.device_model LIKE :search ESCAPE '!'"
            . " OR i.manufacturer LIKE :search ESCAPE '!' OR i.model LIKE :search ESCAPE '!'"
            . " OR i.device_key LIKE :search ESCAPE '!'";
    }
    $statement = $pdo->prepare($query . ' ORDER BY i.last_seen DESC LIMIT 1000');
    $parameters = $search === '' ? [] : [':search' => '%' . strtr($search, ['!' => '!!', '%' => '!%', '_' => '!_']) . '%'];
    $statement->execute($parameters);
    return $statement->fetchAll();
}
