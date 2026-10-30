# Shared niraN / niraNG API deployment notes

Upload `api.php`, `registry.php`, `panel.php`, `index.php`, `admin_auth.php`, and the
complete `admin-auth/` runtime together; follow `ADMIN_AUTH.md` for private keys,
setup, PHP 8.5.12/PDO SQLite, backups and rollback. The SQLite migration is
performed automatically and adds expiring access-token metadata, replay nonces,
and rate-limit buckets without removing existing device or block records.

This directory is the shared backend for both clients: Android `niraNG` and
Windows `niraN`. Deploy the matching PHP/runtime files as one set. The admin panel keeps
Android display/build policy and Windows display/forced-update policy separate;
changing the Windows update minimum never changes Android access or registry
status.

The panel requires HTTPS as reported by the web server (`HTTPS=on`/`1` or
`SERVER_PORT=443`). Its session cookies stay Secure, HttpOnly and SameSite=Strict;
CSRF validation and the nonce-based Content Security Policy remain enabled.
Login forms expose the configurable administrator username to password managers,
with `autocomplete=username` and `current-password` (or `new-password` for setup
and changes). Existing registry accounts initially retain username `admin` and
their password hash. New setup requires a private hosting setup token. Optional
TOTP, recovery codes and 15-day remembered devices are documented in `ADMIN_AUTH.md`.

Five wrong passwords lock the single administrator account for exactly 60 seconds.
The panel stores its versioned auth state under the `admin_auth_v1` setting in the
existing private SQLite database; it does not change device rows or API policy. Writer transactions
serialize concurrent login checks. Clearing cookies, opening another browser or
changing IP does not bypass the account-wide counter. Requests during a lock do
not move its expiry; after expiry the counter starts fresh, and a successful login
also resets it. The account-wide choice prevents attacks distributed across IPs,
but an attacker can briefly lock out this shared administrator account by sending
five failures. Existing authenticated sessions continue working during a login lock.

Sessions carry the account generation; credential/2FA changes invalidate old
generations. Changes of VPN, network or public IP do not terminate a valid session.
Sessions predating this change require fresh login. The panel never trusts arbitrary
`X-Forwarded-For`, `Forwarded` or other client-provided address headers. TLS
termination must set the trusted server HTTPS indicator; forwarding a header
from the browser is not sufficient.

Mixed-profile capability uses the request header `X-Nira-Profile-Version: 1` only
on subscription requests. The JSON schema/body stays unchanged, so older API
deployments safely ignore the new header. After normal device authentication,
only Android with the exact header value `1` forwards capability to my-sub.
Windows, absent headers and unsupported values do not. The bearer, blocked-device,
expiry and HMAC controls remain independent of capability negotiation.

Device search covers the full key and device name/model/manufacturer. The SQLite
query uses bound parameters and treats `%`, `_` and `!` literally. All rendered
values are HTML escaped. Results retain the existing 1000-row cap; the full key is
available in the short key's tooltip. Android/Windows icons are inline SVG with no
external assets or tracking requests.

Do not upload `tests/`. Run the isolated backend checks locally with PHP and PDO
SQLite: `php tests/registry_test.php` and `php tests/panel_test.php`. Tests create
and remove their own temporary database/session files, not the deployed registry.

The Android client pins the API TLS public keys only. Before rotating away from
both the current leaf key and Let's Encrypt YR2 intermediate, ship a client build
whose `NIRANG_API_SPKI_PINS` Gradle property contains the new primary pin and one
working backup pin. The value is a comma-separated pair of `sha256/<base64-spki>`
pins; it is public metadata, not a secret.

Keep `NIRANG_ANDROID_SUBSCRIPTION_UPSTREAM`, panel credentials, and the SQLite
database outside the public web root and source control. Never put the upstream
subscription URL in Android Gradle properties that are compiled into the APK.

For an enhanced-security `my-sub` record, set the same random server-only value
of at least 32 characters as `NIRAN_SUBSCRIPTION_HMAC_SECRET` on both PHP hosts.
The API then signs a short-lived, path-bound request to `my-sub`; the Android APK
receives neither the upstream URL nor the HMAC secret. On shared cPanel hosting,
Apache `SetEnv` values from `.htaccess` are accepted through PHP's `$_SERVER`
fallback. Ordinary records with enhanced security disabled remain compatible
with v2rayNG, V2Box, and other clients.
