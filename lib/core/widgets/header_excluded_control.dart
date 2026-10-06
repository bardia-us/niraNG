import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Excludes only a scrolling trigger's overlap with the rounded fixed header.
/// The clip follows the final composed transform, including reorder/press motion.
class HeaderExcludedControl extends SingleChildRenderObjectWidget {
  const HeaderExcludedControl({
    required this.headerKey,
    required super.child,
    this.headerRadius = 26,
    super.key,
  });
  final GlobalKey headerKey;
  final double headerRadius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HeaderExcludedRenderBox(headerKey, headerRadius);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _HeaderExcludedRenderBox)
      ..headerKey = headerKey
      ..headerRadius = headerRadius;
  }
}

class _HeaderExcludedRenderBox extends RenderProxyBox {
  _HeaderExcludedRenderBox(this.headerKey, this.headerRadius);
  GlobalKey headerKey;
  double headerRadius;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    covariant _HeaderExclusionLayer? oldLayer,
  }) => oldLayer ?? _HeaderExclusionLayer(this);

  RRect? get headerRegion {
    final header = headerKey.currentContext?.findRenderObject();
    if (header is! RenderBox ||
        !header.attached ||
        !header.hasSize ||
        header.owner != owner ||
        header.size.isEmpty) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      header.getTransformTo(this),
      Offset.zero & header.size,
    );
    if (!rect.isFinite) return null;
    return RRect.fromRectAndRadius(
      rect,
      Radius.elliptical(
        headerRadius * rect.width / header.size.width,
        headerRadius * rect.height / header.size.height,
      ),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (headerRegion?.contains(position) ?? false) return false;
    return super.hitTest(result, position: position);
  }
}

class _HeaderExclusionLayer extends OffsetLayer {
  _HeaderExclusionLayer(this.control);
  final _HeaderExcludedRenderBox control;
  ui.ClipPathEngineLayer? _clipEngine;

  // A cached row may move without painting. Resolve the cutout during scene
  // composition, not via post-frame repaint or a scroll-only invalidation.
  @override
  bool get alwaysNeedsAddToScene => true;

  // OffsetLayer's offset setter invalidates a normally retained layer. This
  // layer is already unconditionally added on every composed scene.
  @override
  void markNeedsAddToScene() {}

  void _replaceClip(ui.ClipPathEngineLayer? next) {
    if (identical(next, _clipEngine)) return;
    _clipEngine?.dispose();
    _clipEngine = next;
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (!control.attached || !control.hasSize) return;
    final header = control.headerRegion;
    final bounds = Offset.zero & control.size;
    if (header == null || !header.outerRect.overlaps(bounds)) {
      _replaceClip(null);
      super.addToScene(builder);
      return;
    }
    if ([
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ].every(header.contains)) {
      // Retain local content for instant restoration, but do not compose any
      // child optical filters while the control is completely under the header.
      _replaceClip(null);
      engineLayer = null;
      return;
    }
    final visible = Path.combine(
      PathOperation.difference,
      Path()..addRect(bounds.inflate(24)),
      Path()..addRRect(header),
    );
    _replaceClip(
      builder.pushClipPath(
        visible.shift(offset),
        clipBehavior: Clip.antiAlias,
        oldLayer: _clipEngine,
      ),
    );
    super.addToScene(builder);
    builder.pop();
  }

  @override
  void dispose() {
    _replaceClip(null);
    super.dispose();
  }
}
