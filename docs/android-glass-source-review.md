# Android glass implementation review — 2026-10-06

Four implementation repositories, not just screenshots, were examined:

1. [sdegenaar/liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets): [geometry shader](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/shaders/liquid_glass_geometry_blended.frag) encodes SDF-derived surface normals, height and antialiased coverage; [render shader](https://github.com/sdegenaar/liquid_glass_widgets/blob/main/shaders/liquid_glass_render.frag) supplies Snell/paraxial refraction, directional rim lighting and Fresnel. This is the existing vendored renderer, not a newly substituted package.
2. [whynotmake-it/flutter_liquid_glass](https://github.com/whynotmake-it/flutter_liquid_glass): [renderer](https://github.com/whynotmake-it/flutter_liquid_glass/blob/main/packages/liquid_glass_renderer/lib/assets/shaders/render.glsl) is the historical basis for the first package. Hemispherical thickness and normal-dependent lighting are useful; it is not an independent fourth-party renderer to stack on top.
3. [AhmeedGamil/liquid_glass_easy](https://github.com/AhmeedGamil/liquid_glass_easy): [Impeller lens](https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/lib/src/widgets/render/impeller_liquid_glass_lens.dart), [optical border](https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/lib/assets/shaders/liquid_glass_border.glsl), and [batching](https://github.com/AhmeedGamil/liquid_glass_easy/blob/main/lib/src/widgets/lens/liquid_glass_batch.dart) separate physical-pixel coordinates, transform tracking and independent overlapping lens reads. No package replacement was necessary.
4. [colbymaloy/flutter_liquid_glass](https://github.com/colbymaloy/flutter_liquid_glass): [shader](https://github.com/colbymaloy/flutter_liquid_glass/blob/main/assets/shaders/glass_shader.frag) implements radial/sinusoidal UV displacement and tint, without the current package's SDF normals and volumetric rim. Switching to it would not improve the current optical model.

## Applied corrections

- A `GlassBackdropGroup` shares background reads; it is not a `LiquidGlassLayer`. The physical A34/Vulkan log showed `LiquidGlassRenderScope.of` null-check failure for grouped buttons without a renderer ancestor. Every standalone menu trigger now provisions its own bounded lens layer. This fixes the invalid renderer contract rather than covering the black error placeholders with an opaque panel.
- Connect and header-menu controls also use an independent optical lens instead of the nested vector vibrancy fast path, preserving press/stretch animation.
- The chosen iOS27 preset had `lightIntensity=0` and `fresnelStrength=0`. The existing shader now uses its spherical Snell model with restrained directional illumination (.35) and Fresnel (.18); no global white outline or artificial glow border was added.
- Performance mode uses the same geometry and spring motion, with an opaque frost cloud that skips the expensive ghost sampler. Short menus remain naturally sized; measured layout and hit-test geometry are shared.
- Non-overlapping server triggers have a screen-local backdrop group. Popups/overlapping glass do not share it; retained pages are not batched as one background.

See [Flutter BackdropFilter](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html) and [fragment shader guidance](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) for the engine constraints. A shader's modeled highlights are not proof of matching Apple's native material. GPU frame timing and visual approval must be reported separately from widget/JVM test results.

### Final transition correction

Detached full-page snapshots were experimentally tried and rejected after
real-device transition corruption. Final pages remain live. A scoped motion
listener invalidates the upstream transform-tracking optical nodes before the
current paint, rather than relying on their post-composition callback alone.
Performance panels and buttons share a full-cloud recipe: the shader's
`uFrost.x >= 1.0` branch uses the Gaussian frost directly, so the preceding
ghost pre-blur and alpha-weighting passes are omitted. The actual frost and
optical lens remain enabled. No opacity/save-layer batching safety checks were
removed, and overlapping/nested glass is not incorrectly pooled.

Final phone FPS and appearance are unverified: the user explicitly stopped
further on-device testing. See the final corrective package section of
[validation](android-1.2.0-validation.md) for exact build and installation status.

### Cold compositor contract and full-effects cost — 2026-10-06

The glass renderer previously derived `alwaysNeedsCompositing` from a geometry
image allocated during paint. Flutter flushes compositing bits before paint;
changing that predicate there without invalidating it can leave cold ancestor
clips non-composited. The renderer now declares a stable compositor contract
before the matte exists. A real base-render-object cold-frame regression fails
against the old predicate and passes with the correction. This is not a pixel
approval of the physical phone; that remains separate.

See [RenderObject compositing contract](https://api.flutter.dev/flutter/rendering/RenderObject/alwaysNeedsCompositing.html).

Full mode now keeps its partly transparent ghost/cloud mix, but omits the
separate ghost pre-blur and luminance-weighted frost pass. Native Gaussian frost,
spherical refraction, normal-driven lighting, rims and spring motion remain.
With zero ghost sigma the upstream shader uses its six-tap floor branch.
The previous 2.4 logical-pixel pre-blur also forced that floor branch on the A34:
this correction removes compositor passes, not a claimed 45-to-6 tap gain on
that device. Performance Mode retains its full-cloud branch, which skips the
ghost entirely. Light/dark recipes still differ; the dark panel's blue-black
tint is replaced by upstream's translucent white tint.

No new on-device FPS measurement was performed. The user reported Performance
Mode working well and full mode lagging; no 90/120 FPS guarantee is inferred
from that report or from Flutter tests.

### Dark panel blur/transmission correction — 2026-10-06

The subsequent screenshot showed readable background letters and an excessive
white cast. Dark panels now use the upstream continuous Gaussian pass (`frost:
0`, `blur: 6` in performance mode / `8` otherwise), followed by the SAME live
refraction/lighting shader. This replaces the interleaved frost pass rather
than stacking another filter on it. Upstream `frostAt` deliberately blends a
sharp ghost with its cloud; removing that path from dark panels avoids relying
on its alternate physical-row read for text diffusion. This is a source-based
pipeline correction, not a claimed pixel match on the A34's Vulkan driver.

The neutral white body remains white, but alpha is reduced from `31/255` to
`15/255`; no blue/black smoked tint is reintroduced. Controls retain their
existing material; light-mode recipes, edge normals, highlights, and motion
are unchanged. No detached snapshots or additional geometry/shader patches
were introduced in this correction.
