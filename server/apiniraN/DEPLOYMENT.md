# Device Registry deployment

Deploy `api.php`, `index.php`, and `registry.php` together under `/apiniraN/`
with PHP 7.4 or newer, PDO SQLite, cURL, and HTTPS. The backend intentionally
avoids PHP 8-only syntax for compatibility with common shared hosting.
On the first visit to `index.php`, the panel asks you to create an administrator
password. Only its `password_hash()` result is stored in the registry database;
the plaintext password is never written to disk. Later visits use that password
for normal session login.

Optional server-side environment variables:

- `NIRAN_REGISTRY_DB`: an absolute SQLite path outside the public web root.
- `NIRAN_ADMIN_PASSWORD_HASH`: an optional `password_hash()` value that
  overrides the password stored by first-time setup. Never store the plaintext
  password or its hash in this repository.
- `NIRAN_ADMIN_TIMEZONE`: timezone used to display First Seen and Last Seen;
  defaults to `Asia/Tehran`.
- `NIRANG_ANDROID_SUBSCRIPTION_UPSTREAM`: private HTTPS subscription endpoint
  served only to allowed Android/niraNG devices.
- `NIRAN_WINDOWS_SUBSCRIPTION_UPSTREAM`: private HTTPS subscription endpoint
  served only to allowed Windows/niraN devices.
- `NIRANG_SUBSCRIPTION_UPSTREAM`: optional legacy fallback if a
  platform-specific variable is absent. Prefer the two variables above.

All upstream URLs are server-only secrets. Never commit them or embed them in
an APK or Windows executable.

The web server user needs read/write access only to the database directory.
Keep HTTPS enabled for both endpoints; the client only posts to `api.php`.

The shared registry migration is additive and preserves existing Windows and
Android registrations and the administrator password. Minimum controllable
versions default to Android `1.1.1` and Windows `0.3.1`; both can be changed
independently in the authenticated panel.

Android schema 4 stores a one-way SHA-256 device key derived on-device from the
app-scoped ANDROID_ID, package name, and a domain-separation label. The raw
ANDROID_ID is never transmitted or stored. Installation IDs remain visible for
debugging, while the panel displays only a shortened device key. A new
installation ID with an already-blocked device key remains blocked and is
marked as a reinstall attempt.

The registry keeps one visible installation row per device key. On Clear Data
or reinstall, the current installation ID and Last Seen value replace the old
ones on that row while the original First Seen value and device-key Block state
are preserved. During migration, existing duplicate rows sharing a device key
are merged automatically before a partial unique index is created.

Versions through niraNG 1.1.0 used a direct subscription URL and did not possess
the schema-4 access token. They are registered as Outdated/Uncontrollable and
must not be presented as fully blockable. Before deploying 1.1.1, rotate or
disable the old direct subscription endpoint and configure the replacement only
as `NIRANG_SUBSCRIPTION_UPSTREAM`; otherwise an old APK that already knows the
old URL can bypass the registry outside this API.

niraN 0.3.1 uses schema 5 and sends a one-way SHA-256 device key derived
on-device from Windows `SystemIdentification.GetSystemIdForPublisher()`. The raw
system identifier is used only in memory and is never sent or stored. The
current unpackaged Win32 build does not have a package publisher identity, so
Windows supplies its documented unpackaged-app system identifier; niraN applies
an app/platform domain separator before hashing. No MAC address, serial number,
IMEI, files, or hidden hardware fingerprint is collected.

niraN 0.3.0 and older embedded the direct subscription endpoint and did not
enforce registry responses before Connect/Refresh. They are therefore shown as
Outdated/Uncontrollable. Rotate or disable that old upstream endpoint when
deploying 0.3.1, then configure its replacement only as
`NIRAN_WINDOWS_SUBSCRIPTION_UPSTREAM`.

The bearer token is random and only its SHA-256 hash is stored. Every status and
subscription request binds the token to both installation ID and device key,
then checks the current server-side block and minimum-version policy before any
subscription bytes are fetched. A modified client can still spoof client-side
claims; stronger binary/device attestation would require a separately designed
service such as Play Integrity and is not implied by this registry.

Run the backend regression test on the deployment host with:

```sh
php tests/registry_test.php
```
