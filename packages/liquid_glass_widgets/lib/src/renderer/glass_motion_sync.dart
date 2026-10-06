import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../engine/internal/transform_tracking_repaint_boundary_mixin.dart';

/// Keeps moving glass live; no detached texture capture is involved.
class GlassMotionSync extends SingleChildRenderObjectWidget {
  const GlassMotionSync(
      {required this.motion,
      required super.child,
      this.shouldRefresh,
      super.key});
  final Listenable motion;

  /// Evaluated on motion, without rebuilding the widget per scroll pixel.
  /// Return false only while the entire subtree is outside the viewport.
  final bool Function()? shouldRefresh;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassMotionSync(motion, shouldRefresh);
  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderGlassMotionSync renderObject) {
    renderObject
      ..shouldRefresh = shouldRefresh
      ..motion = motion;
  }
}

class _RenderGlassMotionSync extends RenderProxyBox {
  _RenderGlassMotionSync(this._motion, this.shouldRefresh);
  Listenable _motion;
  bool Function()? shouldRefresh;
  set motion(Listenable value) {
    if (identical(value, _motion)) return;
    if (attached) _motion.removeListener(_onMotion);
    _motion = value;
    if (attached) _motion.addListener(_onMotion);
  }

  void _onMotion() {
    if (!attached || shouldRefresh?.call() == false) return;
    void refresh(RenderObject node) {
      if (node is RenderOffstage && node.offstage) return;
      // Normal transform tracking runs after composition. A translating
      // viewport must refresh optical coordinates before the current paint.
      // Only optical nodes are dirtied; their local SDF remains reusable.
      if (node is TransformTrackingRenderObjectMixin) node.markNeedsPaint();
      node.visitChildren(refresh);
    }

    visitChildren(refresh);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(_onMotion);
  }

  @override
  void detach() {
    _motion.removeListener(_onMotion);
    super.detach();
  }

  @override
  void dispose() {
    _motion.removeListener(_onMotion);
    super.dispose();
  }
}
