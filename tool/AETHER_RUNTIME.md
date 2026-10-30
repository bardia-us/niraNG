# Aether Android runtime

Source: `https://github.com/patterniha/Aether`, v2.4.0,
commit `d58f9d568083129ce2c767c85054021eb3ee6a38`. This is the exact submodule
revision used by PattNG's `my-releases` branch when inspected on 2026-10-29.
The original executable is **not** packaged: its common HTTPS configuration
unconditionally disabled server authentication for account registration and ECH.

`aether-https-peer.patch` enables BoringSSL peer-chain verification after applying
the TLS fingerprint and explicitly enables hostname verification. It has no
insecure fallback. MASQUE gateway authentication additionally retains the three
upstream SHA256 SPKI pins and is forced on with `--tls-verify` and the controlled
environment. No API host/address/SNI or TLS bypass is accepted from a profile.

The runtime exports Android's platform TrustManager accepted issuers to a private
PEM bundle for `SSL_CERT_FILE`. This avoids relying on Android's legacy hashed CA
filenames matching BoringSSL's directory lookup format. User profiles cannot set
the trust bundle, environment, working directory or executable paths.

## Build and provenance

All build inputs and compiler caches live under ignored `build/aether-*`.
Prerequisites on this Windows host: local Rust 1.99.1 with rustfmt and the
`aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` targets;
NDK 28.2.13676358; CMake/Ninja 3.22.1; libclang 18.1.1; VS2022 for host tests;
NASM 2.16.03 for host BoringSSL tests. Paths are explicit in the build scripts.

1. Clone the pinned Aether source into `build/aether-upstream/Aether`.
2. Apply `tool/aether-https-peer.patch` (the build script also applies/checks it).
3. Download the three official v2.4.0 Android archives named in
   `aether-artifacts.lock.json` into `build/aether-upstream`.
4. Run `python tool/build_aether_artifacts.py`. It verifies published archive
   SHA256 values, ELF ABI and embedded clean Psiphon Git revision, stages only
   the separate Psiphon executables, and keeps upstream license notices.
   It verifies the public bootstrap list's RSA PKCS#1/SHA256 signature and key
   digest before staging plain seed entries. No APK is downloaded or extracted.
5. Run `tool/build_aether_native_tests.ps1` and `tool/build_aether_tests.ps1`.
6. Run `tool/build_aether.ps1 -Stage`. Native staging checks exact source pin,
   security patch and native test evidence, verifies no shared C++ runtime is
   needed, and writes `assets/aether-runtime.json` with final ABI hashes.

Psiphon source is `https://github.com/CluvexStudio/psiphon-tunnel-core` at
`83aa73b9b982e7421e00117f5b0c5aceb5dda452`, which both upstream build scripts and
the official binaries' Go build metadata identify. Aether starts that executable
with `AETHER_PSIPHON_BIN`; adding a Psiphon JSON property is not a native runtime.
Tor and lyrebird modes are not exposed by this integration.

Gradle must preserve `libaether_nira.so` and `libpsiphon_nira.so` through its strip
task (`keepDebugSymbols`) so packaging cannot invalidate their integrity hashes.
The binaries are already release-stripped. Missing/incompatible artifacts or a
missing security manifest cause validation to fail before any registration.

## Session boundary

`AetherSession(context, protectedUpstreamPort=0, socksPort=10819,
psiphonPort=10821, onProgress={})` exposes `validate`, `prepare`, `scan`,
`start(VpnService, config, tunFd)`, `stop`, `isRunning` and `outputSocksPort`.
The service owns TUN and the Xray local-SOCKS adapter. Keep the existing service
PerAppPolicy exclusion of the application's own UID. An optional nonzero direct
SOCKS upstream must support UDP ASSOCIATE and protected network egress.

`prepare(config, upstreamHttpPort)` may run before stopping an existing VPN; its
HTTP proxy override is for secure registration only. Registration is staged in
private no-backup storage; failed/cancelled registration retains old identities.
Valid retained identities skip repeated registration. MASQUE, WG and gool inner
WG have independent files. Runtime native renewal also uses the patched verifier.

`scan(config)` starts a bounded temporary local proxy, probes real verified HTTPS
traffic, and keeps the proxy until its caller stops it in `finally`. It ignores
the saved endpoint for that run. Session readiness requires end-to-end HTTPS
through the output SOCKS port; bare listener or handshake readiness is insufficient.
WARP-only paths additionally require `warp=on` in Cloudflare's authenticated trace.

Progress values are closed app strings: `registering`, `finding_endpoint`, `ready`.
Native output is drained without logging credential/device/endpoint details.
Stop invalidates generation ownership and terminates marked native descendants,
including Psiphon. No shell is used for runtime process arguments.

Typed keys: mode, psiphon, psiphonMode, psiphonRegion, scan, carrier, ipFamily,
endpoint, keepalive, dns, startupTimeoutSeconds. Exact values/ranges live in
`AetherOptions.kt`; unknown keys fail. No MTU flag is exposed because the pinned
upstream CLI has no such option. Android 10/API29 is required for this runtime;
the application's minimum SDK can remain unchanged.

## Verification boundaries

Native targeted regressions prove peer verification, rejection of an untrusted
API server before request data, and rejection of a trusted wrong-name server
with a trust-only success control. They do not claim the entire upstream test
suite passes: existing upstream HTTPS fixture tests deliberately used untrusted
local self-signed peers. Host policy tests cover typed options, private-identity
rollback/deduplication, generation cancellation, CA bundle and actual process ABI.

Host compilation and ELF inspection do not prove a working device tunnel. Device
network traffic, switch/cancel/reconnect and bootstrap behavior require a separate
authorized live check. Official Psiphon x86_64 uses 4KiB ELF LOAD alignment;
the ARM binaries use 64KiB, and locally built Aether uses 16KiB. This distinction
must be retained in release verification until x86_64 Psiphon is rebuilt.
