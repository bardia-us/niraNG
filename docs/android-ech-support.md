# Android ECH import

The bundled library remains AndroidLibXrayLite `v26.8.28`, with the pinned
Xray source `patterniha/xray-core@3115a981a8b6`. No core update is required for
these import changes. The current upstream documentation and this pinned source
both accept client `tlsSettings.echConfigList` as:

- A fixed Base64 ECHConfigList, preserving `+`, `/` and `=` padding.
- A DNS resolver URI, such as `udp://1.1.1.1`.
- A lookup domain plus resolver URI, such as
  `cloudflare-ech.com+udp://1.1.1.1`.

Share links accept `ech` (the v2rayNG convention) and `echConfigList`.
VMess JSON accepts either key as well. A nonempty `echConfigList` takes precedence
when both keys exist. URI percent decoding preserves a literal unescaped `+`;
it does not reinterpret that character as a space. The value is forwarded
without resolving DNS, caching ECH configs or making a handshake in app code.

The field is emitted only for TLS. Reality and plaintext profiles do not receive
it. Existing fingerprint, ALPN and cipher-suite fields retain their values. The
pinned core's TLS config calls `ApplyECH`; its uTLS `copyConfig` carries
`EncryptedClientHelloConfigList` through to `UClient`, and its WebSocket TLS
handshake has an explicit ECH path. The app does not replace the fingerprint.

Profiles without ECH keep the previous generated TLS JSON. An empty ECH value
does not emit `echConfigList`. Fixed config validity, DNS TTL, lookup failure,
certificate checks and the actual handshake remain the core's responsibility.

The per-server editor exposes SNI/fingerprint and, for TLS, cipher suites,
FinalMask JSON and ALPN. Edits are stored separately using the existing encrypted
cache mechanism and reapplied for the same profile ID on reload/refresh. It does
not copy credentials into the override file. Edits apply on the next connection
or service restart; the editor does not interrupt the current tunnel.

## Verification scope

`XrayEchConfigTest` exercises parser-to-generated-JSON behavior: both aliases,
raw/escaped plus, fixed Base64 padding, VMess JSON, coexistence with TLS options,
empty/absent ECH and Reality/plaintext exclusion. `ServerProfileSettingsTest` and
`ServerProfileOverridesTest` cover metadata, eligibility, validation and override
round trips. `android_server_profile_test.dart` covers populated editor fields,
real controller/channel save payload, reopening with updated native metadata,
Reality restrictions, invalid JSON and native rejection.

These are JVM and Flutter tests. No Android device handshake, live DNS/ECH lookup,
APK installation or connection-success claim is part of this verification.

## Primary sources

- [Current upstream TLS documentation](https://github.com/XTLS/Xray-docs-next/blob/main/docs/en/config/transports/tls.md)
- [Pinned core ECH parser and resolver](https://github.com/patterniha/xray-core/blob/3115a981a8b6/transport/internet/tls/ech.go)
- [Pinned TLS config and ApplyECH](https://github.com/patterniha/xray-core/blob/3115a981a8b6/transport/internet/tls/config.go)
- [Pinned uTLS and WebSocket ECH handling](https://github.com/patterniha/xray-core/blob/3115a981a8b6/transport/internet/tls/tls.go)
- [v2rayNG share-link ech mapping](https://github.com/2dust/v2rayNG/blob/master/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt)

Sources were checked on 2026-10-06. Runtime compatibility is based on the pinned
source above, not on assuming the bundled library matches the current main branch.
