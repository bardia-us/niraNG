# Local compatibility patches (Android and Windows)

Source: published `liquid_glass_widgets` 1.9.0, MIT license retained.
Upstream: https://github.com/sdegenaar/liquid_glass_widgets
Vendored in niraNG; shared Pub-cache files are not changed. The existing
coverage/subpixel-rim fixes from the approved Windows material were reapplied
to the 1.9.0 release without changing preset colors, lens or rim intensity.

## Android feedback preference

`GlassMenu.enableHaptics` defaults to true (unchanged upstream behavior).
niraNG disables item-boundary vibration when Feedback is Sound or Off.
This changes neither morph animation nor selection/activation semantics.

## Menu layout and overlay visibility

Menu height, selection pill and slide-to-select hit regions use the same
laid-out row heights. Before the first layout, TextPainter measures actual
wrapped title/subtitle lines at the menu content width and system text scale;
maxLines limits wrapping instead of reserving unused lines. Layout changes
reconcile arbitrary icon/trailing and custom row dimensions. Short menus retain
only their 12px top/bottom inset without phantom empty space or scrolling.

`GlassMenu.onVisibilityChanged` reports overlay presence: true on show, false
after the closing spring settles, immediate route dismissal or widget disposal.
`onClose` retains its upstream close-start timing. The host uses visibility to
hold its horizontal page swipe lock until the overlay is actually removed.

## Geometry coverage

Upstream computes smoothstep coverage across the edge, then discards every
pixel with sdN >= 0, removing the outer half of the antialiasing window.
On native Windows at DPR 1, tool/edge_coverage_probe.dart measures alpha 0
where the existing 1px smoothstep should produce alpha approximately 40/255.

Keep that coverage and clamp only the optical surface distance to zero.
No changes to blur, frost, rim strength, refraction or material presets.
Native probe and visual review are separate checks; this patch is experimental
until the visible dotted edge is checked in the app.

## Subpixel rim sampling

The user confirmed the coverage patch improves the edge but a little aliasing
remains. The original hairline profile spans 0.25 to 0.667 physical pixels at
DPR 1. A native two-stage probe on constant white, moving the same edge through
eight 1/8px phases, measures total shade [29,60,68,55,40,25,13,5]: spread 63.
This isolates rim sampling from interleaved frost and changing backgrounds.

When the profile is narrower than a projected pixel footprint, average its
existing smoothstep analytically across that footprint. The width, intensity,
lighting recipe, blur and refraction settings remain unchanged; well-resolved
profiles use the unchanged original sample. No global supersampling is added.
The analytic SDF-normal footprint avoids derivatives after the alpha early-out.

Patched tool/rim_sampling_probe.dart: [37,45,48,45,39,32,29,30], spread 19
(regression budget 30): PASS. This is reduced sampling instability, not proof
that all visual aliasing is eliminated or that the user approved the final rim.

## Startup readiness (no optics changes)

Expose `LiquidGlassWidgets.premiumShadersReady` as a read-only cache check.
The upstream precache loader can report errors yet complete normally. niraNG
uses this to select the shader-free fallback after failure/timeout instead of
mistaking initialization completion for a usable premium renderer. Material
settings, rendering algorithms and shaders remain the sandbox recipe.
