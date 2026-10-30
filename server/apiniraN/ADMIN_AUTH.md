# Administrator authentication · PHP 8.5.12 / LiteSpeed / cPanel

This source upgrade applies independently to the registry panel and canonical
my-sub Subscription Studio. Device-registration authentication, subscription
HMACs, client API tokens and stored subscriptions are unchanged. No deployment
or production data migration has been executed by the development tests.

## Hosting prerequisites

- HTTPS must be enabled and forced by the web server. PHP checks the server's
  native `HTTPS` or `SERVER_PORT=443`; it never trusts `X-Forwarded-*`. If TLS is
  terminated upstream, configure LiteSpeed's trusted TLS indication rather than
  adding application trust for arbitrary forwarded headers.
- PHP 8.5.12 with `openssl`, `iconv`, `session`, `hash`, `json`, `ctype`; registry
  also requires **PDO + pdo_sqlite**. A hosting list containing only MySQL/PDO
  MySQL does not prove SQLite support. Enable pdo_sqlite in cPanel PHP Selector
  or ask the provider. Do not silently switch databases. my-sub retains atomic
  JSON storage and requires no SQL extension. QR needs no GD, Imagick or XMLWriter.
- Writable private storage and PHP's private session directory. Keep the existing
  `NIRAN_REGISTRY_DB` and `NIRA_STORAGE_DIR` paths. Prefer paths outside public_html;
  deny public downloads of database, state, lock, WAL/SHM and backup files.
- Correct server time (30-second TOTP steps; accepted window is current ±1 step).

## External configuration (separate for each application)

| Setting | Registry | Subscription Studio |
|---|---|---|
| TOTP encryption key | `NIRAN_ADMIN_TOTP_KEY` | `NIRA_SUB_ADMIN_TOTP_KEY` |
| First setup token | `NIRAN_ADMIN_SETUP_TOKEN` | `NIRA_SETUP_TOKEN` |
| Session cookie | `niran_admin`, `/apiniraN/` | `nira_sub_admin`, `/admin/` |
| Remember cookie | `niran_registry_trust`, `/apiniraN/` | `nira_subscription_trust`, `/admin/` |
| Encryption AAD | `nira-registry-admin:v1` | `nira-subscription-admin:v1` |

Generate each encryption key independently with PHP
`base64_encode(random_bytes(32))` in a private terminal; do not print it to a
shared log, put it in PHP/Git, a URL, a public phpinfo page or this document.
Install it using the hosting provider's private environment configuration, or
an account-owned PHP bootstrap outside public_html that calls `putenv()`.
`$_SERVER`/`$_ENV` values from cPanel SetEnv are also supported. Environment
configuration must be protected like a password. The two apps must use different
keys. Source distribution contains no deployed key or real credential.

Missing/invalid keys block 2FA enrollment; existing encrypted 2FA cannot be
verified with a missing or different key. Password-only accounts continue to
work until 2FA is explicitly enabled. Preserve the old external key with the
private data backup. Key rotation requires a planned decrypt/re-encrypt process;
replacing the environment value alone will lock out authenticator verification.

Remove the setup token from hosting configuration after first setup. Existing
accounts cannot be overwritten using the setup flow. The old registry
`NIRAN_ADMIN_PASSWORD_HASH` is an initial import source only: once `admin_auth_v1`
is saved, the in-panel username/password becomes authoritative. Remove that
legacy environment hash after verifying the import. Existing registry username
defaults to `admin`; existing my-sub usernames and password hashes are retained.

## User flows and security properties

1. Enter username/password. Session ID and CSRF token rotate. With optional 2FA
   enabled, this creates only a five-minute pending session: it cannot read or
   mutate the admin API or private registry UI.
2. Enter a six-digit Google Authenticator code (RFC 6238 SHA-1, 30 seconds), or
   open the recovery-code alternative. The primary OTP is one text input with
   `inputmode=numeric`, `maxlength=6`, `autocomplete=one-time-code`; visual cells
   preserve native paste, Backspace and password-manager behavior. Server accepts
   only exactly six ASCII digits for TOTP; recovery codes have a separate strict
   hex format. No submitted code is evaluated or interpolated into SQL.
3. After final verification, session ID/CSRF rotate again. A checked Remember
   option issues a random selector + random validator. Only the validator hash
   is stored. Its Secure/HttpOnly/SameSite=Lax cookie lasts **15 days** from issue;
   rotation never extends the original deadline. A correct password is still
   required on every new login. The cookie bypasses only the second factor.
4. A remembered device rotates its validator on use. Reuse of a previous or
   invalid validator revokes that selector and demands 2FA. Concurrent use of an
   old token can revoke the device; reauthenticate with a fresh OTP/recovery code.
5. Security settings support username/password changes, local QR enrollment,
   confirmation before enabling, disabling/resetting 2FA, replacing recovery
   codes, and revoking one or all devices. Enrollment expires after ten minutes.
   Disable/reset or code replacement requires the current password plus an unused
   TOTP/recovery proof when 2FA is active. Changing credentials or 2FA state rotates
   the account generation and invalidates old sessions and all trusted devices.
   Device revocation also invalidates sessions completed through that device.

Every TOTP timestep can succeed only once, including enrollment and security
actions. Replay and recovery consumption happen inside the same JSON file lock
or SQLite `BEGIN IMMEDIATE` transaction as state persistence. Ten high-entropy
recovery codes are shown once; only hashes are stored. Password and OTP stages
have independent account-wide five-failure/60-second fixed lockouts, with peer IP
as an additional limit. New cookies, usernames or IPs do not reset the account
limit. IP changes no longer terminate a valid registry session.

PHP sessions use strict mode, cookies only, Secure/HttpOnly/SameSite=Strict and
CSRF for every POST, including password and OTP stages. A legacy session lacking
the new account generation is invalid. Remembered sessions are also checked
against device revocation and expiry on every authenticated request.

Google Password Manager may group accounts on the same origin regardless of form
IDs or brands. Distinct form names improve clarity but cannot enforce isolation.
Use separate hostnames (for example, a registry host and a subscription host) for
fully separate password-manager sites. No code claims otherwise.

## Dependencies and deployment

`admin-auth/composer.json` pins OTPHP **11.5.0** and BaconQrCode **3.1.1**;
`composer.lock` pins all transitive packages/commit references. The bundled
`vendor/` directory is deployable without Composer/root access on the host.
Composer plugins and scripts were disabled. OTPHP implements RFC 6238; Bacon
encodes the QR matrix. The renderer emits only integer SVG modules and a fixed
four-module quiet zone. No QR service, analytics, external font, script or image
request receives a secret. QR/manual enrollment values are shown only in the
current authenticated no-store response; they are not placed in URLs/logs.

Upstream sources: [OTPHP](https://github.com/Spomky-Labs/otphp/tree/11.5.0),
[BaconQrCode](https://github.com/Bacon/BaconQrCode/tree/v3.1.1).

Upload the app's full changed auth source plus matching `admin-auth/vendor` and
lock file together. For my-sub this directory is `shared/admin-auth/`; for the
registry it is `apiniraN/admin-auth/`. Its `.htaccess` denies direct HTTP access;
PHP includes still work. Keep `admin/security.php` for my-sub. Do **not** deploy
test routers, fixture tests, `build/`, source backups or temporary tooling into
public_html. Tests intentionally simulate HTTPS on loopback; those routers must
never run in production. Do not expose tests through the deployed web root.

## Migration, rollback and preservation

- Before deployment, privately back up existing runtime state (registry SQLite
  using SQLite's consistent backup operation, or a quiesced DB including WAL;
  my-sub `auth.state.php` and subscription JSON under exclusive locks), external
  encryption keys, and current sources. Development source backups intentionally
  contain **source files only** and are not backups of live user data.
- Migration is additive and lazy, guarded by `auth_version=1`: registry creates
  a single `admin_settings` key `admin_auth_v1` inside an immediate transaction;
  my-sub extends its existing guarded atomic auth JSON. No user subscription,
  installation table, identity, API secret or existing legacy hash is cleared.
  Newer unknown schema versions fail closed instead of being overwritten.
- Deploy all matching source/dependencies, check HTTPS and extensions, log in
  with the existing credential, inspect Security, then enroll/confirm and save
  recovery codes. Verify pending API denial and a second clean browser login
  before removing the old source backup. Sessions created by old code require
  fresh login. Do not test with real secrets in screenshots or console output.
- For rollback, put the panel in maintenance mode; restore the matching sources,
  private auth-state backup and key as a coherent checkpoint. **Never roll back
  to password-only sources while retaining a newly 2FA-enabled account**: old code
  would ignore 2FA. Prefer fixing forward or preserving the new auth gate. Do not
  delete SQLite/JSON, clear the account, reset subscriptions or bulk-remove old
  databases to recover access. Restoring auth alone must not overwrite later
  subscription/registry data; restore only the auth key/record under proper locks
  if a reviewed, app-specific recovery procedure is needed.

## Validation

`tests/admin_auth_test.php` exercises the shared engine with test state only.
`tests/panel_test.php` uses private temporary SQLite/session files and actual PHP
requests, including concurrent requests. `tests/admin_auth_browser_test.cjs`
starts a loopback PHP server plus real Chromium and drives both apps with
isolated JSON/SQLite/session fixtures. Set `PHP_BINARY`, `PHPRC` (with pdo_sqlite),
`PLAYWRIGHT_MODULE`, `BROWSER_EXECUTABLE` and `NIRA_TEST_MYSUB_ROOT` as appropriate.
Host deployment, actual LiteSpeed settings, external keys, phone scanning and
Google Password Manager site grouping require host/user verification.
