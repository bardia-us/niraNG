# niraNG Android 1.2.0+22 — validation and handoff

Date: 2026-10-05. Local build only; no commit, push, tag or GitHub release.
Existing backend/PHP edits and the niraN Windows source were not changed.

## Implemented

- Published `liquid_glass_widgets` 1.9.0 is vendored with its MIT license.
  Real premium shaders use the approved iOS-style material and spring menus.
  Compatibility patches are documented in `packages/liquid_glass_widgets/PATCHES.md`.
- Shader warm-up starts after the first frame, with a bounded, visible fallback.
  Unsupported renderers, high-contrast/Performance Mode and reduced motion use
  the appropriate lightweight path. Premium support is checked at runtime.
- Connect/Disconnect stretch interactions, finite shield state animation,
  ordinary frosted title bar, six accents, three dark canvases, Telegram vector.
- Haptic feedback is the default; optional preloaded short sound and Off remain.
  Menu boundary haptics honor the same preference.
- Full log selection/copy; live messages do not interrupt an active selection.
- Natural-height short server menus and additional ping/action spacing.
- Server order persists through selection; queued mutations and rollback preserve
  newer ping results. Native reorder only changes its snapshot after persistence.
- Public-IP diagnostics no longer block lifecycle work. Physical network tracking
  excludes the VPN itself. Operation tokens and network revisions reject stale
  reconnects, including network loss/return during reconnect.
- Bilingual bundled What's New is available even before public publication.

## SDK and dependency updates

- Flutter 3.47.6 / Dart 3.13.5: verified already current stable; not reinstalled.
- Android cmdline-tools 23.0, platform-tools 37.0.1, emulator 37.2.12 updated.
- Compile/target API 36; min API 24 preserved. NDK 28.2.13676358 preserved.
- Riverpod 3.4.3 and compatible Pub dependencies resolved; old glass renderer
  is no longer an active dependency. Glass package upgraded to published 1.9.0,
  not unreleased GitHub main.
- Build tooling remains Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20. Flutter emits
  future-support warnings for these, and Gradle reports deprecated features.
  They are not build failures. AGP/Gradle 9 migration was not mixed into this UI
  update. No validation-skip flag was used.
- Windows JBR selector failure was resolved by a build-local Unix-domain temp
  directory via JAVA_TOOL_OPTIONS; no system-wide Java/network setting changed.

## Executed verification

- `flutter test --no-pub --reporter expanded`: 88 passed.
- `flutter analyze --no-pub`: no issues found.
- `gradlew :app:testDebugUnitTest --rerun --offline --console=plain --no-daemon`:
  88 native tests across 25 suites; zero failures, errors or skipped tests.
- `flutter build apk --release --split-per-abi --no-pub`: succeeded.
- All three APK signatures verified. ARM64 signer SHA-256 matches the previous
  local 1.1.8 release: `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.
- Package `dev.nirang.client`, version `1.2.0`, base build 22. Split versionCodes
  1022 (ARM32), 2022 (ARM64), 4022 (x86_64), consistent with the existing policy.
- Compiled five upstream shader assets, bilingual notes and simple mark verified
  in the ARM64 APK. No signing secrets included in this report.
- Full suite includes manual drag, persistence/rollback/concurrent ordering,
  selection/copy, feedback preferences, registration, and narrow RTL menus with
  1.4x text scale. Independent code review found no outstanding code blocker.

## Outputs

Under `build/app/outputs/flutter-apk/`:

- `niraNG-v1.2.0-arm64-v8a.apk`: 28,754,728 bytes (27.4 MiB), most modern phones.
- `niraNG-v1.2.0-armeabi-v7a.apk`: 28,769,770 bytes (27.4 MiB), ARM32.
- `niraNG-v1.2.0-x86_64.apk`: 29,903,555 bytes (28.5 MiB), x86_64.

ARM64 APK SHA-256:
`C67CCC76DB1B0853AD1E990FE3BDD5D8C3183D9FDD671EBC69D1A56D881CBF8D`.

## Not verified / not included

No phone or configured AVD was connected. Actual GPU appearance, startup timing,
audio/haptic feel and Wi-Fi-without-Internet behavior still need a real-device
test. Widget tests and native lifecycle tests are not proof of visual approval
or of zero crashes on every Android device. No phone install was performed.

Recommended phone checks: upgrade in place without uninstalling; check retained
subscription/order/settings; test dark/light menu animation and selection; switch
servers after latency sorting; enable Wi-Fi without Internet and connect/stop;
lose/restore Wi-Fi during reconnect; select and copy long logs.

Android sing-box/core selection was not added: that needs separate native VPN
integration and protocol-compatibility testing. Windows-only System Proxy, tray,
installer and editable Home layout were deliberately not copied to Android.

## Same-version follow-up — 2026-10-06

This section supersedes the earlier no-phone verification status above. Version
remains **1.2.0+22**, package `dev.nirang.client`; no backend or Windows edits,
commit, tag, push or publication were performed for this follow-up.

Changes include retained directional pages with gesture/menu guards, elastic
navigation and a dedicated short pop/haptic cue, naturally sized menu geometry
with matching hit targets, finite usage-bar replay, clear pending public-IP
refresh with a five-second manual throttle, stale-network result rejection and
coalesced reconnect checks, clipped ordinary title blur, cleaner fitted flags,
local/private routing ahead of other rules, notification cleanup policy,
per-server TLS profile editing and parser-to-Xray ECH preservation.

Latest preference request: the first canvas option, **Midnight**, and the first
accent, a lighter **Purple**, are defaults. Existing valid saved choices are not
silently reset. OLED black remains truly black when explicitly selected.
Performance Mode defaults to on, retaining motion and optical glass rather than
replacing menus with static opaque panels.

### Verification executed

- Full Flutter suite: **123 passed**; analyzer: **No issues found**.
- Full native suite: **116 tests / 29 suites**, zero failures or errors.
- All three production APKs built from **lib/main.dart**, not the diagnostic
  entrypoint. Signatures verified; ARM64 retains the previous signing certificate.
- ARM64: 28,783,568 bytes; ARM32: 28,803,702; x86_64: 29,936,967.
- ARM64 SHA-256:
  `673568DEE3DCBCC58848751B52BB0E4E60B6261A4564E85B01DDA7B6D56F77F3`.
- ARM64 package metadata: versionName 1.2.0, versionCode 2022, min API24,
  target/compile API36. Five shader assets, 259 PNG flags, release notes and
  bundled native core present.
- Physical device: Samsung A34 SM-A346E, API36, 1080×2340, DPR2.8125,
  active display mode approximately120Hz. Engine log confirms Impeller/Vulkan.
- Device log reproduced missing `LiquidGlassRenderScope` for standalone
  premium triggers. Independent bounded render layers corrected that contract;
  the actual server screenshot then showed names, protocol text, ping and
  controls instead of black error placeholders. This was not a redaction feature.
- A UI/engine recreation with the VPN service kept running measured229ms warm
  Activity launch; this is **not** a cold-process startup or full access-check
  duration measurement. No cold restart was performed while VPN was active.
- Actual menu semantics placed four consecutive action rows at529–664,
  670–805,810–945 and951–1086 physical pixels. Header-menu entries began311px,
  not halfway down the screen. No action changing/deleting configs was selected.

### Performance scope

`tool/profile_android.dart` is a separate release-mode diagnostic entrypoint.
It records only feature and frame durations, in bounded log batches, with no
configuration identifiers, credentials or IP addresses. The final production
entrypoint does not import or activate it.

Mixed full-effects samples showed raster overruns: server raster P95≈69ms,
Home≈46ms, settings≈88ms, including cold work and simultaneous manual activity.
The saved Performance Mode preference was observed off. These samples do not
establish a controlled before/after comparison or sustained120fps; the frame
budget at120Hz is8.33ms. Visual approval and passing unit tests are not proof of
zero jank. Controlled performance-mode comparison and final installation status
are recorded separately after the device check.

ECH tests establish preservation into `tlsSettings.echConfigList`, including
Base64 plus/padding and dynamic DNS strings. A live ECH handshake/DNS failure
matrix and lower-API notification behavior have **not** been verified on hardware.
See [ECH source and scope](android-ech-support.md) and
[four-project optical review](android-glass-source-review.md).

## Final corrective package — 2026-10-06

This is the latest package, superseding the APK hashes and the pending
performance comparison above. Version remains **1.2.0+22**.

- The experimental detached page `SnapshotWidget` path was rejected after the
  user reported corrupted black/colored header pixels during a page transition.
  It is **not present in the final AppShell**; pages remain live and retained.
- `GlassMotionSync` synchronizes the premium renderer's transform-tracking
  nodes with the PageController before paint, instead of waiting for the
  usual post-composition transform callback. It does not capture textures,
  change the page layout, or rebuild the local SDF just for translation.
- Tab button transitions are 240ms ease-out, retaining horizontal direction,
  interrupted-transition safety and the open-menu gesture guard.
- Performance Mode now applies the same bounded optical recipe to panels and
  controls: full-opacity Gaussian frost, neutral blur/frost weights, and no
  redundant ghost pre-blur. Frost, spherical refraction, highlights and spring
  interactions remain; the full-effects recipe is unchanged.
- Short settings choices use measured natural rows. A scroll container is
  added only if their actual scaled text/row height exceeds available space.
  Language, feedback, theme and background choices have no scroll container
  when they fit; small viewports/large text can still reach all options.

Verification: **134 Flutter tests passed**, analyzer **No issues found**;
the native sources are unchanged since the passing **116-test** native run.
New regression tests cover live (non-snapshotted) page transitions, interrupted
navigation/disposal, synchronous optical repaint and listener replacement,
short choice dialogs and constrained/accessibility layouts.

Production entrypoint is **lib/main.dart**, not `tool/profile_android.dart`.
All three signatures verified against certificate SHA-256
`290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.

| ABI | Bytes | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 28,787,868 | AE87A44AA1E442071CA28C92C9A2F548060FA46A8D2241E4B588E857C7BD895B |
| armeabi-v7a | 28,806,878 | EBCD1AED950548C0F4F379E9C78D04AF331E4173B0A1E5D9F4F382B7C4B5AD54 |
| x86_64 | 29,938,527 | B6E73D7E96D08C63739928AAA9658D476D650EFAF2745B217F2C54F270D8AFEC |

The user stopped further device testing and requested installation without
opening the app. No final FPS/visual approval is claimed. Final installation
was attempted but ADB reported the selected device was not found; a second inventory
contained no devices. **This package has not yet been installed.** No uninstall,
data reset, app launch or phone test was performed after that instruction.
The requested independent final review was unavailable because its reviewer
hit the account usage limit; no successful independent review is claimed.

### Installation completed after USB reconnection

The same Samsung A34 was subsequently detected as authorized.
`adb install -r` returned **Success**, without uninstalling or resetting data.
The installed `base.apk` was read back and its SHA-256 exactly matched the
final ARM64 package:
`AE87A44AA1E442071CA28C92C9A2F548060FA46A8D2241E4B588E857C7BD895B`.
This supersedes the earlier disconnected-device installation status above.
The app was **not launched by the agent** after installation; no additional
on-device visual or FPS test was performed.

## Cold rendering and full-effects follow-up — 2026-10-06

This follow-up supersedes the previous final package once its build/install
evidence below is recorded. Version/package/signing identity remain unchanged.

- Stable cold-frame compositing contract for premium glass: layers are reserved
  before a geometry image is created, rather than depending on a paint-time
  predicate change. A failing/passing render-object regression covers this.
- Full effects omit the redundant ghost pre-blur and weighted frost compositor
  pass. They retain transparent ghost/cloud mixing, native frost, lens/rims,
  directional light and animations. Performance Mode keeps its full-cloud
  optimization; it was reported smooth by the user and was not replaced.
- Dark panel tint uses translucent white instead of the dark blue-black tint.
- Shader-free branded startup feedback labels device preparation, access
  verification and saved-settings loading; a slow network check explains its
  wait after four seconds. No percentage or fake network activity is shown.
- Local app preparation starts after consent while access verification is
  pending. App entry still waits for the authoritative access result. Native
  bridge calls use a single executor: overlapping Dart futures are **not** a
  measured native-startup speed-up. Access-server latency remains a dependency.
- Preloaded initial app state is explicitly processed after AppShell mounts,
  preserving performance prompt, auto-connect and the existing update/reminder
  sequence. Queued work requests a frame even on an idle cold launch.

Tests cover the actual bootstrap with preloaded controller, late administrator
denial, consent gate, slow verification feedback and cold compositing contract.
The independent review identified the initial-state regression; after its
red/green correction the reviewer found no further critical/important issue in
the scoped changes. The review did not validate phone FPS, visuals or install.

The user declined sing-box work for this update. Windows/backend/GitHub are
unchanged by this follow-up. No phone app launch or interactive profiling is
performed after installation; no final physical FPS/appearance approval is
claimed from local automated tests.

### Follow-up build/install evidence

- **140 Flutter tests passed** (`build/android-startup-full-tests.log`), including
  cold compositor and real preloaded-bootstrap regression cases.
- Analyzer: **No issues found** (`build/android-startup-analyze.log`).
- Production build: all three release ABIs passed, entrypoint `lib/main.dart`
  (`build/android-startup-production.log`). Native sources were not modified
  in this follow-up; the previous 116-test native run is historical, not a new
  execution for this package.
- Every APK signature verified against SHA-256 certificate
  `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.

| ABI | Bytes | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 28,789,192 | 609BE77EFCFD8C507CEE43F7D30974F797965518C82867BC1420C9E1CDFF38D9 |
| armeabi-v7a | 28,806,706 | 4665D72D01CBB8539A3D53887FECF039815BF276D1E0ACFC84F7BDA51C8FE2D5 |
| x86_64 | 29,938,559 | B151CDFA303C963EAEF7B061A438F1AB6C1142FD515FC795BCFCF0AB1B688BBA |

`adb -s <connected-device> install -r` returned **Success**. The installed `base.apk`
was read back to `build/installed-startup-base.apk`; its SHA-256 exactly matched
the ARM64 package above. Installed metadata confirms `dev.nirang.client`,
versionName `1.2.0`, versionCode `2022`, ABI `arm64-v8a`. No uninstall/data reset,
app launch, phone gesture or new on-device FPS benchmark was performed.

## Final dark-panel / ready-first startup correction — 2026-10-06

This section supersedes the previous access-before-entry startup description.
The user clarified that the seven seconds are a request deadline, NOT a delay
before starting the request. Startup now prepares saved app data locally, paints
its ready screen, and then starts automatic access/update requests immediately.
The app does not wait for those requests to display Home. Consent and saved
blocked/outdated policy still gate entry. Offline/timeouts do not create or
erase policy restrictions; a definitive backend denial still replaces Home.

- Device access uses a separate native executor and a monotonic seven-second
  total request budget. Status/token renewal share that budget; a watchdog
  actively disconnects a stalled connection. Startup GitHub requests have the
  same seven-second workflow limit and force-close their client on completion.
- Dark panel white alpha is reduced to `15/255`, without a smoked body tint.
  Upstream continuous native blur replaces interleaved frost on dark panels:
  sigma 6 in performance mode, 8 in full mode. Light/control recipes and live
  refraction, edge lighting, and motion are preserved.
- Public horizontal scroll notifications finish the imperceptible <=2 logical
  pixel tail. Active drags, fast flings, menu guards and intermediate pages on
  a Home-to-Settings transition are not deliberately interrupted.
- Review found three issues: temporary responses erasing cached restrictions,
  cached policy screen changes not rendering, and late update callbacks reading
  disposed Riverpod state. All were corrected; subsequent scoped read-only
  review found no remaining P1/P2. This is not an appearance/FPS certification.

Fresh verification:

- **149 Flutter tests passed**, `build/final-polish-tests.log`.
- **122 native tests / 30 suites / zero failures**,
  `build/final-polish-native.log` and native XML results.
- Analyzer: **No issues found**, `build/final-polish-analyze.log`.
- All three production release ABIs built from `lib/main.dart`,
  `build/final-polish-production.log`. Existing future-toolchain deprecation
  warnings remain; this scoped fix did not upgrade Gradle/AGP/Kotlin.
- APK signatures verify with the existing certificate SHA-256
  `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.

| ABI | Bytes | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 28,791,716 | 0FFF52C43619C0A00F384DD96DFE50824EDEF7F8E86B05E754D9A65CCF828736 |
| armeabi-v7a | 28,809,574 | 4625BD4B9C66F5F2CA754AC4E4CD05AF646BEA7C0489887A36B812BB7EBF4089 |
| x86_64 | 29,941,647 | CD4F810D8A509A5963524C27C60AE0BF7B32C09211F5C6E1DE978097C23C3425 |

ARM64 in-place `adb install -r` returned **Success**. Installed `base.apk` was
read back as `build/installed-final-polish-base.apk`; its SHA-256 exactly matches
the package above. Installed metadata remains `dev.nirang.client`, `1.2.0`,
versionCode `2022`, appId `10522`, firstInstallTime `2026-09-18 22:00:49`.
No uninstall/data clear, app launch, device gesture, or phone-side GPU/FPS test
was performed. Final visual approval remains with the user. Windows, backend,
GitHub publication, sing-box, and app version are unchanged by this correction.

## Final follow-up and four-APK release — 2026-10-06

This checkpoint supersedes the earlier three-APK/install reports above.

- Large dark message cards use a separate, calmer optical recipe; approved
  small controls and light-mode material keep their previous settings.
- Short dialogs use clamping scrolling only when content overflows, with more
  available height. Keyboard-constrained forms and long notes remain scrollable.
- Animated destination pages accept input at 80% visibility. Every interrupted
  transition resets the initial guard; outgoing pages and open popups stay
  protected. The test taps a real destination control before animation settles.
- First Telegram invitation remains mandatory. The second is a once-only
  Persian invitation with Later, including existing users, on a later process
  launch after the first. A matching current-connection probe must complete;
  stale/cancelled pings and open popups cannot qualify or consume it.
- Independent scoped review found three lifecycle/probe races. Regression
  tests cover the fixes; the final review found no remaining P1/P2 in scope.

Fresh verification on the release source:

- **160 Flutter tests passed**, `build/final-release-tests.log`.
- **126 native tests / 31 suites / zero failures or errors**,
  `build/release-followup-native.log` and native XML results.
- Analyzer: **No issues found**, `build/final-release-analyze.log`.
- The complete `tool/build_release.ps1` workflow passed,
  `build/release-packaging-final.log`, using production `lib/main.dart`.
  Switching split/universal packaging exposed a Windows R8 mapped-file lock;
  gracefully stopping the Gradle daemon between builds releases it. No shrinking
  or signing was disabled. Future-toolchain deprecation warnings remain.
- All four APKs have package `dev.nirang.client`, versionName `1.2.0`,
  installation versionCode `4022`, minimum API 24 and target API 36.
  Generated `BuildConfig.BASE_VERSION_CODE` remains `22` for backend policy.
- All signatures verify against the existing certificate SHA-256
  `290bd5c9aebb9bf0cc4933f26fcc8ca2712cc65c113bfce99ff5c769598545c4`.
- Universal contains Flutter and Xray native libraries for ARM64, ARM32 and
  x86-64; each split contains its own ABI. All include five glass shaders and
  the bilingual release-notes asset.

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 28,799,788 | 46F9C85C11186DD47C1D7108365D3F92D4BD3CB247A70F617C153CBF36D4F879 |
| armeabi-v7a | 28,817,502 | 6D89FD62C4F8B4A0F7D346392E600323B2BAE7E9AEEC08146ADF5C098501B13E |
| x86_64 | 29,949,375 | 8AA8CF30336BD6DE703ABCD306219FF758ADC9308F049F9D7EC6A3B5F5FD3C16 |
| universal | 70,467,799 | FBEFC1DB4F8DEFDDCEE23705F86ACAB4D6BB706E8805619BB97C8CE29A6E445D |

Universal in-place `adb install -r` returned **Success** on the connected
Samsung A34. Installed `base.apk` was read back to
`build/installed-universal-final.apk`; its SHA-256 exactly matches universal
above. Package metadata confirms `1.2.0`, code `4022`, appId `10522`, preserved
firstInstallTime `2026-09-18 22:00:49`, lastUpdateTime `2026-10-06 19:27:06`.
No uninstall/data clear, clone, app launch, gesture, new phone-side FPS test or
final visual approval was performed. Dark-card glare tuning is not a claim of
on-device visual equivalence. Windows, remote backend and sing-box are outside
this release; unrelated local PHP edits are excluded from its source commit.
