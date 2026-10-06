# Glass performance checkpoint — 2026-10-07

## Scope

Preserve premium glass, blur, refraction, spring animations and controls.
No device-name hacks, renderer switch, CPU/GPU clock forcing, quality downgrade,
version bump, backend edit, device launch or GitHub publication.

## Confirmed unnecessary work and bounded fix

`GlassMotionSync` visited every descendant of attached retained pages on every
pager notification, even when a whole page was outside the viewport. Optical
nodes were invalidated unnecessarily; this is CPU-side work, not proof that
invisible pages were executing GPU shaders.

The shell now supplies a cheap visibility predicate derived from the current
fractional page offset (not the eagerly selected navigation index). Both
intersecting pages remain live, including the intermediate Servers page when
moving directly between Home and Settings. Hidden Offstage branches are skipped.
No widget-tree rebuild per pixel, detached screenshot or frozen material is used.

Regression tests exercise traversal, same-frame optical repaint, becoming
visible again, listener/predicate replacement and the actual retained AppShell.

## Backdrop sharing inspection

Servers already wraps the lazy list in `GlassBackdropGroup`, but the upstream
GlassMenu put an unconditional Opacity around its trigger. The group's render
pass safety check excludes that path even at opacity 1. A regression test on the
actual app trigger reproduced the excluded group.

Our glass-aware triggers now opt into material-channel fade instead of the
outer Opacity. MaterializeScope already fades glass through its shader visibility
and content separately; the combined content fade is preserved. Ordinary
upstream triggers retain their default opacity behavior. Enabled GlassButton
and ordinary row clips introduce no other outer save-layer barrier on this path.
Do not disable `useOwnLayer`: that would regress the previous missing
render-scope/black-placeholder fix. Grouping shares blur/frost; refraction remains
per surface. Real GPU capture is needed to measure savings on an Android driver.

Review caught a non-material regression from removing the outer opacity:
keyboard focus rings and hidden trigger semantics survived. Regression tests
reproduced both. Focus rings now consume material visibility via paint color
alpha (no save-layer); hidden triggers explicitly exclude their semantics and
restore them when the menu closes.

## Why not force maximum CPU/GPU usage?

High utilization is not the goal. A 120 Hz frame has about 8.33 ms available;
CPU UI work and GPU rendering must fit their frame budgets. Unnecessary
save-layers/backdrop reads can dominate despite a strong CPU. Sustained maximum
power can trigger thermal throttling. Optimize work and frame pacing, then
measure UI/raster/GPU times on a physical device in profile mode.

Primary references checked:

- https://github.com/sdegenaar/liquid_glass_widgets#performance-tips
- https://pub.dev/packages/liquid_glass_widgets/changelog
- https://docs.flutter.dev/perf/best-practices
- https://docs.flutter.dev/tools/devtools/performance
- https://developer.android.com/games/optimize/power
- https://developer.android.com/games/optimize/gameperformance

## Deferred / not verified

- Light-mode backdrop text remains too readable: fix blur later, as requested.
- A55 severe lag: no A55 controlled profile available; do not claim its root
  cause or a measured FPS improvement from widget tests.
- Device FPS, thermals and visual equality need a controlled physical-device
  comparison. Keep profiling tools separate from the release entrypoint.
- Widget tests check group eligibility above the trigger, not actual live
  shader-layer membership/GPU passes. They check optical repaint, not exact
  sampled shader coordinates through an interrupted viewport transform.

## Verification

- Final full Flutter suite: 166 passed (`build/glass-motion-full-tests.log`).
- Analyzer: no issues (`build/glass-motion-analyze.log`).
- Android release build is checked separately in `build/glass-motion-arm64-build.log`.
- Build tools report existing future-support warnings for Gradle 8.14.0,
  AGP 8.11.1 and Kotlin 2.2.20. Toolchain upgrades are not bundled into this fix.
- The connected app is not launched, installed or interacted with in this task.
  Published v1.2.0 artifacts, backend and version remain unchanged.

## Authorized follow-up: 1.2.1

The subsequent local performance APK was installed with an in-place update;
the user reports FPS looks good so far. This is feedback, not a measured A55 fix.

Light panels now use the same single continuous native Gaussian path as dark
panels (sigma 8, or 6 in performance mode), replacing interleaved sharp ghost
rows rather than stacking filters. Light tint, lens, rims and all small-control
optics remain unchanged. Dark settings produce the same values as before.

Only server-row menu triggers opt into circular 44x44 controls with their own
stretch and press scaling disabled. The row's existing uniform scale feedback,
header control, elastic Connect button and menu spring/morph remain intact.

Version is 1.2.1+23, with bundled bilingual offline notes. Regression tests first
failed on absent light blur and the old row-trigger geometry, then passed after
the changes. Release build and in-place installation are verified separately;
no publication, backend edit, data reset or automatic app launch is authorized
in this follow-up. Light-mode visual approval and device FPS remain phone-side
checks, not conclusions from widget tests.

## Same-version circular-row correction

The user still saw flattened row lenses. The previous test asserted 44x44
constructor values inside a roomy Center, not the app's actual compact ListTile.
With the real theme, trailing layout capped the height at 40 while the width
remained 44. The corrected test reproduced the rendered 44x40 lens in both
performance modes before the fix.

Only row triggers now fit a square within their incoming constraints, capped
at 44: the existing compact row produces 40x40, with no change to tile height,
glass optics, header control or menu morph. Rendered dimensions and menu actions
are tested with the actual compact theme in light/dark and both performance modes.
The full suite passes 172 tests and the analyzer reports no issues. The version
remains 1.2.1+23 / installation code 4023. This is a local checkpoint pending
real-device feedback and separate publication approval, not a new public release.
