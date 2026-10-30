# Bundled Xray library

`libv2ray.aar` is the local telemetry rebuild of the bundled `v26.8.28`
AndroidLibXrayLite release. It keeps the original Xray base, Go patch version,
compiled dependency versions/checksums, public API, and all three geo assets.

- SHA-256: `821E68750C7C903AB79D0036AF7A433F5926E776F02CA1D9DF33B2E21DCB234A`
- Android ABIs: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- Xray base: <https://github.com/patterniha/xray-core/tree/3115a981a8b6>
- Go runtime/compiler: `go1.26.7`, matching the original AAR
- Original AAR SHA-256: `F52AE053281B9C3E5F01CAB1C92B6AE7D750B05A12BF39B6B3649BF931A570DA`
- Original release: <https://github.com/patterniha/AndroidLibXrayLite/releases/tag/v26.8.28>

The wrapper rebuild base is commit
[`5bad0b55f2d002ace13657db11937bddcf48bc3b`](https://github.com/patterniha/AndroidLibXrayLite/tree/5bad0b55f2d002ace13657db11937bddcf48bc3b).
The original binary records its wrapper as a local `(devel)` replacement and
does not embed its VCS commit. This selected August 28 source snapshot matches
the original module graph and public API; its wrapper commit is not claimed to
be proven by the original binary. The original Xray replacement module does
explicitly record `3115a981a8b6` and its verified module checksum.

Local changes are limited to:

- Two controller methods returning cumulative selected-inbound byte counters as
  JSON, including a final snapshot after closing the core. They expose no socket
  or remote control API and do not reset counters on reads.
- A TUN UDP counter wrapper that preserves packet destination/source metadata.
  The old plain connection wrapper hid `ReadMultiBuffer`/`WriteMultiBuffer`
  whenever inbound statistics were enabled. TCP behavior stays unchanged.

The pinned core is copied from the checksum-verified module cache and all 1,036
files are checked before applying the declared one-file Go overlay. This local
replacement appears honestly as `(devel)` in build information. The base source
manifest, base/overlay hashes, complete per-ABI dependency comparison, toolchain
checksum and artifact hash are recorded in `libv2ray-build.json` and
`build/native/xray-pinned/`. The original AAR is retained there as
`libv2ray-original-v26.8.28.aar`. No core or TLS behavior upgrade is included.

Rebuild with `tool/build_xray.ps1`; use `-Bundle` only to copy a fully verified
result into this directory. It requires the verified Go1.26.7 toolchain module
in the workspace cache and preserves original assets. Native tests cover known
bytes through chained outbounds, repeated cumulative reads, reconnect, final
close counters, unavailable/invalid counters, and TUN UDP packet metadata and
partial writes. Both 64-bit libraries retain 16 KiB ELF load alignment; the
32-bit libraries retain their original 4 KiB alignment.

This version is required for FinalMask's ordered `lengths` and `delays`
runtime fields. See the repository root `THIRD_PARTY_NOTICES.md` for licenses.
