// This app vendors and pins this renderer; the adapter is intentionally internal.
// ignore_for_file: implementation_imports
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'optical_capture_phase.dart';

class OpticalBackdropSource extends ChangeNotifier {
  OpticalBackdropSource({
    this.underlay,
    this.sharedBlurSigma = 0,
    List<double> regionalBlurSigmas = const [],
  }) : regionalBlurSigmas = List.unmodifiable(regionalBlurSigmas),
       assert(sharedBlurSigma >= 0),
       assert(regionalBlurSigmas.length <= 2);
  final OpticalBackdropSource? underlay;

  /// One input extent for surfaces with different blurs over the same region.
  /// The actual Gaussian recipe/output stays independent for each surface.
  final double sharedBlurSigma;
  final List<double> regionalBlurSigmas;
  double get pixelRatio => _ratio;
  final key = GlobalKey();
  ui.Image? _raw;
  final _blurred = <(double, Rect), ui.Image>{};
  final _regionInputs = <Rect, ui.Image>{};
  final _atlases = <Rect, ui.Image>{};
  bool _dirty = true;
  bool _notificationQueued = false;
  bool _disposed = false;
  double _ratio = 0;
  Size? _size;
  Offset origin = Offset.zero;
  void invalidate() {
    if (_disposed) return;
    final wasDirty = _dirty;
    _dirty = true;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notificationQueued) return;
      _notificationQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notificationQueued = false;
        // A later optical stage may already have consumed this frame's change.
        // Only request another paint when the cached image is still stale.
        if (!_disposed && _dirty) notifyListeners();
      });
      return;
    }
    if (!wasDirty) notifyListeners();
  }

  void _retire(ui.Image image) =>
      SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());

  /// One raw scene and one image job for both settled header blur recipes.
  /// Each slot retains its own Gaussian and clamp bounds; no quality reduction.
  ({ui.Image image, Offset origin, Rect sampleBounds})? captureAtlasRegion(
    double ratio,
    double sigma,
    Rect region,
  ) {
    final recipe = regionalBlurSigmas.indexOf((sigma * 100).round() / 100);
    final boundary = key.currentContext?.findRenderObject();
    if (underlay != null ||
        recipe < 0 ||
        boundary is! _SourceBoundary ||
        !boundary.hasSize) {
      return null;
    }
    _prepare(boundary, ratio);
    final bounds = Rect.fromLTWH(
      0,
      0,
      (boundary.size.width * ratio).ceilToDouble(),
      (boundary.size.height * ratio).ceilToDouble(),
    );
    final pixels = Rect.fromLTRB(
      (region.left * ratio).floorToDouble(),
      (region.top * ratio).floorToDouble(),
      (region.right * ratio).ceilToDouble(),
      (region.bottom * ratio).ceilToDouble(),
    ).intersect(bounds);
    if (pixels.isEmpty) return null;
    final image = _atlases.putIfAbsent(pixels, () {
      if (_atlases.length >= 2) _retire(_atlases.remove(_atlases.keys.first)!);
      final widest = regionalBlurSigmas.reduce((a, b) => a > b ? a : b);
      final input = pixels
          .inflate((widest * ratio * 3).ceilToDouble() + 2)
          .intersect(bounds);
      final raw = captureRegion(
        ratio,
        0,
        Rect.fromLTRB(
          input.left / ratio,
          input.top / ratio,
          input.right / ratio,
          input.bottom / ratio,
        ),
      )!.$1;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (var i = 0; i < regionalBlurSigmas.length; i++) {
        final top = Offset(0, i * pixels.height);
        canvas.save();
        canvas.clipRect(top & pixels.size);
        canvas.drawImage(
          raw,
          input.topLeft - pixels.topLeft + top,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: regionalBlurSigmas[i] * ratio,
              sigmaY: regionalBlurSigmas[i] * ratio,
              tileMode: ui.TileMode.clamp,
            ),
        );
        canvas.restore();
      }
      final picture = recorder.endRecording();
      try {
        return picture.toImageSync(
          pixels.width.toInt(),
          pixels.height.toInt() * regionalBlurSigmas.length,
        );
      } finally {
        picture.dispose();
      }
    });
    final slot = Rect.fromLTWH(
      0,
      recipe * pixels.height,
      pixels.width,
      pixels.height,
    );
    return (
      image: image,
      origin: origin + (pixels.topLeft - slot.topLeft) / ratio,
      sampleBounds: slot,
    );
  }

  (ui.Image, Offset)? captureRegion(double ratio, double sigma, Rect region) {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    _prepare(boundary, ratio);
    final bounds = Rect.fromLTWH(
      0,
      0,
      (boundary.size.width * ratio).ceilToDouble(),
      (boundary.size.height * ratio).ceilToDouble(),
    );
    final pixels = Rect.fromLTRB(
      (region.left * ratio).floorToDouble(),
      (region.top * ratio).floorToDouble(),
      (region.right * ratio).ceilToDouble(),
      (region.bottom * ratio).ceilToDouble(),
    ).intersect(bounds);
    if (pixels.isEmpty) return null;
    if (boundary is! _SourceBoundary) {
      // Compatibility for external RepaintBoundary owners; product boundaries
      // expose the protected OffsetLayer capture through captureRect below.
      final raw = capture(ratio, 0);
      return raw == null
          ? null
          : (_filtered(sigma, pixels), origin + pixels.topLeft / ratio);
    }
    final roundedSigma = (sigma * 100).round() / 100;
    final image = _blurred.putIfAbsent((roundedSigma, pixels), () {
      if (_blurred.length >= 2) _retire(_blurred.remove(_blurred.keys.first)!);
      // Capture only the filter's input support, not the entire scroll page.
      final inputSigma = sharedBlurSigma > roundedSigma
          ? sharedBlurSigma
          : roundedSigma;
      final input = roundedSigma == 0
          ? pixels
          : pixels
                .inflate((inputSigma * ratio * 3).ceilToDouble() + 2)
                .intersect(bounds);
      final local = Rect.fromLTRB(
        input.left / ratio,
        input.top / ratio,
        input.right / ratio,
        input.bottom / ratio,
      );
      ui.Image captureInput() {
        var raw = boundary.captureRect(local, ratio);
        final baseBox = underlay?.key.currentContext?.findRenderObject();
        final baseOrigin = baseBox is RenderBox && baseBox.hasSize
            ? baseBox.localToGlobal(Offset.zero)
            : underlay?.origin;
        final base = baseOrigin == null
            ? null
            : underlay?.captureRegion(
                ratio,
                0,
                local.shift(origin - baseOrigin),
              );
        if (base != null) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawImage(
            base.$1,
            (base.$2 - origin) * ratio - input.topLeft,
            Paint(),
          );
          canvas.drawImage(raw, Offset.zero, Paint());
          final picture = recorder.endRecording();
          final combined = picture.toImageSync(raw.width, raw.height);
          picture.dispose();
          _retire(raw);
          raw = combined;
        }
        return raw;
      }

      final shareInput = roundedSigma > 0 && sharedBlurSigma > 0;
      final raw = shareInput
          ? _regionInputs.putIfAbsent(input, () {
              if (_regionInputs.length >= 2) {
                _retire(_regionInputs.remove(_regionInputs.keys.first)!);
              }
              return captureInput();
            })
          : captureInput();
      // An underlay asks for unfiltered pixels. The raw snapshot already has
      // the exact output extent; a sigma-zero filter would allocate and render
      // a second identical texture on every moving frame.
      if (roundedSigma == 0) return raw;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(
        raw,
        input.topLeft - pixels.topLeft,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: roundedSigma * ratio,
            sigmaY: roundedSigma * ratio,
            tileMode: ui.TileMode.clamp,
          ),
      );
      final picture = recorder.endRecording();
      final filtered = picture.toImageSync(
        pixels.width.toInt(),
        pixels.height.toInt(),
      );
      picture.dispose();
      if (!shareInput) _retire(raw);
      return filtered;
    });
    return (image, origin + pixels.topLeft / ratio);
  }

  void _prepare(RenderRepaintBoundary boundary, double ratio) {
    // A retained PageView can move this boundary without repainting its local
    // pixels. Reuse the image, never its previous screen-space placement.
    origin = boundary.localToGlobal(Offset.zero);
    // Flutter flushes independent boundaries deepest-first, not in backdrop
    // dependency order. Complete this earlier sibling's pending display list
    // before sampling it; returning the old image adds visible scroll latency.
    // This is the same composited-child paint used by PaintingContext.paintChild.
    if (boundary is _SourceBoundary && boundary.paintPending) {
      PaintingContext.repaintCompositedChild(boundary);
    }
    if (_dirty || _ratio != ratio || _size != boundary.size) {
      if (_raw != null) _retire(_raw!);
      _raw = null;
      for (final image in _blurred.values) {
        _retire(image);
      }
      _blurred.clear();
      for (final image in _regionInputs.values) {
        _retire(image);
      }
      _regionInputs.clear();
      for (final image in _atlases.values) {
        _retire(image);
      }
      _atlases.clear();
      _ratio = ratio;
      _size = boundary.size;
      _dirty = false;
    }
  }

  ui.Image? capture(double ratio, double sigma) {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    _prepare(boundary, ratio);
    if (_raw == null) {
      var next = OpticalCapturePhase.record(
        () => boundary.toImageSync(pixelRatio: ratio),
      );
      final base = underlay?.capture(ratio, 0);
      if (base != null) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(base, (underlay!.origin - origin) * ratio, Paint());
        canvas.drawImage(next, Offset.zero, Paint());
        final picture = recorder.endRecording();
        final combined = picture.toImageSync(next.width, next.height);
        picture.dispose();
        _retire(next);
        next = combined;
      }
      _raw = next;
    }
    if (sigma <= .001) return _raw;
    return _filtered(
      sigma,
      Rect.fromLTWH(0, 0, _raw!.width.toDouble(), _raw!.height.toDouble()),
    );
  }

  ui.Image _filtered(double sigma, Rect pixels) {
    final roundedSigma = (sigma * 100).round() / 100;
    return _blurred.putIfAbsent((roundedSigma, pixels), () {
      // One GPU-resident Gaussian per recipe, not a backdrop extraction per lens.
      if (_blurred.length >= 2) _retire(_blurred.remove(_blurred.keys.first)!);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(
        _raw!,
        -pixels.topLeft,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: roundedSigma * _ratio,
            sigmaY: roundedSigma * _ratio,
            tileMode: ui.TileMode.clamp,
          ),
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        pixels.width.toInt(),
        pixels.height.toInt(),
      );
      picture.dispose();
      return image;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _raw?.dispose();
    _raw = null;
    for (final image in _blurred.values) {
      image.dispose();
    }
    _blurred.clear();
    for (final image in _regionInputs.values) {
      image.dispose();
    }
    _regionInputs.clear();
    for (final image in _atlases.values) {
      image.dispose();
    }
    _atlases.clear();
    super.dispose();
  }
}

/// Invalidates from actual paint, including presses/reorders, not just scroll.
/// The later stage is notified before it paints; this is not a frame callback.
class OpticalBackdropBoundary extends SingleChildRenderObjectWidget {
  OpticalBackdropBoundary({required this.source, required super.child})
    : super(key: source.key);
  final OpticalBackdropSource source;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SourceBoundary(source);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _SourceBoundary).source = source;
  }
}

class _SourceBoundary extends RenderRepaintBoundary {
  _SourceBoundary(this.source);
  OpticalBackdropSource source;
  bool paintPending = true;
  ui.Image captureRect(Rect bounds, double ratio) => OpticalCapturePhase.record(
    () => (layer! as OffsetLayer).toImageSync(bounds, pixelRatio: ratio),
  );

  @override
  void markNeedsPaint() {
    paintPending = true;
    super.markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    paintPending = false;
    source.invalidate();
  }
}

/// Keeps row repaint isolation, but reports a changed display list to the
/// shared capture source even when its outer boundary did not repaint.
class OpticalPaintObserver extends SingleChildRenderObjectWidget {
  const OpticalPaintObserver({
    required this.onPaint,
    required super.child,
    super.key,
  });
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintObserver(onPaint);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _PaintObserver).onPaint = onPaint;
  }
}

class _PaintObserver extends RenderRepaintBoundary {
  _PaintObserver(this.onPaint);
  VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

/// Isolate the live input from app chrome outside this page. This is a retained
/// compositor pass, not a new app-owned image or a readback on each scroll tick.
class LiveGlassViewport extends SingleChildRenderObjectWidget {
  const LiveGlassViewport({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _LiveGlassViewport();
}

class _LiveGlassViewport extends RenderProxyBox
    implements LiquidGlassCompositorPass {
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Rect get compositorBoundsInScreenSpace =>
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  @override
  void paint(PaintingContext context, Offset offset) {
    layer = context.pushClipRect(
      true,
      offset,
      Offset.zero & size,
      super.paint,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      oldLayer: layer as ClipRectLayer?,
    );
  }
}

/// Resolve either the live compositor or a current explicitly staged snapshot.
class OpticalBackdropCapture extends SingleChildRenderObjectWidget {
  const OpticalBackdropCapture({
    required this.source,
    this.motion,
    this.enabled = true,
    this.paintedOutput,
    this.sampleRegion,
    this.liveBackdrop = false,
    required super.child,
    super.key,
  });
  final OpticalBackdropSource source;
  final Listenable? motion;
  final bool enabled;
  final OpticalBackdropSource? paintedOutput;

  /// Source-local logical bounds, including refraction/drag/filter overscan.
  final Rect? sampleRegion;

  /// Let settled surfaces sample the current compositor instead of taking
  /// intermediate ui.Images. Fractional material fades keep the capture path
  /// so a disappearing overlapping lens does not erase the glass below it.
  final bool liveBackdrop;
  @override
  RenderObject createRenderObject(BuildContext context) => _CaptureHost(
    source,
    motion,
    MediaQuery.devicePixelRatioOf(context),
    enabled,
    paintedOutput,
    sampleRegion,
    liveBackdrop,
  );
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _CaptureHost).update(
    source,
    motion,
    MediaQuery.devicePixelRatioOf(context),
    enabled,
    paintedOutput,
    sampleRegion,
    liveBackdrop,
  );
}

class _CaptureHost extends RenderProxyBox
    implements LiquidGlassBackdropProvider {
  _CaptureHost(
    this.source,
    this.motion,
    this.ratio,
    this.enabled,
    this.paintedOutput,
    this.sampleRegion,
    this.liveBackdrop,
  );
  OpticalBackdropSource source;
  Listenable? motion;
  double ratio;
  bool enabled;
  OpticalBackdropSource? paintedOutput;
  Rect? sampleRegion;
  bool liveBackdrop;
  final _liveBlurKey = BackdropKey();
  final _blurRecipe = Expando<double>();
  bool _paintQueued = false;
  bool _geometryMoved = false;
  void update(
    OpticalBackdropSource nextSource,
    Listenable? nextMotion,
    double nextRatio,
    bool nextEnabled,
    OpticalBackdropSource? nextOutput,
    Rect? nextRegion,
    bool nextLiveBackdrop,
  ) {
    if (attached && enabled) {
      motion?.removeListener(_moved);
      source.removeListener(_sourceChanged);
    }
    source = nextSource;
    motion = nextMotion;
    ratio = nextRatio;
    enabled = nextEnabled;
    paintedOutput = nextOutput;
    sampleRegion = nextRegion;
    liveBackdrop = nextLiveBackdrop;
    if (attached && enabled) {
      motion?.addListener(_moved);
      source.addListener(_sourceChanged);
    }
    markNeedsPaint();
  }

  void _moved() {
    if (!enabled) return;
    _geometryMoved = paintedOutput != null;
    source.invalidate();
    _sourceChanged();
  }

  void _sourceChanged() {
    if (!enabled) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_paintQueued) return;
      _paintQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _paintQueued = false;
        if (attached) _sourceChanged();
      });
      return;
    }
    // The optical controls have their own repaint boundaries. Dirty those too,
    // before paint, so they cannot retain a display list with an older image.
    var requiresCapturedPaint = !liveBackdrop;
    void invalidateGlass(RenderObject node) {
      if (node is RenderOffstage && node.offstage) return;
      if (node is LiquidGlassRenderObject) {
        if (liveBackdrop && node.captureImage == null && !_geometryMoved) {
          // The compositor reuses this filter layer against the current scene.
          // Scrolling its backdrop does not require recording the shader again.
          return;
        }
        requiresCapturedPaint = true;
        // Ask the owner to consume current layout transforms. Uniform motion
        // reuses its matte; only a changed local composition is rasterized.
        if (_geometryMoved) node.markCapturedGeometryMoved();
        node.markNeedsPaint();
      }
      node.visitChildren(invalidateGlass);
    }

    visitChildren(invalidateGlass);
    _geometryMoved = false;
    if (requiresCapturedPaint) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (enabled) {
      motion?.addListener(_moved);
      source.addListener(_sourceChanged);
    }
  }

  @override
  void detach() {
    if (enabled) {
      motion?.removeListener(_moved);
      source.removeListener(_sourceChanged);
    }
    super.detach();
  }

  @override
  void resolveCapturedBackdropForPaint(LiquidGlassRenderObject node) {
    if (!enabled) return;
    final boundary = source.key.currentContext?.findRenderObject();
    if (boundary is RenderBox && boundary.hasSize) {
      node.samplingBoundsInScreenSpace = MatrixUtils.transformRect(
        boundary.getTransformTo(null),
        Offset.zero & boundary.size,
      );
    }
    if (node.settings.blur > 0) _blurRecipe[node] = node.settings.blur;
    if (liveBackdrop &&
        node.settings.visibility == 1 &&
        node.settings.effectiveFrost == 0) {
      // Blur restores the shared pristine input before each independent lens.
      // Composing blur+refraction would make the second lens see the first.
      node.bindLiveBackdropForPaint(_liveBlurKey, blur: _blurRecipe[node] ?? 0);
      node.onOpticalPaint = paintedOutput?.invalidate;
      return;
    }
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    node.combineClearBlur = true;
    node.onOpticalPaint = paintedOutput?.invalidate;
    final blur = (_blurRecipe[node] ?? 0) * node.settings.visibility;
    // Only the low-pass-filtered backdrop is downsampled; native geometry and
    // foreground stay at device DPR. Resolve BEFORE this node draws, not in an
    // ancestor paint that can run after the node's own repaint boundary.
    final captureRatio = ratio > 1 ? 1.0 : ratio;
    final region = sampleRegion;
    final atlas = region == null
        ? null
        : source.captureAtlasRegion(captureRatio, blur, region);
    if (atlas != null) {
      node.bindCapturedBackdropForPaint(
        atlas.image,
        origin: atlas.origin,
        pixelRatio: source.pixelRatio,
        sampleBounds: atlas.sampleBounds,
      );
      return;
    }
    final regional = region == null
        ? null
        : source.captureRegion(captureRatio, blur, region);
    final image = region == null
        ? source.capture(captureRatio, blur)
        : regional?.$1;
    if (image != null) {
      node.bindCapturedBackdropForPaint(
        image,
        origin: regional?.$2 ?? source.origin,
        pixelRatio: source.pixelRatio,
      );
    }
  }
}
