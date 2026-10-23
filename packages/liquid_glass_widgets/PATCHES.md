# Local compatibility patches (Android and Windows)

Source: published `liquid_glass_widgets` 1.9.0, MIT license retained.
Upstream: https://github.com/sdegenaar/liquid_glass_widgets
Vendored in niraNG; shared Pub-cache files are not changed. The existing
coverage/subpixel-rim fixes from the approved Windows material were reapplied
to the 1.9.0 release without changing preset colors, lens or rim intensity.

## Android product follow-up: shared row pass and fresh capture

### 2026-10-24: popup routing outside the captured drag overlay

`GlassMenu.useRootOverlay` is an opt-in (default false). Server row actions use
the root overlay for both popup layout and anchor coordinates, so the captured
local reorder overlay cannot sample its own menu. Other menus keep their existing
nearest-overlay behavior. The held row's original keyed action menu is promoted
into the card proxy; the shared decorative stage retains the other rows unchanged.

### 2026-10-23: per-recipe capture slots

Servers can bind an atlas slot through `bindCapturedBackdropForPaint` with
pixel sample bounds. Existing clamp uniforms keep manual bilinear taps inside
that slot; ordinary captures retain full-image bounds and the public image setter
clears prior slot state. Texture-coordinate scale and physical SDF remain unchanged.
Touch-light radius uses the original slot height, not the combined texture height.
Real packaged-shader pixels cover a black slot next to a red slot, refraction,
bevel and active touch lighting versus an independent image (maximum error2/255).
Both shader entrypoints are revision marked to invalidate include-dependent assets.
This does not assert Android FPS gains; use the measured product journal.

### 2026-10-22: directional oval mask and bounded sampling

Free stretch elongates along the drag with reciprocal transverse contraction,
bounded even on long diagonal pulls. Oval masks use affine covariance principal
diameters/axis instead of the enclosing rectangle; unused oval corner slots carry
the axis vector, retaining the seven-float ABI and existing shape count. Geometry
reuse compares full transforms (opposite diagonals can have identical bounds).
Paraxial refraction is confined to the outer bevel; the inner face keeps backdrop
scale. A low environmental rim lobe complements the directional reflection on
the sides without a thick stroke or body wash. Packaged entrypoints are revision
marked to invalidate stale include-dependent shader assets.

Product captures preblur only the end-column/header sample regions with drag,
refraction and filter overscan, mirrored for RTL. Raw backdrop freshness and
uniform-scroll matte reuse remain unchanged. Actual FragmentProgram pixel tests
cover flat body/retained lens, side lighting, diagonal mask, opposite-diagonal
cache invalidation, and regional/full-image blur equivalence. Desktop tests are
not Android visual or FPS acceptance; this update permits phone installation only.

### 2026-10-21: direct scene and live matte cache

Servers no longer uses the historical Flow path described below. Its direct,
fixed-extent visible-control scene follows the approved Lab. The working header,
ordinary translucency, shader material, blur amounts and stretch remain intact.

The optical cache now checks actual current shape poses before paint rather
than waiting for a tracking callback after compositing. Removed geometry and
groups becoming empty invalidate their old contribution. An unchanged batch
moving by one affine translation reuses its existing GPU matte at the new
coordinates; changed SDFs, relative transforms, membership, DPR and perspective
rebuild synchronously. Picture-to-image conversion of the same shape cache does
not defeat reuse. The redundant second geometry-gather pass is removed.

`test/optical_geometry_render_test.dart` directly drives real render objects and
the compiled SDF shader, rather than AdaptiveGlass's shader-free desktop-test
fallback. RED/GREEN regressions cover uniform scroll texture identity/placement,
first-frame drag masks, one gather per rebuild, removal/reentry, DPR and
perspective. Disabled product capture adapters also detach their listeners,
with a real repaint counter regression through repeated enable/disable cycles.
No optical quality/resolution reduction is used. These are code/renderer tests,
not an assertion of native FPS; the user requested no further phone testing.

The 4026 integration is not visually approved: the user observed delayed
background text while scrolling, despite real Premium optics being active.
Product row controls now use the approved Lab composition: one shared
AdaptiveLiquidGlassLayer, a zero-blend group per lens and useOwnLayer=false.
Popup overlays and the header trigger keep independent optics. Cached mounted
controls still move through Flow rather than rebuilding their widget subtrees.
The active GPU stage is also restricted to viewport lenses with a 64-logical-px
guard band, like the Lab's visible range. The larger ReorderableListView cache
retains row/menu widgets but no longer registers all its offscreen geometry in
the shared optical layer. Flow updates their transforms without replacing the
retained menu widgets. This retains controls beneath fixed headers and allows
edge stretch; it does not reduce shader resolution or remove optics.

The product capture adapter previously returned the last cached image when its
source boundary still needed painting. Flutter's deepest-first repaint order
can therefore show old text in a lens. The adapter now completes that pending
composited-child paint before sampling, using PaintingContext's existing paint
operation. A real pending red/blue image regression fails before this change
and passes after it. This changes no shader, resolution or optical depth.
Native visual/FPS acceptance remains a separate check from unit tests.

The product Flow adapter exposes live anchor transforms before paint (normal
Flow only exposes the last painted child matrix), and motion invalidates the
shared matte's placement without discarding cached local shape geometry.
RenderLiquidGlass overrides setUpLayer to keep transform notifications active
through BOTH marker paint and paintFromLayer's mixin paint: neither consumes
the owner's optical matte. Real-owner and pre-paint-position regressions cover
these distinct paths. A row trigger uses a temporary own layer while its
materialize glassProgress is below one, so the lens can fade independently of
the shared resting rows; the outer blend wrapper/button identity stays stable.

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

## Visible-page motion and shared trigger backdrops (2026-10-07)

`GlassMotionSync.shouldRefresh` is an optional per-motion predicate. niraNG
uses the live fractional page offset to keep both intersecting pages refreshed
before paint, while avoiding traversal of invisible retained pages. Hidden
Offstage descendants are also skipped. No material settings or shaders change.

`GlassMenu.useGlassTriggerFade` defaults to false to retain plain-trigger
behavior. niraNG opts in for materialize-aware GlassIconButton triggers: the
outer Opacity is removed because the backdrop group's safety check excludes
even fully opaque RenderOpacity ancestors. The existing material visibility
channel fades glass; its content channel retains the previous combined fade.
Hidden trigger semantics are excluded explicitly. Keyboard focus rings fade
through paint alpha rather than a new save-layer, and return on menu close.

Tests reproduce the former group exclusion, hidden-tree traversal and focus/
semantics regressions. Widget tests establish eligibility, not actual GPU
pass count or device FPS. See docs/performance/2026-10-07-glass-motion.md in
the host project for deferred profiling and light-mode blur follow-up.

## Approved Android Lab clear-lens port (2026-10-21)

Targeted renderer/capture/stretch/clear-shader changes are taken from the
user-approved Android Lab snapshot `lab-premium-121fps-source-20261020.zip`
(SHA256 E52F023ED0B23E42E66C55149303E76A2B32B62FCFE6A23F0AC60CA9B98779F9).
The package's 1.9 public widgets/settings remain; this is not a package downgrade.
Capture backgrounds use one texel per logical pixel while geometry and glyphs
retain native DPR. Screen/canvas mapping and sampling bounds exclude system bars.
Free diagonal deformation uses the approved Lab formula, not uniform inflation.
Clear-only rendering is registered separately; frost-zero material does not pay
the unused frost shader cost. Existing anchored-menu choreography is retained.

The host's staged list optics use an optional LiquidGlassBackdropProvider and
onOpticalPaint callback. Capture resolves at the beginning of each optical node's
own paint, since nested repaint boundaries flush before their ancestors. Binding
does not call markNeedsPaint during paint. Source invalidations are coalesced
outside paint, skipped when already consumed, and don't run an idle ticker.
The host observes row paint and its existing press motion for source freshness.
Headers sample the row-inclusive scene; controls sample the unglassed list.
No merged analytic-glass path or matte substitution is used in normal mode.

Host static analysis/release compilation are separate from native visual/FPS
validation. At the user's request no product tests or device FPS runs accompany
this port; the Lab's measured 121 FPS is not a measured niraNG result.

## Corrective product integration (2026-10-21)

The first port passed compilation but was not visually accepted: `initialize`
was called with `never`, which skips Premium preloading and kept the product's
readiness gate false. The host now explicitly loads Premium; initialization
also caches the clear render variant and readiness verifies all three programs.
A bounded startup wait does not cancel late readiness or require scrolling.

Restore the original product cold-frame compositing contract: optical render
objects reserve compositing before paint creates their first geometry image.
The existing cold nested-glass regression reproduced the lost contract.
Transform tracking records the transform of an actual paint, avoiding another
request for a transform that motion sync already painted this frame. Cached
unpainted translations still request their needed repaint. The original motion
regression reproduced the redundant trailing frame before this correction.

The host Flow portal uses attach/detach render links, not GlobalKey lookups of
inactive recycled row elements. A real scroll/hit-test regression reproduced
the inactive-element exception before this fix. Product verification and any
measured FPS are recorded separately in docs/development-history.md.

## Materialize foreground compositing (2026-10-22)

`GlassMaterializeScope.wrapContent` accepts the surface's content visibility.
The engine passes it directly instead of inserting a second Opacity inside the
content Gaussian. Uniform alpha multiplication commutes with premultiplied
Gaussian filtering; the host regression checks real filtered RGBA (including
transparent edges) within two 8-bit levels. Glass settings, its geometry fade,
content timing/sigma, and backdrop filters are not changed. The host's separate
Home-only shared surface owner does not alter the engine's default filter path.

## Shared foreground invalidation (2026-10-22)

Geometry markers forward paint invalidation to their matching ancestor optical
owner. A ListView viewport is itself a repaint boundary even without automatic
row boundaries; it could consume a changed ping/IP/text paint while the owner
kept the old foreground until scroll motion repainted it. This is paint-only:
local SDF images are retained. Detached/offstage or non-ancestor optical owners
are not invalidated through this path. Two host regressions use actual cached
frame pixels for text and paint-only updates through a viewport, with no scroll,
and assert unchanged matte identity and no idle rendering loop.
