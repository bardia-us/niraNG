# niraNG API deployment notes

Upload `api.php`, `registry.php`, and `index.php` together. The SQLite migration is
performed automatically and adds expiring access-token metadata, replay nonces,
and rate-limit buckets without removing existing device or block records.

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
