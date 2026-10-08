# Home optical motion and connection layout follow-up

Same-version Android candidate: 1.2.1+23 / versionCode 4023. No Windows, PHP, VPN-core or publication change.

- Home previously synchronized only pager motion through AppShell. Its own vertical scroll depended on post-composition transform fallback. A retained ScrollController now drives GlassMotionSync for Home optics in the current paint. Connection-card SizeChangedLayoutNotifier notifications also invalidate only optical paint when the card moves the usage panel; they never call setState or request relayout from layout callbacks.
- Animating the old outer card clip did not interpolate the positions of children inside it. Restart now uses SizeTransition plus FadeTransition within its real layout, 360ms in / 300ms out, easeInOutCubic. Reduced-motion preferences bypass this duration. Following content and next section move with the occupied extent.
- AsyncOperationGuard keeps per-command single-flight and 500ms after completion, including failures. A monotonic Stopwatch replaces wall-clock comparisons; no delayed first action, queued spam or cooldown timers. Different commands remain independent so Disconnect can cancel an active Connect. Duplicate rejected connect/disconnect taps do not replay feedback.
- Server names retain single-line ellipsis and 600 weight, at 15 logical pixels with zero added letter spacing; horizontal padding12, leading minimum26 and title gap12 reclaim unused width. Circle and latency dimensions stay unchanged.
- BottomNavigationBar optics end above Android's safe area. A plain themed background covers that system area and SystemUiOverlayStyle uses a transparent navigation divider. This removes app-rendered sources of the reported dark bottom line; any physical-device/OEM residual still needs feedback.

## Regression evidence

Failing tests reproduced absent Home motion wiring, immediate content-position jump despite animated panel height, optical material covering the system area, and insufficient cooldown. The longer-name fixture fits at 360 logical width with compact layout and fails when previous font/spacing are restored. Cooldown tests exercise499/500ms, long-running operations, errors and cancellation availability.

## Reference

Context7 Flutter documentation informed the transition and repaint investigation. Local Flutter SizeChangedLayoutNotifier source explicitly permits repaint notifications during layout but warns against rebuilding/relayout. The callback here follows that constraint. https://api.flutter.dev/flutter/widgets/SizeChangedLayoutNotifier-class.html

## Limits

Automated checks establish motion/input/timing behavior, not measured phone FPS or final optical appearance. Install in place and leave the app unopened for user feedback. GitHub remains untouched until publication is explicitly requested.

## Verified candidate

- Full Flutter suite: 210 tests passed (`build/home-settle-tests.log`); analyzer: no issues (`build/home-settle-analyze.log`). Independent read-only review reported no important or critical issue.
- Release build completed for arm64-v8a, armeabi-v7a, x86_64 and universal (`build/home-settle-build.log`). All four APK signatures and version metadata verified: 1.2.1 / 4023. Universal includes all three supported ABIs.
- ARM64 installed in place via `adb install -r`: Success. Installed APK SHA-256 matches the candidate: `DD73C767DB32BC8433138D9D1D96F6A21FF231FA693FC0E67224FA1B97F761F3`.
- Device package lastUpdateTime: 2026-10-09 00:07:18; original firstInstallTime remains 2026-09-18 22:00:49. No uninstall, clear-data or application launch performed. No app process was running after installation.
- User checks still pending: dark Home scrolling optical stability, Restart layout motion in both directions, bottom system-area line on the physical display. No measured FPS or zero-jank claim.
