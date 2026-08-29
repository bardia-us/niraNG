# Device Registry deployment

Deploy `api.php` and `index.php` under `/apiniraN/` with PHP 7.4 or newer and
PDO SQLite. The backend intentionally avoids PHP 8-only syntax for compatibility
with common shared-hosting environments.
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

The web server user needs read/write access only to the database directory.
Keep HTTPS enabled for both endpoints; the client only posts to `api.php`.

The API accepts the existing Windows schema versions 1 and 2 plus Android
schema version 3. Deploy `api.php` and `index.php` together: both perform the
same additive SQLite migration for platform, manufacturer, model, OS and app
columns. Existing Windows registrations and administrator credentials are
preserved. Android records contain only the consent-screen fields documented in
the niraNG client; no hardware identifier is accepted or stored.
