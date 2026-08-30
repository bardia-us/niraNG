<?php
declare(strict_types=1);

require_once __DIR__ . '/registry.php';
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
$nonce = base64_encode(random_bytes(18));
header("Content-Security-Policy: default-src 'none'; style-src 'nonce-{$nonce}'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

session_name('niran_admin');
session_set_cookie_params(['lifetime' => 0, 'path' => '/apiniraN/', 'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
session_start();

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function is_password_hash($value): bool
{
    if (!is_string($value) || $value === '') return false;
    return (password_get_info($value)['algoName'] ?? 'unknown') !== 'unknown';
}

function stored_admin_hash(PDO $pdo): ?string
{
    $statement = $pdo->prepare('SELECT setting_value FROM admin_settings WHERE setting_key = :key LIMIT 1');
    $statement->execute([':key' => 'admin_password_hash']);
    $value = $statement->fetchColumn();
    return is_string($value) && $value !== '' ? $value : null;
}

function csrf_token(): string
{
    if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) $_SESSION['csrf'] = bin2hex(random_bytes(32));
    return $_SESSION['csrf'];
}

function valid_csrf(): bool
{
    return isset($_POST['csrf'], $_SESSION['csrf']) && is_string($_POST['csrf']) && is_string($_SESSION['csrf'])
        && hash_equals($_SESSION['csrf'], $_POST['csrf']);
}

function display_timestamp($value, DateTimeZone $timezone): string
{
    if (!is_string($value) || $value === '') return '—';
    try {
        return (new DateTimeImmutable($value))->setTimezone($timezone)->format('Y/m/d - H:i');
    } catch (Exception $exception) {
        return '—';
    }
}

$error = null;
$message = null;
try {
    $database = registry_database();
} catch (Throwable $exception) {
    $database = null;
    $error = 'The registry database is unavailable.';
}
$environmentHash = getenv('NIRAN_ADMIN_PASSWORD_HASH');
$passwordHash = is_string($environmentHash) && $environmentHash !== '' ? $environmentHash : ($database instanceof PDO ? stored_admin_hash($database) : null);
$setupRequired = $database instanceof PDO && $passwordHash === null;
if ($passwordHash !== null && !is_password_hash($passwordHash)) $error = 'The administrator password hash is invalid.';

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    if (!valid_csrf()) {
        $error = 'The request expired. Please try again.';
    } else {
        $action = is_string($_POST['action'] ?? null) ? $_POST['action'] : '';
        if ($action === 'logout') {
            $_SESSION = [];
            session_regenerate_id(true);
            header('Location: index.php', true, 303);
            exit;
        }
        if ($action === 'setup' && $setupRequired && $database instanceof PDO) {
            $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
            $confirmation = is_string($_POST['password_confirmation'] ?? null) ? $_POST['password_confirmation'] : '';
            if (strlen($password) < 10 || strlen($password) > 1024 || !hash_equals($password, $confirmation)) {
                $error = 'Use a matching password containing at least 10 characters.';
            } else {
                $hash = password_hash($password, PASSWORD_DEFAULT);
                $statement = $database->prepare(
                    'INSERT OR IGNORE INTO admin_settings (setting_key, setting_value, updated_at) VALUES (:key, :value, :updated_at)'
                );
                $statement->execute([':key' => 'admin_password_hash', ':value' => $hash, ':updated_at' => registry_now()]);
                session_regenerate_id(true);
                $_SESSION['authenticated'] = true;
                header('Location: index.php', true, 303);
                exit;
            }
        } elseif ($action === 'login' && $passwordHash !== null) {
            $lockedUntil = (int)($_SESSION['locked_until'] ?? 0);
            $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
            if ($lockedUntil <= time() && strlen($password) <= 1024 && password_verify($password, $passwordHash)) {
                session_regenerate_id(true);
                $_SESSION['authenticated'] = true;
                $_SESSION['attempts'] = 0;
                unset($_SESSION['locked_until']);
                header('Location: index.php', true, 303);
                exit;
            }
            $attempts = min(10, (int)($_SESSION['attempts'] ?? 0) + 1);
            $_SESSION['attempts'] = $attempts;
            if ($attempts >= 5) $_SESSION['locked_until'] = time() + 300;
            $error = 'Invalid credentials or temporarily locked.';
        } elseif (!empty($_SESSION['authenticated']) && $database instanceof PDO) {
            if ($action === 'minimum_versions') {
                $androidMinimum = registry_valid_version($_POST['minimum_android_version'] ?? null);
                $windowsMinimum = registry_valid_version($_POST['minimum_windows_version'] ?? null);
                if ($androidMinimum === null || $windowsMinimum === null) {
                    $error = 'Both minimum versions must use semantic version format.';
                } else {
                    $statement = $database->prepare(
                        'INSERT INTO admin_settings (setting_key, setting_value, updated_at) VALUES (:key, :value, :updated_at)
                         ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at'
                    );
                    $database->beginTransaction();
                    try {
                        $statement->execute([':key' => 'minimum_android_version', ':value' => $androidMinimum, ':updated_at' => registry_now()]);
                        $statement->execute([':key' => 'minimum_windows_version', ':value' => $windowsMinimum, ':updated_at' => registry_now()]);
                        $database->commit();
                        $message = 'Minimum controllable versions updated.';
                    } catch (Throwable $exception) {
                        if ($database->inTransaction()) $database->rollBack();
                        throw $exception;
                    }
                }
            } elseif ($action === 'block' || $action === 'unblock') {
                $deviceKey = is_string($_POST['device_key'] ?? null) ? strtolower(trim($_POST['device_key'])) : '';
                if (preg_match('/^[0-9a-f]{64}$/', $deviceKey) !== 1) {
                    $error = 'Invalid device key.';
                } else {
                    $status = $action === 'block' ? 'blocked' : 'allowed';
                    $reason = $action === 'block' ? 'blocked_by_administrator' : '';
                    $statement = $database->prepare(
                        'UPDATE device_keys SET access_status = :status, reason = :reason, blocked_at = :blocked_at,
                         updated_at = :updated_at WHERE device_key = :device_key'
                    );
                    $statement->execute([
                        ':status' => $status, ':reason' => $reason,
                        ':blocked_at' => $status === 'blocked' ? registry_now() : null,
                        ':updated_at' => registry_now(), ':device_key' => $deviceKey,
                    ]);
                    if ($statement->rowCount() !== 1) $error = 'Device key was not found.';
                    else $message = $status === 'blocked' ? 'Device blocked.' : 'Device unblocked.';
                }
            }
        }
    }
}

$authenticated = !empty($_SESSION['authenticated']) && $database instanceof PDO;
$minimumAndroidVersion = $database instanceof PDO
    ? registry_minimum_version($database, 'android')
    : NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION;
$minimumWindowsVersion = $database instanceof PDO
    ? registry_minimum_version($database, 'windows')
    : NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION;
$rows = [];
if ($authenticated) {
    $rows = $database->query(
        'SELECT i.*, d.access_status, d.reason, d.blocked_at
         FROM installations i LEFT JOIN device_keys d ON d.device_key = i.device_key
         ORDER BY i.last_seen DESC LIMIT 1000'
    )->fetchAll();
}
$timezoneName = getenv('NIRAN_ADMIN_TIMEZONE');
try { $displayTimezone = new DateTimeZone(is_string($timezoneName) && $timezoneName !== '' ? $timezoneName : 'Asia/Tehran'); }
catch (Throwable $exception) { $displayTimezone = new DateTimeZone('UTC'); }
?>
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>niraNG Device Registry</title>
<style nonce="<?= e($nonce) ?>">
:root{color-scheme:dark;--bg:#0d0b14;--panel:#171321;--line:#302a40;--text:#f4efff;--muted:#aaa1bd;--accent:#8b7cf6;--ok:#45c59a;--bad:#ff6f82;--warn:#f3bd59}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at top,#211a38,var(--bg) 40%);color:var(--text);font:14px system-ui,sans-serif}main{max-width:1280px;margin:auto;padding:28px}.card{background:rgba(23,19,33,.94);border:1px solid var(--line);border-radius:18px;padding:20px;margin-bottom:18px;overflow:auto}h1,h2{margin:0 0 14px}p{color:var(--muted)}input,button{border-radius:9px;border:1px solid var(--line);padding:9px 12px;background:#211b2f;color:var(--text)}button{cursor:pointer;background:var(--accent);border:0;font-weight:700}.danger{background:#a93650}.secondary{background:#3a334a}.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.right{margin-left:auto}.badge{display:inline-block;padding:4px 8px;border-radius:999px;font-weight:800;font-size:12px}.allowed{background:#173d34;color:#7ce6c2}.blocked{background:#4b1f2b;color:#ff9bac}.outdated{background:#49391a;color:#ffd57f}.unknown{background:#34303c;color:#c6bdcf}.reinstall{background:#39295b;color:#cbbcff}table{border-collapse:collapse;width:100%;min-width:1050px}th,td{text-align:left;padding:11px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-size:12px}.mono{font-family:ui-monospace,monospace;font-size:12px}.notice{padding:10px;border-radius:9px;margin:10px 0}.error{background:#4b1f2b}.success{background:#173d34}@media(max-width:700px){main{padding:14px}.right{margin-left:0}}
</style></head><body><main>
<div class="row"><h1>niraNG Device Registry</h1><?php if ($authenticated): ?><form class="right" method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="logout"><button class="secondary">Log out</button></form><?php endif; ?></div>
<?php if ($error !== null): ?><div class="notice error"><?= e($error) ?></div><?php endif; ?>
<?php if ($message !== null): ?><div class="notice success"><?= e($message) ?></div><?php endif; ?>
<?php if (!$authenticated): ?>
<section class="card"><h2><?= $setupRequired ? 'Create administrator password' : 'Administrator login' ?></h2>
<form method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="<?= $setupRequired ? 'setup' : 'login' ?>">
<div class="row"><input type="password" name="password" minlength="10" maxlength="1024" required placeholder="Password">
<?php if ($setupRequired): ?><input type="password" name="password_confirmation" minlength="10" maxlength="1024" required placeholder="Confirm password"><?php endif; ?><button>Continue</button></div></form></section>
<?php else: ?>
<section class="card"><h2>Remote access policy</h2><form method="post" class="row"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="minimum_versions"><label>Android / niraNG minimum <input name="minimum_android_version" value="<?= e($minimumAndroidVersion) ?>" pattern="[0-9]+\.[0-9]+\.[0-9]+.*" required></label><label>Windows / niraN minimum <input name="minimum_windows_version" value="<?= e($minimumWindowsVersion) ?>" pattern="[0-9]+\.[0-9]+\.[0-9]+.*" required></label><button>Save</button></form>
<p>Android below <?= e($minimumAndroidVersion) ?> and Windows below <?= e($minimumWindowsVersion) ?> are Outdated/Uncontrollable. Old clients with a direct embedded subscription endpoint cannot be honestly remote-blocked.</p></section>
<section class="card"><h2>Devices (<?= count($rows) ?>)</h2><table><thead><tr><th>Status</th><th>Device</th><th>Platform / Version</th><th>Device Key</th><th>Installation ID</th><th>First Seen</th><th>Last Seen</th><th>Action</th></tr></thead><tbody>
<?php foreach ($rows as $row):
    $version = is_string($row['app_version']) ? $row['app_version'] : '0.0.0';
    $platform = $row['platform'] === 'android' ? 'android' : 'windows';
    $minimumVersion = $platform === 'android' ? $minimumAndroidVersion : $minimumWindowsVersion;
    $hasDeviceKey = is_string($row['device_key']) && preg_match('/^[0-9a-f]{64}$/', $row['device_key']) === 1;
    $outdated = registry_is_outdated($version, $minimumVersion);
    $controllable = $hasDeviceKey && !$outdated;
    $blocked = $hasDeviceKey && ($row['access_status'] ?? '') === 'blocked';
    $status = $blocked ? 'blocked' : ($outdated ? 'outdated' : (($row['access_status'] ?? '') === 'allowed' ? 'allowed' : 'unknown'));
?>
<tr><td><span class="badge <?= e($status) ?>"><?= e(ucfirst($status)) ?></span><?php if ($blocked && $outdated): ?> <span class="badge outdated">Outdated</span><?php endif; ?><?php if ((int)$row['reinstalled_after_block'] === 1): ?><br><span class="badge reinstall">Reinstalled after block</span><?php endif; ?><?php if ($outdated): ?><br><small>Remote control unavailable.<br>User must update <?= $platform === 'android' ? 'niraNG' : 'niraN' ?> to <?= e($minimumVersion) ?> or newer.</small><?php endif; ?></td>
<td><strong><?= e((string)($row['device_name'] ?: $row['device_model'] ?: 'Unknown device')) ?></strong><br><small><?= e(trim((string)$row['manufacturer'] . ' ' . (string)$row['model'])) ?></small></td>
<td><?= e((string)$row['platform']) ?><br><?= e((string)$row['app_name'] . ' ' . $version) ?></td>
<td class="mono"><?= e(registry_short_key(is_string($row['device_key']) ? $row['device_key'] : null)) ?><?php if ((int)$row['bypass_attempts'] > 0): ?><br><small>Attempts: <?= (int)$row['bypass_attempts'] ?></small><?php endif; ?></td>
<td class="mono"><?= e((string)$row['installation_id']) ?></td><td><?= e(display_timestamp($row['first_seen'], $displayTimezone)) ?></td><td><?= e(display_timestamp($row['last_seen'], $displayTimezone)) ?></td>
<td><?php if ($controllable || $blocked): ?><form method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="device_key" value="<?= e((string)$row['device_key']) ?>"><input type="hidden" name="action" value="<?= $blocked ? 'unblock' : 'block' ?>"><button class="<?= $blocked ? 'secondary' : 'danger' ?>"><?= $blocked ? 'Unblock' : 'Block' ?></button></form><?php else: ?>—<?php endif; ?></td></tr>
<?php endforeach; ?></tbody></table></section>
<?php endif; ?></main></body></html>
