# Android ECH import

The bundled library remains AndroidLibXrayLite `v26.8.28`, SHA-256
`F52AE053281B9C3E5F01CAB1C92B6AE7D750B05A12BF39B6B3649BF931A570DA`.
The bundled ARM64 library's Go build metadata identifies Xray
`v1.260327.1-0.20260728075948-5ca6f4b7d4dc` (26.7.28); the older
`3115a981a8b6` claim in the library README does not describe those actual bytes.
The existing core accepts `tlsSettings.echConfigList` as:

- A fixed Base64 ECHConfigList, preserving `+`, `/` and `=` padding.
- A DNS resolver URI, such as `udp://1.1.1.1`.
- A lookup domain plus resolver URI, such as
  `cloudflare-ech.com+udp://1.1.1.1`.
- An `h2c://` DNS resolver URI routed through a TLS helper outbound, such as
  `h2c://1.1.1.1/dns-query` with `tlsSettings.echSockopt.dialerProxy`.

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
FinalMask JSON, ALPN, ECH config list and ECH outbound JSON. The ECH outbound is
one whole auxiliary Xray outbound. The builder appends its parsed object after
the other outbounds and links the main outbound's `tlsSettings.echSockopt.dialerProxy`
to its tag, matching PattNG's single-profile behavior. The GUI-only `echOutbound`
field is not emitted inside raw Xray TLS settings. The helper's own TLS settings,
including `fromMitM` certificate/ALPN values, remain as entered.

Edits use the existing encrypted cache mechanism and survive an ordinary app
restart. ECH outbound JSON is validated but its editor whitespace and indentation
are retained in storage; parsing for Xray output does not rewrite the stored text.
Source profile credentials are not copied into the override file. A helper may
itself contain user-supplied credentials, so its JSON must never be logged.
Edits apply on the next connection or service restart; the editor does not
interrupt the current tunnel.

A successful subscription refresh is authoritative: it restores the freshly
parsed source profiles and discards all manual profile edits, including ECH,
fingerprint, SNI, ALPN, ciphers and FinalMask. Fetch, parse and cache-commit failures
preserve the prior snapshot and edits. The source cache and override envelope
carry a subscription revision so a stale override file cannot reapply after a
successful refresh and app restart. New edits attach to the current revision;
legacy files without a revision continue to load until that first successful
refresh. A shared commit generation under the existing repository lock also
invalidates already-loaded instances after successful cache or override writes:
the long-lived bridge reloads before its next read/write when a worker refreshed
the subscription, so a later ping or reorder cannot persist old edited profiles.
Failed writes do not publish a new generation. Ordinary reads need only the
generation comparison, without reading/decrypting files again.
No core upgrade or speculative connection behavior change is included.

## Verification scope

`XrayEchConfigTest` exercises parser-to-generated-JSON behavior: both aliases,
raw/escaped plus, fixed Base64 padding, VMess JSON, coexistence with TLS options,
empty/absent ECH and Reality/plaintext exclusion. `ServerProfileSettingsTest` and
`ServerProfileOverridesTest` cover metadata, eligibility, validation and override
round trips. `android_server_profile_test.dart` covers populated editor fields,
real controller/channel save payload, reopening with updated native metadata,
Reality restrictions, invalid JSON and native rejection.

`SubscriptionRepositoryRefreshTest` exercises successful authoritative refresh,
restart, legacy migration, stale override invalidation, and fetch/parse/persist
failure ordering using real repository logic with isolated file/network I/O.
It also covers the bridge/worker two-instance case: stale selected-server reads,
ping/reorder revival, propagation of new edits, and no invalidation on failed writes.
`XrayEchOutboundPolicyTest` checks the public PattNG-style h2c helper and its
unchanged TLS fields across VPN, local proxy, probe and fallback builders, plus
import and fail-closed validation. These are generated-output checks, not a TLS
handshake test. The user reported that the actual ECH configuration is currently
down and requested no live connection test; the user will test it later.
No DNS reply, certificate validation, Android ECH handshake or connection-success
claim is part of this verification.

## Primary sources

- [Current upstream TLS documentation](https://github.com/XTLS/Xray-docs-next/blob/main/docs/en/config/transports/tls.md)
- [Actual core ECH parser and h2c resolver](https://github.com/XTLS/Xray-core/blob/5ca6f4b7d4dc/transport/internet/tls/ech.go)
- [Actual TLS config and ApplyECH](https://github.com/XTLS/Xray-core/blob/5ca6f4b7d4dc/transport/internet/tls/config.go)
- [Actual uTLS and WebSocket ECH handling](https://github.com/XTLS/Xray-core/blob/5ca6f4b7d4dc/transport/internet/tls/tls.go)
- [PattNG ECH outbound serialization](https://github.com/patterniha/PattNG/blob/my-releases/V2rayNG/app/src/main/java/com/v2ray/ang/core/EchOutbound.kt)
- [v2rayNG share-link ech mapping](https://github.com/2dust/v2rayNG/blob/master/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt)

PattNG's helper serialization and the actual core's ECH resolver source were
checked on 2026-10-21. Runtime capability evidence uses the bundled artifact's
metadata and matching source, not an assumption that it matches current main.
