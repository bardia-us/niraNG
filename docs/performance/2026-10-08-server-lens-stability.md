# Server lens motion synchronization

## Report and cause

User images show several lens bodies vertically displaced from their three-dot icons, clipped into half-circles at row bounds, with alternating dark/striped fragments. This is different from a layout aspect-ratio problem.

Premium optical uniforms use screen/compositor coordinates at paint time. Cached row layers can translate without repainting their optics. Upstream transform tracking discovers that translation during composition and schedules a post-frame repaint, so the first moving frame can sample an old geometry position. The app already uses GlassMotionSync for the horizontal pager, but ServersScreen had no corresponding vertical-scroll synchronization; its ScrollNotification handler was a no-op. Implicit row press scale/slide also moved cached optics independently of pager motion.

## Scoped correction

- Give the existing ReorderableListView a lifecycle-owned ScrollController and connect the existing GlassMotionSync renderer to it. Only attached optical nodes are dirtied; local geometry is reused and no per-scroll-pixel widget rebuild or extra blur layer is added.
- Drive the existing short row scale/translation from one animation, with the same optical synchronization during press/release. Performance mode still disables this row animation. No change to the circular control material, size, header overlap mask, menu or hit handling.
- Preserve version1.2.1+23, signing and app identity. Backend/PHP and Windows are outside this fix.

## Verification and user checks

- Regression coverage: actual ServersScreen wiring in both performance modes; cached optical paint matches current global position in the same frame through forward/reverse/fractional scroll steps. Existing rounded-header clipping and circular bounds tests remain.
- Tests do not execute the device's actual Impeller shader. Confirm the photographed artifact on the installed candidate; do not declare final pixel/FPS approval from widget tests.
- User checks: slowly scroll and stop mid-row; rapid up/down followed by a sudden stop; press/release and open/close several row menus; pass controls under and back out of the fixed header; compare light/dark and Performance on/off. Report which of these still produces clipping/offset/stripes, and whether it occurs during movement or remains after stopping.

## Candidate results

- Full Flutter suite: 186 passed (`build/server-lens-stability-tests.log`). Analyzer: no issues (`build/server-lens-stability-analyze.log`).
- Release build completed successfully: arm64-v8a, armeabi-v7a, x86_64 and universal. Metadata confirms `dev.nirang.client`, version 1.2.1, code 4023; the universal contains all three ABIs.
- ARM64 signing certificate SHA-256 remains `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.
- ARM64 APK SHA-256: `D8EBE0874F20CF4B9B8A57EAB9BB254866083516E55B189B5D914F9EE1763F46`.
- Installation completed on the existing Samsung A34 after USB transport recovered: `adb install -r` returned Success. Installed base.apk SHA-256 matches the ARM64 candidate above; package metadata confirms version 1.2.1/code 4023. First install remains 2026-09-18 22:00:49; update time is 2026-10-08 19:59:31 (device-reported times). No uninstall, data reset, app launch or GitHub publication was performed for this candidate. Final visual confirmation remains with the user's scroll/menu checks.
