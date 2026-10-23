import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A live layout reference, not a last-frame Flow/FollowerLayer transform.
class OpticalRowLink extends ChangeNotifier {
  RenderBox? box;
  bool _pressTransformActive = false;

  /// Press/release animation changes the row pose without scrolling or reorder.
  void pressFrame(bool active) {
    _pressTransformActive = active;
    notifyListeners();
  }
}

class OpticalRowAnchor extends SingleChildRenderObjectWidget {
  const OpticalRowAnchor({required this.link, required super.child, super.key});
  final OpticalRowLink link;
  @override
  RenderObject createRenderObject(BuildContext context) => _RowAnchor(link);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _RowAnchor).link = link;
}

class _RowAnchor extends RenderProxyBox {
  _RowAnchor(this._link);
  OpticalRowLink _link;
  set link(OpticalRowLink next) {
    if (identical(_link.box, this)) _link.box = null;
    _link = next;
    if (attached) _link.box = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link.box = this;
  }

  @override
  void detach() {
    if (identical(_link.box, this)) _link.box = null;
    super.detach();
  }
}

/// Fixed-position fast path during normal scrolling; live row pose during
/// press/release and reorder. Paint, geometry and hit tests use the same matrix.
class OpticalControlFollow extends SingleChildRenderObjectWidget {
  const OpticalControlFollow({
    required this.link,
    required this.enabled,
    this.motion,
    required super.child,
    super.key,
  });
  final OpticalRowLink link;
  final bool enabled;
  final Listenable? motion;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ControlFollow(link, enabled, motion);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _ControlFollow).update(link, enabled, motion);
  }
}

class _ControlFollow extends RenderProxyBox {
  _ControlFollow(this.link, this.enabled, this.motion);
  OpticalRowLink link;
  bool enabled;
  Listenable? motion;
  void _moved() => markNeedsPaint();
  void update(
    OpticalRowLink nextLink,
    bool nextEnabled,
    Listenable? nextMotion,
  ) {
    if (attached) link.removeListener(_moved);
    if (attached && enabled) motion?.removeListener(_moved);
    link = nextLink;
    enabled = nextEnabled;
    motion = nextMotion;
    if (attached) link.addListener(_moved);
    if (attached && enabled) motion?.addListener(_moved);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    link.addListener(_moved);
    if (enabled) motion?.addListener(_moved);
  }

  @override
  void detach() {
    link.removeListener(_moved);
    if (enabled) motion?.removeListener(_moved);
    super.detach();
  }

  Matrix4 get _pose {
    final anchor = link.box;
    if ((!enabled && !link._pressTransformActive) ||
        anchor == null ||
        !anchor.attached ||
        !anchor.hasSize ||
        !hasSize) {
      return Matrix4.identity();
    }
    final pose = Matrix4.tryInvert(getTransformTo(null));
    if (pose == null) return Matrix4.identity();
    return pose
      ..multiply(anchor.getTransformTo(null))
      ..translateByDouble(
        (anchor.size.width - size.width) / 2,
        (anchor.size.height - size.height) / 2,
        0,
        1,
      );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_pose);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _pose,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _pose,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );
}
