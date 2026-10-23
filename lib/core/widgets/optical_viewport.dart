// Adapter to the app's pinned, vendored renderer.
// ignore_for_file: implementation_imports
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';

/// Keeps the native layers independent while excluding system bars from
/// optical sampling. This records bounds only; it never captures a bitmap.
class OpticalViewport extends SingleChildRenderObjectWidget {
  const OpticalViewport({required super.child, super.key});
  @override
  RenderObject createRenderObject(BuildContext context) => _ViewportBounds();
}

class _ViewportBounds extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    void bind(RenderObject node) {
      if (node is RenderOffstage && node.offstage) return;
      if (node is LiquidGlassRenderObject) {
        node.samplingBoundsInScreenSpace = bounds;
        node.combineClearBlur = true;
      }
      node.visitChildren(bind);
    }

    visitChildren(bind);
    super.paint(context, offset);
  }
}
