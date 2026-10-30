# Third-party notices

## sing-box

- Project: <https://github.com/SagerNet/sing-box>
- Version: `1.14.4`, commit `c005f35300ce76427dc285481ec5695f5b179cd2`
- License: GNU General Public License v3.0 or later (GPL-3.0-or-later)
- Bundled artifact and hashes: `android/app/libs/libbox.aar` and `libbox-build.json`
- Reproducible build: `tool/build_singbox.ps1`
- Local patches: `tool/build_singbox_namespace.py` isolates gomobile Java/JNI
  as `nirasbgo`; `tool/native/singbox/nirang_probe.go` adds an independent
  `CommandServer.StartProbe` entry point without changing the active diagnostic
  configuration snapshot or opening a command listener. Both patch hashes are
  recorded in the build manifest. The pinned core parser, DNS, routing and TLS
  validation are retained.

## AndroidLibXrayLite

- Project: <https://github.com/patterniha/AndroidLibXrayLite>
- Pinned release: `v26.8.28`
- License: GNU Lesser General Public License v3.0 (LGPL-3.0)
- Bundled artifact: `android/app/libs/libv2ray.aar`
- Original release SHA-256: `F52AE053281B9C3E5F01CAB1C92B6AE7D750B05A12BF39B6B3649BF931A570DA`
- Local telemetry AAR SHA-256: `821e68750c7c903ab79d0036af7a433f5926e776f02ca1d9df33b2e21dcb234a`
- Local changes: cumulative selected-input statistics and a compatibility fix
  preserving TUN UDP packet metadata when input statistics are enabled. The
  pinned core version, original assets and TLS behavior are retained.
- Rebuild inputs, modified source and verification: `tool/build_xray.ps1`,
  `tool/native/xray/`, and `android/app/libs/libv2ray-build.json`. Original Go
  `1.26.7` is retained. See `android/app/libs/README.md` for the exact source
  provenance and local pinned-core replacement.
- Corresponding source: <https://github.com/patterniha/AndroidLibXrayLite/tree/v26.8.28>

The AAR packages native Go/JNI code. Before distributing niraNG, include the
LGPL-3.0 license text and preserve an appropriate corresponding-source offer or
link for the exact artifact.

## Xray-core

- Project: <https://github.com/patterniha/xray-core>
- Pinned commit: `3115a981a8b6` (`v26.8.28`)
- License: Mozilla Public License 2.0 (MPL-2.0)
- Source used by the pinned wrapper is declared in the wrapper’s `go.mod`.

## Liquid Glass Widgets

- Project: <https://github.com/sdegenaar/liquid_glass_widgets>
- Vendored release: `1.9.0`, with local compatibility patches.
- Copyright: 2024–2026 Sebastian Degenaar.
- License: MIT, retained at `packages/liquid_glass_widgets/LICENSE`.
- Source and patch notes: `packages/liquid_glass_widgets/` and its `PATCHES.md`.

## Flutter and AndroidX dependencies

Flutter, Dart packages and AndroidX dependencies retain their respective
licenses. Release builds should generate and ship a complete dependency license
inventory as part of the store/distribution process.

## Psiphon identification artwork

- Psiphon Inc.: <https://psiphon.ca/>.
- Modern official website apple-touch icon, used unchanged to identify the Psiphon connection option.
- Original source URLs, hashes and retrieval details: `assets/branding/psiphon-source.json` and `engine-branding-sources.md`.
- Psiphon names and marks belong to their respective owner; inclusion does not imply endorsement.

## Twemoji flag graphics

- Project: <https://github.com/jdecked/twemoji>
- Copyright: Twitter, Inc. and other contributors
- License: Creative Commons Attribution 4.0 International (CC-BY 4.0)
- Bundled assets: `assets/flags/twemoji/`

The full graphics license is included as
`assets/flags/twemoji/LICENSE-GRAPHICS`.
