# Android sing-box session

Pinned core: **1.14.4**, official source commit
`c005f35300ce76427dc285481ec5695f5b179cd2`:
<https://github.com/SagerNet/sing-box/tree/c005f35300ce76427dc285481ec5695f5b179cd2>.
License: GPL-3.0-or-later. The exact upstream license is at
<https://github.com/SagerNet/sing-box/blob/c005f35300ce76427dc285481ec5695f5b179cd2/LICENSE>.
The Go Authors' BSD-3-Clause license also applies to gomobile v0.1.12;
the source namespace patch is `tool/build_singbox_namespace.py`.

## Artifact provenance

`tool/build_singbox.ps1` builds actual Android `experimental/libbox` from the
verified official source. It keeps Go checksum-database verification enabled and
verifies downloaded module contents before applying the local gomobile patch.
The patch relocates only the Java/JNI reference tracker to `nirasbgo` so the
existing Xray `go.Seq` runtime remains independent. Do not delete duplicate Java
classes from either AAR as a substitute for this relocation.

- Go: 1.25.5; official Windows archive SHA256:
  `ae756cce1cb80c819b4fe01b0353807178f532211b47f72d7fa77949de054ebb`.
- gomobile: `github.com/sagernet/gomobile@v0.1.12`.
- NDK: 28.2.13676358; Android API 24; JDK 21.0.6 used for Java bindings.
- Build tags: `with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_low_memory`.
- Optional Naive/OpenConnect/OpenVPN/Tailscale endpoint registrations are not enabled.
- No upstream `tlssha1=1` compatibility override is passed to the Go linker.
- AAR: `android/app/libs/libbox.aar`, 62,361,894 bytes, SHA256:
  `0cd7a2b838b0fc273e1bfe1fc1911fdf0afed49d4ef357b8f4d5563e57b316a3`.
- Machine-readable provenance: `android/app/libs/libbox-build.json`.

All three required ABIs are present. Their `libbox.so` SHA256 values are:

| ABI | SHA256 |
| --- | --- |
| arm64-v8a | `0ba2e955ef95119c0df1fb054894a9ed621618bdff2422fa397058b8b0853d10` |
| armeabi-v7a | `5fed911c6c538719bd5015fa00166e9ef9dfe4e9db207799f8d96e5efbb030bc` |
| x86_64 | `d0d54c9096392811e48e3555da340b594b0d619e7b76160f87092e7cffb90709` |

`tool/build_singbox_verify.py` verifies ABI machine identifiers, independent
Java/JNI namespaces and absence of duplicate classes with the existing Xray AAR.
The arm64 ELF load segments were also checked for 16 KiB alignment.

## Service contract

`NativeSingBox.validate(originalJson)` performs Android capability checks, confirms
the linked native version, then calls actual `Libbox.checkConfig`.
`start(vpnService, originalJson, -1)` starts the actual native service. A prebuilt
TUN descriptor is rejected. `OpenTun` builds Android's interface from libbox's
own addresses, DNS options, exact computed routes and package filters. Exactly
one explicit TUN with `address` and `auto_route=true` is required. Success also
requires that native startup actually called OpenTun and obtained a descriptor.

JSON is passed unchanged. Global app DNS, routing and per-app preferences are
not applied. The app's established own-package exclusion is retained: JSON
includes exclude niraNG itself; an own-package-only include fails instead of
expanding to all apps. Unknown or absent package names fail Android setup.

`route.auto_detect_interface=true` is required. Bind-interface/address overrides,
alternate protect sockets and VPN-upstream overrides are rejected because those
options bypass libbox's protected-socket callback. The callback checks the actual
boolean result from `VpnService.protect`. Every callback checks session generation.
Stop invalidates in-flight startup before closing core, network callbacks and TUN.

The adapter monitors the physical default network using Android's supported API
for each version. Android 28-30 requires `CHANGE_NETWORK_STATE` for the matching
physical-network request; Android 31+ uses the best-matching callback. Local DNS
uses the selected physical `Network`, never process-wide VPN DNS resolution.

`counters()` reports actual libbox traffic totals and an explicit availability
flag. The libbox command/status socket is Unix-only inside `noBackupFilesDir`,
with an ephemeral secret; no TCP control endpoint is exposed. Config snapshots
and crash output remain inside private excluded-from-backup storage. Native
exceptions containing config data are not returned to UI or logs.

No HTTP inbound is injected. Existing app IP-checking must report unavailable
unless the original JSON already provides its compatible authenticated-policy
checked loopback HTTP/mixed listener. Wi-Fi identity rules, privileged services,
filesystem inputs, executable paths, debug/control APIs and unsupported TUN
platform features are rejected before native validation rather than ignored.

## Verification evidence and limits

- 16 JUnit policy/lifecycle/socket-protection/package-filter tests pass; each new
  behavior was observed failing before implementation.
- All Kotlin adapter files compile against the actual generated `classes.jar`
  and Android 36 API jar (JVM 17 target). Only the platform `allNetworks`
  deprecation warning remains.
- The same pinned source/tags were built as a Windows host CLI at
  `build/native/sing-box-host.exe`. It accepts a real valid TUN config and rejects
  an unknown outbound type (exit 0 versus 1).
- Actual schema exported by that core:
  `build/native/libbox-binding/sing-box-1.14.4.schema.json`, SHA256
  `32f7598b8428276c5d358fd385942fa54dbe099055974120912b93626accbfd9`.
  Runtime callers can use `NativeSingBox.schema()` for the packaged schema.
- Extracted actual binding jar: `build/native/libbox-binding/classes.jar`.
- Host unit tests and compilation do not establish live Android TUN traffic,
  DNS behavior, reconnection or network handover. Those require the authorized
  device verification coordinated by the root service task.
- No GEO databases or rule-set downloads were enabled or fetched by the adapter.
  A supplied remote rule-set remains the author's explicit original core option.
