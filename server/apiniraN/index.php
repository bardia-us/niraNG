<?php
declare(strict_types=1);

require_once __DIR__ . '/registry.php';
require_once __DIR__ . '/panel.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/admin-auth/ui.php';
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
$nonce = base64_encode(random_bytes(18));
header("Content-Security-Policy: default-src 'none'; style-src 'nonce-{$nonce}'; img-src data:; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

if (!in_array(strtolower((string)($_SERVER['HTTPS'] ?? '')), ['on', '1'], true) && (string)($_SERVER['SERVER_PORT'] ?? '') !== '443') {
    http_response_code(400);
    exit('HTTPS is required for the administrator panel.');
}

ini_set('session.use_strict_mode', '1');
ini_set('session.use_only_cookies', '1');
ini_set('session.use_trans_sid', '0');
session_name('niran_admin');
session_set_cookie_params(['lifetime' => 0, 'path' => '/apiniraN/', 'secure' => true, 'httponly' => true, 'samesite' => 'Strict']);
session_start();
$auth = null;
$authResult = [];
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
$setupRequired = false;
if ($database instanceof PDO) {
    try {
        $auth = panel_auth($database);
        $authState = $auth->state();
        $setupRequired = empty($authState['password_hash']);
        if (!empty($_SESSION['authenticated']) && !$auth->authenticated()) {
            $_SESSION = []; session_regenerate_id(true);
        }
    } catch (Throwable $exception) { $auth = null; $error = 'Authentication storage is unavailable; preserve the database and restore matching source.'; }
}

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    if (!valid_csrf()) {
        $error = 'The request expired. Please try again.';
    } elseif ($auth instanceof NiraAdminAuth) {
        $action = is_string($_POST['action'] ?? null) ? $_POST['action'] : '';
        $authActions = ['setup','login','verify_2fa','logout','change_password','change_username','begin_2fa','confirm_2fa','disable_2fa','regenerate_recovery','revoke_device','revoke_all_devices'];
        if (in_array($action, $authActions, true)) {
            try {
                if ($action === 'change_password' || $action === 'setup') {
                    $confirmation = $_POST['password_confirm'] ?? $_POST['password_confirmation'] ?? null;
                    if (!is_string($confirmation) || !is_string($_POST['password'] ?? null) || !hash_equals($_POST['password'], $confirmation)) throw new InvalidArgumentException('Passwords must match.');
                }
                $authResult = $auth->action($_POST);
                if (!in_array($action, ['begin_2fa','confirm_2fa','regenerate_recovery'], true)) {
                    header('Location: index.php', true, 303); exit;
                }
                $message = 'Account security updated. Save any recovery codes shown below.';
            } catch (DomainException | InvalidArgumentException $exception) { $error = $exception->getMessage(); if ($exception instanceof NiraAdminRateLimit) { http_response_code(429); header('Retry-After: '.$exception->retryAfter); } }
            catch (Throwable $exception) { $error = 'Authentication action unavailable. Check the external key and storage; no reset is required.'; }
        } elseif ($auth->authenticated() && $database instanceof PDO) {
            if ($action === 'minimum_versions') {
                $androidMinimum = registry_valid_version($_POST['minimum_android_version'] ?? null);
                $androidMinimumBuild = registry_valid_build($_POST['minimum_android_build'] ?? null);
                $windowsMinimum = registry_valid_version($_POST['minimum_windows_version'] ?? null);
                $windowsUpdateMinimum = registry_valid_version($_POST['minimum_windows_update_version'] ?? null);
                if ($androidMinimum === null || $androidMinimumBuild === null || $windowsMinimum === null || $windowsUpdateMinimum === null) {
                    $error = 'Versions must use semantic format and Android build must be a non-negative integer.';
                } else {
                    $statement = $database->prepare(
                        'INSERT INTO admin_settings (setting_key, setting_value, updated_at) VALUES (:key, :value, :updated_at)
                         ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value, updated_at = excluded.updated_at'
                    );
                    $database->beginTransaction();
                    try {
                        $statement->execute([':key' => 'minimum_android_version', ':value' => $androidMinimum, ':updated_at' => registry_now()]);
                        $statement->execute([':key' => 'minimum_android_build', ':value' => (string)$androidMinimumBuild, ':updated_at' => registry_now()]);
                        $statement->execute([':key' => 'minimum_windows_version', ':value' => $windowsMinimum, ':updated_at' => registry_now()]);
                        $statement->execute([':key' => 'minimum_windows_update_version', ':value' => $windowsUpdateMinimum, ':updated_at' => registry_now()]);
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

$authenticated = $auth instanceof NiraAdminAuth && $auth->authenticated();
$pending2fa = $auth instanceof NiraAdminAuth && $auth->pending();
$minimumAndroidVersion = $database instanceof PDO
    ? registry_minimum_version($database, 'android')
    : NIRANG_DEFAULT_MINIMUM_ANDROID_VERSION;
$minimumWindowsVersion = $database instanceof PDO
    ? registry_minimum_version($database, 'windows')
    : NIRANG_DEFAULT_MINIMUM_WINDOWS_VERSION;
$minimumWindowsUpdateVersion = $database instanceof PDO
    ? registry_minimum_update_version($database, 'windows')
    : NIRANG_DEFAULT_MINIMUM_WINDOWS_UPDATE_VERSION;
$minimumAndroidBuild = $database instanceof PDO
    ? registry_minimum_android_build($database)
    : NIRANG_DEFAULT_MINIMUM_ANDROID_BUILD;
$latestAndroidVersion = $authenticated
    ? registry_latest_release_version($database, 'bardia-us/niraNG')
    : null;
$latestWindowsVersion = $authenticated
    ? registry_latest_release_version($database, 'bardia-us/niraN')
    : null;
$rows = [];
$search = is_string($_GET['q'] ?? null) ? trim(substr($_GET['q'], 0, 256)) : '';
if ($authenticated) {
    $rows = panel_device_rows($database, $search);
}
$timezoneName = getenv('NIRAN_ADMIN_TIMEZONE');
try { $displayTimezone = new DateTimeZone(is_string($timezoneName) && $timezoneName !== '' ? $timezoneName : 'Asia/Tehran'); }
catch (Throwable $exception) { $displayTimezone = new DateTimeZone('UTC'); }
?>
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>niraN / niraNG Device Registry</title>
<style nonce="<?= e($nonce) ?>">
:root{color-scheme:dark;--bg:#0d0b14;--panel:#171321;--line:#302a40;--text:#f4efff;--muted:#aaa1bd;--accent:#8b7cf6}*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at top,#211a38,var(--bg) 40%);color:var(--text);font:14px system-ui,sans-serif}main{max-width:1280px;margin:auto;padding:22px}.card{background:rgba(23,19,33,.94);border:1px solid var(--line);border-radius:14px;padding:16px;margin-bottom:14px}h1,h2{margin:0 0 14px}h1{font-size:23px}h2{font-size:17px}p{color:var(--muted)}a{color:#bcb2ff}input,button{border-radius:9px;border:1px solid var(--line);padding:9px 12px;background:#211b2f;color:var(--text)}button{cursor:pointer;background:var(--accent);border:0;font-weight:700}.danger{background:#a93650}.secondary{background:#3a334a}.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.right{margin-left:auto}.toolbar{margin-bottom:14px}
.badge{display:inline-block;padding:4px 8px;border-radius:999px;font-weight:800;font-size:12px}.allowed{background:#173d34;color:#7ce6c2}.blocked{background:#4b1f2b;color:#ff9bac}.outdated{background:#49391a;color:#ffd57f}.unknown{background:#34303c;color:#c6bdcf}.reinstall{background:#39295b;color:#cbbcff}.latest{background:#172f4d;color:#8fd0ff}
table{border-collapse:collapse;width:100%;min-width:1050px}th,td{text-align:left;padding:9px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--muted);font-size:12px}.mono{font-family:ui-monospace,monospace;font-size:12px}.device-key{white-space:nowrap;cursor:help}.table-wrap{overflow:auto}.notice{padding:10px;border-radius:9px;margin:10px 0}.error{background:#4b1f2b}.success{background:#173d34}
.platform{display:inline-flex;align-items:center;gap:6px;font-weight:700}.platform svg{width:17px;height:17px;fill:currentColor;flex:none}.platform.android{color:#82d8a1}.platform.windows{color:#80baff}.auth{max-width:480px;margin:24px auto}.auth form{display:grid;gap:12px}.auth label{display:grid;gap:6px;color:var(--muted)}.auth input{width:100%}
.policy{gap:12px;align-items:end}.policy label{display:grid;gap:6px;color:var(--muted);font-size:12px}.policy input{width:180px}.policy-note{font-size:12px;line-height:1.6;margin-bottom:0}.search{margin-bottom:12px}.search input{min-width:240px;flex:1}@media(max-width:700px){main{padding:14px}.right{margin-left:0}.search input{min-width:0;width:100%}.policy label,.policy input{width:100%}}
<?php readfile(__DIR__.'/admin-auth/ui.css'); ?>
</style></head><body><main>
<div class="row toolbar"><h1>niraN / niraNG Device Registry</h1><?php if ($authenticated): ?><form class="right" method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="logout"><button class="secondary">Log out</button></form><?php endif; ?></div>
<?php if ($error !== null): ?><div class="notice error"><?= e($error) ?></div><?php endif; ?>
<?php if ($message !== null): ?><div class="notice success"><?= e($message) ?></div><?php endif; ?>
<?php if (!$authenticated): ?>
<section class="card auth"><h2><?= $pending2fa ? 'Verify your authenticator' : ($setupRequired ? 'Create administrator account' : 'Registry administrator login') ?></h2>
<?php if ($pending2fa): ?>
<form method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="verify_2fa"><?php admin_auth_otp('registry-login-code', true); ?><label class="remember-choice"><input name="remember" type="checkbox" value="1">Remember this device for 15 days</label><button>Verify and enter registry</button></form>
<form method="post" class="auth-secondary"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="logout"><button class="secondary">Use another account</button></form>
<?php elseif (!$setupRequired || registry_environment('NIRAN_ADMIN_SETUP_TOKEN') !== null): ?>
<form method="post" id="nira-registry-login" autocomplete="on"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="<?= $setupRequired ? 'setup' : 'login' ?>">
<label for="admin-username">Registry username<input id="admin-username" type="text" name="username" autocomplete="username" maxlength="100" required></label>
<label for="admin-password">Password<input id="admin-password" type="password" name="password" <?= $setupRequired ? 'minlength="10"' : '' ?> maxlength="72" autocomplete="<?= $setupRequired ? 'new-password' : 'current-password' ?>" required></label>
<?php if ($setupRequired): ?><label for="admin-confirmation">Confirm password<input id="admin-confirmation" type="password" name="password_confirmation" minlength="10" maxlength="72" autocomplete="new-password" required></label><label>Hosting setup token<input type="password" name="setup_token" autocomplete="off" required></label><?php endif; ?><button type="submit">Continue to registry</button></form>
<?php else: ?><p>Public registration is disabled. Configure NIRAN_ADMIN_SETUP_TOKEN outside the web root; see ADMIN_AUTH.md.</p><?php endif; ?></section>
<?php else: ?>
<details class="card" <?= $authResult ? 'open' : '' ?>><summary>Account security · authenticator and trusted devices</summary><?php admin_auth_security($auth, $authResult); ?></details>
<section class="card"><h2>Remote access policy</h2><form method="post" class="row policy"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="action" value="minimum_versions"><label>Android display version <input name="minimum_android_version" value="<?= e($minimumAndroidVersion) ?>" pattern="[0-9]+\.[0-9]+\.[0-9]+.*" required></label><label>Android minimum build <input name="minimum_android_build" type="number" min="0" step="1" value="<?= $minimumAndroidBuild ?>" required></label><label>Windows registry status minimum <input name="minimum_windows_version" value="<?= e($minimumWindowsVersion) ?>" pattern="[0-9]+\.[0-9]+\.[0-9]+.*" required></label><label>Windows forced-update minimum <input name="minimum_windows_update_version" value="<?= e($minimumWindowsUpdateVersion) ?>" pattern="[0-9]+\.[0-9]+\.[0-9]+.*" required></label><button>Save</button></form>
<p class="policy-note">Android forced updates use build <?= $minimumAndroidBuild ?>; Windows uses version <?= e($minimumWindowsUpdateVersion) ?>. Registry Status follows the display minimum above. Latest GitHub releases: niraNG <?= e($latestAndroidVersion ?? 'unavailable') ?> / niraN <?= e($latestWindowsVersion ?? 'unavailable') ?>.</p></section>
<section class="card"><h2>Devices (<?= count($rows) ?><?= count($rows) === 1000 ? ' — first 1000 matches' : '' ?>)</h2>
<form method="get" class="row search" role="search"><label for="device-search">Device / Device Key</label><input id="device-search" type="search" name="q" value="<?= e($search) ?>" maxlength="256" placeholder="Search device name or full key"><button type="submit">Search</button><?php if ($search !== ''): ?><a href="index.php">Clear</a><?php endif; ?></form>
<div class="table-wrap"><table><thead><tr><th>Status</th><th>Device</th><th>Platform / Version</th><th>Device Key</th><th>Installation ID</th><th>First Seen</th><th>Last Seen</th><th>Action</th></tr></thead><tbody>
<?php foreach ($rows as $row):
    $version = is_string($row['app_version']) ? $row['app_version'] : '0.0.0';
    $platform = $row['platform'] === 'android' ? 'android' : 'windows';
    $minimumVersion = $platform === 'android' ? $minimumAndroidVersion : $minimumWindowsVersion;
    $latestVersion = $platform === 'android' ? $latestAndroidVersion : $latestWindowsVersion;
    $hasDeviceKey = is_string($row['device_key']) && preg_match('/^[0-9a-f]{64}$/', $row['device_key']) === 1;
    $appBuild = (int)($row['app_build'] ?? 0);
    $displayState = registry_display_status(
        $version,
        $minimumVersion,
        (string)($row['access_status'] ?? ''),
        $hasDeviceKey,
        $latestVersion
    );
    $outdated = $displayState['outdated'];
    $controllable = $hasDeviceKey && !$outdated;
    $blocked = $hasDeviceKey && ($row['access_status'] ?? '') === 'blocked';
    $status = $displayState['status'];
?>
<tr><td><span class="badge <?= e($status) ?>"><?= e(ucfirst($status)) ?></span><?php if ($blocked && $outdated): ?> <span class="badge outdated">Outdated</span><?php endif; ?><?php if ((int)$row['reinstalled_after_block'] === 1): ?><br><span class="badge reinstall">Reinstalled after block</span><?php endif; ?><?php if ($outdated): ?><br><small>Remote control unavailable.<br>User must update <?= $platform === 'android' ? 'niraNG' : 'niraN' ?> to <?= e($minimumVersion) ?> or newer.</small><?php endif; ?></td>
<td><strong><?= e((string)($row['device_name'] ?: $row['device_model'] ?: 'Unknown device')) ?></strong><br><small><?= e(trim((string)$row['manufacturer'] . ' ' . (string)$row['model'])) ?></small></td>
<td><span class="platform <?= e($platform) ?>"><?php if ($platform === 'android'): ?><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 8 4 5l1-.6L7.1 7a10 10 0 0 1 9.8 0L19 4.4l1 .6-2 3a7 7 0 0 1 3 6H3a7 7 0 0 1 3-6ZM7 10a1 1 0 1 0 2 0 1 1 0 0 0-2 0Zm8 0a1 1 0 1 0 2 0 1 1 0 0 0-2 0ZM5 16h14v4H5z"/></svg>Android<?php else: ?><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m2 4 9-1v8H2Zm11-1 9-1v9h-9ZM2 13h9v8l-9-1Zm11 0h9v9l-9-1Z"/></svg>Windows<?php endif; ?></span><br><?= e((string)$row['app_name'] . ' ' . $version) ?><?php if ($displayState['latest']): ?> <span class="badge latest">Latest version</span><?php endif; ?><?php if ($platform === 'android'): ?><br><small>Build <?= $appBuild ?></small><?php endif; ?></td>
<td class="mono device-key" title="<?= e((string)($row['device_key'] ?? '')) ?>"><?= e(registry_short_key(is_string($row['device_key']) ? $row['device_key'] : null)) ?><?php if ((int)$row['bypass_attempts'] > 0): ?><br><small>Attempts: <?= (int)$row['bypass_attempts'] ?></small><?php endif; ?></td>
<td class="mono"><?= e((string)$row['installation_id']) ?></td><td><?= e(display_timestamp($row['first_seen'], $displayTimezone)) ?></td><td><?= e(display_timestamp($row['last_seen'], $displayTimezone)) ?></td>
<td><?php if ($controllable || $blocked): ?><form method="post"><input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>"><input type="hidden" name="device_key" value="<?= e((string)$row['device_key']) ?>"><input type="hidden" name="action" value="<?= $blocked ? 'unblock' : 'block' ?>"><button class="<?= $blocked ? 'secondary' : 'danger' ?>"><?= $blocked ? 'Unblock' : 'Block' ?></button></form><?php else: ?>—<?php endif; ?></td></tr>
<?php endforeach; ?><?php if ($rows === []): ?><tr><td colspan="8">No devices found.</td></tr><?php endif; ?></tbody></table></div></section>
<?php endif; ?></main></body></html>
