# Android motion and control follow-up

Same-version candidate after `449f1f88e581ae124f62d6b2f99410bf054f768f`.
Scope excludes Windows, backend/PHP, VPN configuration, signing and publication.

## Changes and evidence

- Dialog entrance: two completed paints for optical priming, then 220ms scale .94→1 and an initial 110ms material/content fade. An almost-zero visibility keeps premium geometry mounted. Reduced motion skips scale/fade; early dismissal cannot report `onShown`. Foreground content opacity is already handled by upstream; do not add a second whole-backdrop opacity.
- Control gesture ownership: upstream `GlassDragBuilder` uses raw pointer events, which do not compete with an ancestor Scrollable. Regression reproduced a list moving from40 to110 while dragging its glass trigger. Matching horizontal/vertical drag recognizers now claim that gesture; child taps and surrounding list scrolling remain functional. A generic pan recognizer is insufficient because its larger slop loses first.
- Whole-scroll stretch removed: keep bouncing scroll physics, but do not additionally deform the compositor and circular glass shapes with StretchingOverscrollIndicator. Row controls retain40x40 bounds, no own stretch/press scale, no downward-offset shadow, and a more balanced rim at the light-axis ends. No opaque replacement for the lens or header exclusion.
- Page release: critical damping, mass.5/stiffness300, shorter tail; drag-start motion threshold18. Intent thresholds32px/650pxs remain. Navigation tap animation240ms, retained pages,80%-visible input unlock and menu blocking remain unchanged. Test follows monotonic120Hz samples after an80% release, within.06px at400ms. This is a physics test, not measured device FPS.
- Premium backdrop magnification: optional `backdropZoom` defaults1; app selects1.035. Uniform45 is appended and written for live/capture shader paths. Sample deltas move toward the layer centre, preserving geometry/foreground and fading at the rim. Both continuous-blur and interleaved-frost sample paths receive the delta; GLES texture flipping only applies in sample coordinates. Copy/lerp/pinch/equality/hash/visibility retain the field.
- Up-to-date result: floating theme-aware rounded confirmation, check icon, three-second dismissal; settings update flow otherwise unchanged.

## References checked

- `sdegenaar/liquid_glass_widgets`, main tree7437a8acb56bae51d6969e3b9f51b257d461d047: GlassButton, GlassDragBuilder, stretch and premium optics.
- Flutter animations package `fade_scale_transition.dart`: fade/scale pattern adapted to a subtler .94 scale, with separate optical priming needed by this app.
- Current local Flutter PageScrollPhysics and StretchingOverscrollIndicator: release spring/tolerance and whole-content deformation.
- Context7 Flutter/package documentation lookup supplemented source inspection; source code determined gesture/optical behavior.

## Validation limits

Automated tests verify interaction, geometry bounds, settings transport and motion progress; they do not establish final optical appearance on the phone, low-end device performance, or120fps. The user subsequently authorized one launch and a brief smoke check, without unnecessary screenshots. Compare circles/material on-device before release; no new A55 measurement is claimed.

## Verified candidate

-183 Flutter tests passed again after resuming; analyzer reports no issues (`build/motion-polish-full-tests.log`, `build/motion-polish-analyze.log`).
- ARM64, ARM32, x86_64 and genuine universal release APKs built (`build/motion-polish-release-build.log`). All retain version1.2.1/code4023 and certificate SHA256 `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.
- ARM64 installed in place on Samsung A34; installed base SHA256 matches `AF12A93529C79A832F6061AA94397F7F37A9BDAE7A91DC865B9FBED537ED3BA6`. Last update2026-10-08 18:18:03; original first install2026-09-18 22:00:49 retained. No uninstall/reset.
- One authorized launch returned `Status: ok`; process16034 had no flutter/AndroidRuntime/libc error entries at the initial check. Phone keyguard was locked, so that is process-start evidence, not completed UI smoke-test evidence. `am start -W` wait3037ms is not a Flutter first-frame measurement.
- No GitHub publication, backend/PHP or Windows changes were made for this task.

## Brief device smoke check after user unlock

- Same PID16034; no second launch. Navigated to Settings, scrolled, opened General/Update interval, verified Cancel/Apply semantics, cancelled without saving, selected Servers (confirmed selected tab and header), then returned Home.
- First UI-automation dump timed out waiting for idle; compressed retry succeeded. Do not equate that timeout with an ANR.
- Final same-process log scan found0 matching Flutter exception/overflow, AndroidRuntime fatal, ANR or shader compilation errors. No screenshot, configuration change or manual connection toggle was performed. Removed the single temporary UI hierarchy file afterward.
- Android `gfxinfo` supplied only6 host-view frames, not the Flutter Surface's full raster stream; its percentile/jank figures are not a valid app FPS benchmark and are not reported as such. No new device frame-rate/optical approval claim.
