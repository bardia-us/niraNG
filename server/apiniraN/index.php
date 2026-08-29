<?php
declare(strict_types=1);

header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
$nonce = base64_encode(random_bytes(18));
header("Content-Security-Policy: default-src 'none'; style-src 'nonce-{$nonce}'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");

session_name('niran_admin');
session_set_cookie_params([
    'lifetime' => 0,
    'path' => '/apiniraN/',
    'secure' => true,
    'httponly' => true,
    'samesite' => 'Strict',
]);
session_start();

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
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
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS admin_settings (
            setting_key TEXT PRIMARY KEY,
            setting_value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )'
    );
    return $pdo;
}

function is_password_hash($value): bool
{
    if (!is_string($value) || $value === '') {
        return false;
    }
    $info = password_get_info($value);
    return ($info['algoName'] ?? 'unknown') !== 'unknown';
}

function stored_admin_hash(PDO $pdo): ?string
{
    $statement = $pdo->prepare(
        'SELECT setting_value FROM admin_settings WHERE setting_key = :setting_key LIMIT 1'
    );
    $statement->execute([':setting_key' => 'admin_password_hash']);
    $value = $statement->fetchColumn();
    return is_string($value) && $value !== '' ? $value : null;
}

function csrf_token(): string
{
    if (!isset($_SESSION['csrf']) || !is_string($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function valid_csrf(): bool
{
    return isset($_POST['csrf'], $_SESSION['csrf']) &&
        is_string($_POST['csrf']) && is_string($_SESSION['csrf']) &&
        hash_equals($_SESSION['csrf'], $_POST['csrf']);
}

function display_timestamp($value, DateTimeZone $timezone): string
{
    if (!is_string($value) || $value === '') {
        return '—';
    }
    try {
        return (new DateTimeImmutable($value))
            ->setTimezone($timezone)
            ->format('Y/m/d - H:i');
    } catch (Exception $exception) {
        return '—';
    }
}

$configurationError = null;
$database = null;
$passwordHash = null;
$setupRequired = false;
try {
    $database = registry_database();
} catch (Throwable $exception) {
    $configurationError = 'The registry database is unavailable.';
}

$environmentHash = getenv('NIRAN_ADMIN_PASSWORD_HASH');
if (is_string($environmentHash) && $environmentHash !== '') {
    if (is_password_hash($environmentHash)) {
        $passwordHash = $environmentHash;
    } else {
        $configurationError = 'The configured administrator password hash is invalid.';
    }
} elseif ($database instanceof PDO) {
    try {
        $storedHash = stored_admin_hash($database);
        if ($storedHash === null) {
            $setupRequired = true;
        } elseif (is_password_hash($storedHash)) {
            $passwordHash = $storedHash;
        } else {
            $configurationError = 'The stored administrator password hash is invalid.';
        }
    } catch (Throwable $exception) {
        $configurationError = 'The administrator configuration is unavailable.';
    }
}

$error = null;
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    if (!valid_csrf()) {
        $error = 'The request expired. Please try again.';
    } elseif (($_POST['action'] ?? '') === 'logout') {
        $_SESSION = [];
        session_regenerate_id(true);
        header('Location: index.php', true, 303);
        exit;
    } elseif (($_POST['action'] ?? '') === 'setup' && $setupRequired && $database instanceof PDO) {
        $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
        $confirmation = is_string($_POST['password_confirmation'] ?? null)
            ? $_POST['password_confirmation']
            : '';
        if (strlen($password) < 10 || strlen($password) > 1024) {
            $error = 'Use a password containing at least 10 characters.';
        } elseif (!hash_equals($password, $confirmation)) {
            $error = 'Password confirmation does not match.';
        } else {
            try {
                $hash = password_hash($password, PASSWORD_DEFAULT);
                if (!is_string($hash) || !is_password_hash($hash)) {
                    throw new RuntimeException('Password hashing failed');
                }
                $database->beginTransaction();
                if (stored_admin_hash($database) !== null) {
                    $database->rollBack();
                    $error = 'Administrator setup has already been completed.';
                } else {
                    $statement = $database->prepare(
                        'INSERT INTO admin_settings (setting_key, setting_value, updated_at)
                         VALUES (:setting_key, :setting_value, :updated_at)'
                    );
                    $statement->execute([
                        ':setting_key' => 'admin_password_hash',
                        ':setting_value' => $hash,
                        ':updated_at' => (new DateTimeImmutable('now', new DateTimeZone('UTC')))->format(DateTimeInterface::ATOM),
                    ]);
                    $database->commit();
                    session_regenerate_id(true);
                    $_SESSION['authenticated'] = true;
                    $_SESSION['attempts'] = 0;
                    header('Location: index.php', true, 303);
                    exit;
                }
            } catch (Throwable $exception) {
                if ($database->inTransaction()) {
                    $database->rollBack();
                }
                $error = 'The administrator password could not be saved.';
            }
        }
    } elseif (($_POST['action'] ?? '') === 'login' && $configurationError === null) {
        $lockedUntil = (int)($_SESSION['locked_until'] ?? 0);
        if ($lockedUntil > time()) {
            $error = 'Too many attempts. Please wait before trying again.';
        } else {
            $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
            if (strlen($password) <= 1024 && password_verify($password, $passwordHash)) {
                session_regenerate_id(true);
                $_SESSION['authenticated'] = true;
                $_SESSION['attempts'] = 0;
                unset($_SESSION['locked_until']);
                header('Location: index.php', true, 303);
                exit;
            }
            $attempts = min(10, (int)($_SESSION['attempts'] ?? 0) + 1);
            $_SESSION['attempts'] = $attempts;
            if ($attempts >= 5) {
                $_SESSION['locked_until'] = time() + min(900, 30 * ($attempts - 4));
            }
            $error = 'Invalid password.';
        }
    }
}

$authenticated = ($_SESSION['authenticated'] ?? false) === true;
$rows = [];
$timezoneName = getenv('NIRAN_ADMIN_TIMEZONE');
if (!is_string($timezoneName) || $timezoneName === '') {
    $timezoneName = 'Asia/Tehran';
}
try {
    $displayTimezone = new DateTimeZone($timezoneName);
} catch (Exception $exception) {
    $displayTimezone = new DateTimeZone('Asia/Tehran');
    $timezoneName = 'Asia/Tehran';
}
if ($authenticated) {
    try {
        $rows = $database
            ->query('SELECT platform, device_name, windows_username, windows_version,
                manufacturer, model, os_version, app_name, app_version,
                first_seen, last_seen
                FROM installations ORDER BY last_seen DESC LIMIT 1000')
            ->fetchAll();
    } catch (Throwable $exception) {
        $error = 'The registry database is unavailable.';
    }
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>niraN / niraNG Device Registry</title>
  <style nonce="<?= e($nonce) ?>">
    :root { color-scheme: dark; font-family: Inter, Segoe UI, sans-serif; background:#0d0d12; color:#f4f2ff; }
    body { margin:0; padding:32px; }
    main { max-width:1200px; margin:auto; }
    .panel { background:#191820; border:1px solid #353241; border-radius:18px; padding:24px; box-shadow:0 20px 60px #0006; }
    h1 { margin:0 0 20px; font-size:24px; }
    form.login { max-width:380px; }
    input, button { box-sizing:border-box; border-radius:10px; border:1px solid #494459; padding:11px 13px; font:inherit; }
    input { width:100%; color:#fff; background:#111016; margin:8px 0 14px; }
    button { cursor:pointer; color:#fff; background:#7457d7; }
    .logout { float:right; }
    .error { color:#ffaaa5; margin:12px 0; }
    .meta { color:#aaa5b5; margin-bottom:18px; }
    .table-wrap { overflow:auto; }
    table { width:100%; border-collapse:collapse; min-width:1040px; }
    th, td { text-align:left; padding:14px 16px; border-bottom:1px solid #302e39; white-space:nowrap; }
    th { color:#c7baff; font-size:13px; }
    td { font-size:14px; }
    th.time, td.time { min-width:145px; }
    code { color:#c8c2d5; }
  </style>
</head>
<body>
<main>
  <section class="panel">
    <?php if (!$authenticated): ?>
      <h1>niraN / niraNG Device Registry</h1>
      <p class="meta"><?= $setupRequired ? 'Create the administrator password for first-time setup' : 'Private administrator access' ?></p>
      <?php if ($configurationError !== null): ?><p class="error"><?= e($configurationError) ?></p><?php endif; ?>
      <?php if ($error !== null): ?><p class="error"><?= e($error) ?></p><?php endif; ?>
      <?php if ($configurationError === null && $setupRequired): ?>
      <form class="login" method="post" action="index.php" autocomplete="off">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="setup">
        <label for="password">New password</label>
        <input id="password" name="password" type="password" required autofocus autocomplete="new-password" minlength="10" maxlength="1024">
        <label for="password_confirmation">Confirm password</label>
        <input id="password_confirmation" name="password_confirmation" type="password" required autocomplete="new-password" minlength="10" maxlength="1024">
        <p class="meta">The password is hashed before it is stored. The original password cannot be recovered.</p>
        <button type="submit">Create password</button>
      </form>
      <?php elseif ($configurationError === null): ?>
      <form class="login" method="post" action="index.php" autocomplete="off">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="login">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required autofocus autocomplete="current-password" maxlength="1024">
        <button type="submit">Sign in</button>
      </form>
      <?php endif; ?>
    <?php else: ?>
      <form class="logout" method="post" action="index.php">
        <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
        <input type="hidden" name="action" value="logout">
        <button type="submit">Sign out</button>
      </form>
      <h1>niraN / niraNG Device Registry</h1>
      <p class="meta"><?= count($rows) ?> installations shown · newest activity first · <?= e($timezoneName) ?></p>
      <?php if ($error !== null): ?><p class="error"><?= e($error) ?></p><?php endif; ?>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Platform</th><th>Device Name</th><th>Identity / Model</th><th>Operating System</th><th>Application</th><th class="time">First Seen</th><th class="time">Last Seen</th></tr></thead>
          <tbody>
          <?php foreach ($rows as $row): ?>
            <tr>
              <td><?= e(ucfirst((string)($row['platform'] !== '' ? $row['platform'] : 'windows'))) ?></td>
              <td><?= e((string)($row['device_name'] !== '' ? $row['device_name'] : '—')) ?></td>
              <td><?= e((string)($row['platform'] === 'android'
                  ? trim($row['manufacturer'] . ' ' . $row['model'])
                  : ($row['windows_username'] !== '' ? $row['windows_username'] : '—'))) ?></td>
              <td><?= e((string)($row['platform'] === 'android' ? $row['os_version'] : $row['windows_version'])) ?></td>
              <td><?= e((string)(($row['app_name'] !== '' ? $row['app_name'] : 'niraN') . ' ' . $row['app_version'])) ?></td>
              <td class="time"><?= e(display_timestamp($row['first_seen'], $displayTimezone)) ?></td>
              <td class="time"><?= e(display_timestamp($row['last_seen'], $displayTimezone)) ?></td>
            </tr>
          <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </section>
</main>
</body>
</html>
