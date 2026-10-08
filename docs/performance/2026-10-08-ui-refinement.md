# Android UI refinement — same-version candidate

Scope: Android only; no Windows changes, PHP edits, engine replacement or publication. Version remains 1.2.1+23 (Android code 4023).

## Evidence and implementation

- An opaque hit-test Listener on the entire fixed Servers header prevents blank optical areas from reaching server rows; its child menu remains interactive. Regression checks tap and drag interception with both performance settings.
- AnimatedSize inside the Connection card follows content height over 240/200ms, respecting disabled animations. Tests verify intermediate heights when Restart Service appears and disappears.
- App and registration MaterialApp builders enforce TextScaler.noScaling. This intentionally disables Android font-size adaptation at the user's request; fixed scale is 1.0.
- Server-row pointer tracking cancels pressed scale/translation after Flutter touch slop, without replacing bouncing scroll physics or removing list-end elasticity.
- GeometryTransformTrackingLayer records the transform used in a real paint. Same-frame GlassMotionSync refreshes no longer schedule a duplicate trailing repaint; cached transform-only motion retains its post-frame fallback. Regression tests cover both paths.
- Only repeated server-row menu triggers select upstream GlassQuality.standard in Performance mode. They retain circular bounds, blur, translucency, hit handling and motion synchronization, but use a cheaper 2D rim instead of full premium refraction. Regular mode, open menu, header and Connect retain premium optics. This is an explicit performance/material tradeoff, not a guarantee of 120fps.
- Fingerprint choices match the bundled core revision 3115a981a8b6, including advanced hello presets. ALPN and cipher selectors retain imported/custom values without normalizing untouched fields. REALITY rejects unsafe; no networking or ECH resolver is reimplemented. Toasts and compact Selected badge are covered by widget tests.

## References

- Bundled-core fingerprints: https://github.com/patterniha/xray-core/blob/3115a981a8b6/transport/internet/tls/tls.go
- v2rayNG option conventions: https://github.com/2dust/v2rayNG/blob/master/V2rayNG/app/src/main/res/values/arrays.xml
- Flutter AnimatedSize: https://api.flutter.dev/flutter/widgets/AnimatedSize-class.html

## Registry read-only inspection

DeviceRegistrationManager retains the saved installation ID and first-seen timestamp on app updates. Authenticated API requests update version/build/last-seen on the existing row. Registration upsert also finds an existing Device Key before inserting, preserving original first-seen/created-at. Thus updates do not add new users. Reinstalling on the same device can also reuse the device record; a new installation ID alone does not imply a new user. PHP sources were inspected, not changed for this task. This is local-source evidence, not a live production-host audit.

## Verification boundary

Tests prove interaction, settings transport, font scale and repaint scheduling. No new physical-device FPS benchmark or final optical approval is claimed. In-place installation must preserve identity, signature and stored data; do not launch the app after installing this candidate.

## Verified candidate

- 202 Flutter tests passed; analyzer reported no issues. Native test task succeeded with 127 tests, zero failures/errors. Registry and panel PHP test scripts passed against isolated temporary databases.
- Read-only independent review found no Critical/Important issue within the refinements above.
- ARM64, ARM32, x86_64 and universal APKs built successfully. All report version 1.2.1/code 4023 and certificate SHA256 `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`; universal contains all three ABIs.
- ARM64 installed with adb install -r on Samsung A34. Installed base APK SHA256 matches `7A94A87F17707ECF703F57AEB5F073BA87966569C0D57602BBB2CA2B55860368`. Update time is 2026-10-08 23:30:48; original install time remains 2026-09-18 22:00:49. No uninstall, settings reset or app launch was performed.
- No GitHub publication, Windows changes or PHP edits were made in this refinement.
