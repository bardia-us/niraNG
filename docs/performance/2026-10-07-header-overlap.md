# Header overlap and page-transition tail

Same-version follow-up to checkpoint `55653810bf6704424579d5fd2ce342af92fb051d` (1.2.1+23).

## Scope and mechanism

- Only scrolling server-row action triggers are decorated with `HeaderExcludedControl`. Its composition-time mask subtracts the fixed header's actual rounded region using render-tree transforms. The header's own action button, server title/ping and popup overlay are untouched.
- Outside the header the original child composes without clipping or any material/opacity change. Partly covered triggers use an anti-aliased clip without a saveLayer; fully covered triggers do not compose their optical subtree. Cached local content is retained for immediate restoration. The mask follows scroll, press and reorder transforms in the current scene without a scroll listener, post-frame correction or per-pixel widget rebuild; retained engine clips are disposed normally.
- The page controller no longer jumps to the destination during its last two pixels. The existing 240ms ease-out transition and 80%-visible input unlock remain. Reduced-motion navigation still jumps intentionally.

## Verification boundaries

- Controlled raster regression checks cover uncovered / partially covered / fully covered composited controls, same-frame restoration after scroll and non-scroll parent translation, and hit testing. Real upstream controls retain their 40x40 circle, own optical layer and menu overlay in both themes and performance modes.
- Navigation tests check intermediate positions through the 230–235ms tail, early input, interruption, swipes, retained-page state and open-menu safety.
- These tests establish clipping and navigation behavior, not a measured GPU/frame-rate improvement or final on-device visual approval. No physical app launch is required for this validation.
- The prior circle checkpoint APK and manifest remain recoverable separately. Backend/PHP, VPN logic, signing identity and version are unchanged; no publication is part of this change.

## Validated local candidate

- 173 Flutter tests pass (`build/header-overlap-full-tests.log`); analyzer is clean (`build/header-overlap-analyze.log`). Independent read-only review found no remaining Critical/Important issue after the non-scroll-transform correction.
- Signed ARM64, ARM32, x86_64 and universal APKs built successfully (`build/header-overlap-release-build.log`). Universal metadata contains all three ABIs. All four packages retain `dev.nirang.client`, version `1.2.1`, installation code `4023` and the original signing certificate.
- ARM64 installed in place on the connected A34. Installed base APK SHA-256 matches `6C52CD173E80FF3BC9C89014428F915F57DF01228225DD3CC0409B88CBCD9DFC`. Original first-install timestamp is unchanged; last update is `2026-10-07 01:47:57`. No uninstall, data clearing or app launch was performed by the agent.
- Upstream optical coordinates are refreshed after composition when a cached transform changes; final first-reveal shader appearance and GPU frame times still require user/device feedback. This change does not promise zero jank.
