<?php
declare(strict_types=1);

// CLI-only integration driver. Never deploy tests to the public web root.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
$input = json_decode($argv[1], true, 32, JSON_THROW_ON_ERROR);
putenv('NIRAN_REGISTRY_DB=' . $input['database']);
putenv('NIRAN_ADMIN_PASSWORD_HASH=' . ($input['hash'] ?? ''));
putenv('NIRAN_ADMIN_SETUP_TOKEN=' . ($input['setup_token'] ?? ''));
ini_set('session.save_path', $input['sessions']);
session_name('niran_admin');
session_id($input['session_id']);
if (isset($input['seed'])) {
    session_start();
    $_SESSION = $input['seed'];
    session_write_close();
}
$_SERVER['REQUEST_METHOD'] = $input['method'] ?? 'GET';
$_SERVER['REMOTE_ADDR'] = $input['ip'] ?? '192.0.2.10';
$_SERVER['HTTP_X_FORWARDED_FOR'] = $input['forwarded'] ?? '192.0.2.99';
$_SERVER['HTTPS'] = $input['https'] ?? 'on';
$_POST = $input['post'] ?? [];
$_GET = $input['get'] ?? [];
register_shutdown_function(static function (): void {
    echo "\nPANEL_TEST_STATE:" . json_encode([
        'session' => $_SESSION ?? [], 'session_id' => session_id(),
        'status' => http_response_code() ?: 200,
        'cookie' => session_get_cookie_params(),
    ], JSON_THROW_ON_ERROR);
});
require dirname(__DIR__) . '/index.php';
