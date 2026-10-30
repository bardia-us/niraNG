<?php
declare(strict_types=1);
require_once __DIR__.'/admin-auth/AdminAuth.php';
function panel_auth(PDO $pdo): NiraAdminAuth
{
    $read=static function()use($pdo): array {
        $statement=$pdo->prepare('SELECT setting_value FROM admin_settings WHERE setting_key = :key');
        $statement->execute([':key'=>'admin_auth_v1']); $raw=$statement->fetchColumn();
        if ($raw!==false) { $state=json_decode($raw,true,32,JSON_THROW_ON_ERROR); if (!is_array($state)) throw new RuntimeException('Invalid authentication state.'); return $state; }
        // Import legacy credentials only; never modify the registry's data or settings.
        $statement->execute([':key'=>'admin_password_hash']); $hash=$statement->fetchColumn();
        $environment=registry_environment('NIRAN_ADMIN_PASSWORD_HASH');
        $hash=$environment??$hash;
        return is_string($hash) && $hash!=='' ? ['username'=>'admin','password_hash'=>$hash] : [];
    };
    $transaction=static function(callable $callback)use($pdo,$read): array {
        $pdo->exec('BEGIN IMMEDIATE');
        try {
            $state=$read(); $result=$callback($state);
            $statement=$pdo->prepare('INSERT INTO admin_settings (setting_key, setting_value, updated_at) VALUES (:key, :value, :at) ON CONFLICT(setting_key) DO UPDATE SET setting_value=excluded.setting_value, updated_at=excluded.updated_at');
            $statement->execute([':key'=>'admin_auth_v1',':value'=>json_encode($state,JSON_THROW_ON_ERROR),':at'=>registry_now()]);
            $pdo->exec('COMMIT'); return $result;
        } catch(Throwable $error) { $pdo->exec('ROLLBACK'); throw $error; }
    };
    return new NiraAdminAuth($read,$transaction,['realm'=>'nira-registry-admin:v1','issuer'=>'nira Registry','key_env'=>'NIRAN_ADMIN_TOTP_KEY','session'=>'niran_admin','cookie'=>'niran_registry_trust','path'=>'/apiniraN/','setup_token'=>registry_environment('NIRAN_ADMIN_SETUP_TOKEN')??'']);
}
