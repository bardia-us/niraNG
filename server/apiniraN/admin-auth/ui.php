<?php
declare(strict_types=1);
function admin_auth_e($value): string { return htmlspecialchars((string)$value,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8'); }
function admin_auth_otp(string $id='otp-code',bool $recovery=false): void { ?>
<label for="<?=admin_auth_e($id)?>">Authenticator · 6 digits</label>
<input class="otp-input" id="<?=admin_auth_e($id)?>" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" maxlength="6" pattern="[0-9]{6}" dir="ltr" <?=$recovery?'':'required'?> placeholder="000000">
<?php if($recovery): ?><details><summary>Use a recovery code instead</summary><label for="<?=admin_auth_e($id)?>-recovery">One-use recovery code</label><input id="<?=admin_auth_e($id)?>-recovery" name="recovery_code" type="text" autocomplete="off" maxlength="17" pattern="[a-f0-9]{8}-[a-f0-9]{8}" dir="ltr"></details><?php endif; ?>
<?php }
function admin_auth_result(array $result): void {
    if (isset($result['qr_svg'])) { ?>
<section class="auth-notice"><h3>Scan with Google Authenticator</h3><p>QR generated locally. Confirm a fresh code below to enable 2FA.</p><img width="240" height="240" alt="Local authenticator setup QR" src="data:image/svg+xml;base64,<?=base64_encode($result['qr_svg'])?>"><p>Manual key: <code class="secret-value"><?=admin_auth_e($result['manual_secret'])?></code></p></section>
<?php }
    if (isset($result['recovery_codes'])) { ?>
<section class="auth-notice" role="status"><h3>Save your recovery codes now</h3><p>Shown once. Store them offline; every code works only once.</p><pre class="secret-value"><?=admin_auth_e(implode("\n",$result['recovery_codes']))?></pre></section>
<?php }
}
function admin_auth_security(NiraAdminAuth $auth,array $result=[]): void {
    $status=$auth->status(); $enabled=$status['two_factor_enabled']; $csrf=$auth->csrf();
    admin_auth_result($result);
    $hidden=static function(string $action)use($csrf): void { ?><input type="hidden" name="csrf" value="<?=admin_auth_e($csrf)?>"><input type="hidden" name="action" value="<?=admin_auth_e($action)?>"><?php };
    $proof=static function(string $id)use($enabled): void { ?><label for="<?=$id?>-password">Current password</label><input id="<?=$id?>-password" name="current_password" type="password" autocomplete="current-password" required><?php if($enabled) admin_auth_otp($id.'-code',true); };
?>
<div class="auth-security"><header><h2>Account security</h2><p>2FA: <strong><?=$enabled?'Enabled':'Optional · disabled'?></strong> · Remember devices for 15 days after a correct password.</p></header>
<form method="post" class="stack auth-form" autocomplete="on"><?php $hidden('change_password'); ?><h3>Change password</h3><input type="hidden" name="username" autocomplete="username" value="<?=admin_auth_e($status['username'])?>"><?php $proof('change-password'); ?><label for="new-password">New password</label><input id="new-password" name="password" type="password" autocomplete="new-password" minlength="10" maxlength="72" required><label for="confirm-password">Confirm new password</label><input id="confirm-password" name="password_confirm" type="password" autocomplete="new-password" minlength="10" maxlength="72" required><button type="submit">Save password</button></form>
<form method="post" class="stack auth-form" autocomplete="on"><?php $hidden('change_username'); ?><h3>Change username</h3><label for="new-username">Username</label><input id="new-username" name="username" autocomplete="username" value="<?=admin_auth_e($status['username'])?>" minlength="3" maxlength="100" pattern="[a-zA-Z0-9_.@-]+" required><?php $proof('change-username'); ?><button>Save username</button></form>
<?php if(!$enabled): ?>
<form method="post" class="stack auth-form"><?php $hidden('begin_2fa'); ?><h3>Enable Google Authenticator</h3><?php $proof('begin-2fa'); ?><button>Create local QR</button></form>
<?php if(isset($_SESSION['enrollment']) && ($_SESSION['enrollment']['until']??0)>time()): ?><form method="post" class="stack auth-form"><?php $hidden('confirm_2fa'); ?><h3>Confirm setup</h3><?php admin_auth_otp('confirm-2fa'); ?><button>Verify and enable 2FA</button></form><?php endif; ?>
<?php else: ?>
<form method="post" class="stack auth-form"><?php $hidden('regenerate_recovery'); ?><h3>Replace recovery codes</h3><?php $proof('recovery'); ?><button>Generate replacement codes</button></form>
<form method="post" class="stack auth-form"><?php $hidden('disable_2fa'); ?><h3>Disable / reset authenticator</h3><p>Disabling revokes all trusted devices and other sessions. To reset, disable then enroll a new authenticator.</p><?php $proof('disable-2fa'); ?><button class="danger">Disable 2FA</button></form>
<?php endif; ?>
<section class="auth-form"><h3>Trusted devices</h3><p>Revoking a device also closes sessions authenticated through that device. Reuse of an old rotated token revokes its device.</p>
<?php foreach($status['devices'] as $device): ?><form method="post" class="row"><?php $hidden('revoke_device'); ?><input type="hidden" name="selector" value="<?=admin_auth_e($device['selector'])?>"><span><?=admin_auth_e(gmdate('Y-m-d H:i',$device['created']))?> UTC · expires <?=admin_auth_e(gmdate('Y-m-d',$device['expires']))?><?=$device['current']?' · this device':''?></span><button class="secondary">Revoke device</button></form><?php endforeach; ?>
<?php if(!$status['devices']): ?><p>No remembered devices.</p><?php endif; ?>
<form method="post"><?php $hidden('revoke_all_devices'); ?><button class="secondary">Revoke all devices</button></form></section>
<p>Password or username changes revoke remembered devices and other sessions. Password managers may group accounts on the same origin; separate hostnames are required for complete site separation.</p></div>
<?php }
