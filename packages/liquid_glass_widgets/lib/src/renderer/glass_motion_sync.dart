import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../engine/internal/transform_tracking_repaint_boundary_mixin.dart';

/// Keeps moving glass live; no detached texture capture is involved.
class GlassMotionSync extends SingleChildRenderObjectWidget {
  const GlassMotionSync(
      {required this.motion, required super.child, super.key});
  final Listenable motion;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassMotionSync(motion);
  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderGlassMotionSync renderObject) {
    renderObject.motion = motion;
  }
}

class _RenderGlassMotionSync extends RenderProxyBox {
  _RenderGlassMotionSync(this._motion);
  Listenable _motion;
  set motion(Listenable value) {
    if (identical(value, _motion)) return;
    if (attached) _motion.removeListener(_onMotion);
    _motion = value;
    if (attached) _motion.addListener(_onMotion);
  }

  void _onMotion() {
    if (!attached) return;
    void refresh(RenderObject node) {
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
