import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:liquid_glass_widgets/src/engine/internal/transform_tracking_repaint_boundary_mixin.dart';

class _OpticalProbe extends SingleChildRenderObjectWidget {
  const _OpticalProbe()
    : super(child: const SizedBox.square(dimension: 40));
  @override
  _OpticalRender createRenderObject(BuildContext context) => _OpticalRender();
}

class _OpticalRender extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  int paints = 0;
  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    super.paint(context, offset);
  }

  @override
  void onTransformChanged() => markNeedsPaint();
}

void main() {
  testWidgets(
    'new glass settles its first scene without a user gesture, then stays idle',
    (tester) async {
      final motion = ValueNotifier<int>(0);
      addTearDown(motion.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: glass.GlassMotionSync(
              motion: motion,
              child: const _OpticalProbe(),
            ),
          ),
        ),
      );
      final render = tester.renderObject<_OpticalRender>(
        find.byType(_OpticalProbe),
      );
      await tester.pumpAndSettle();
      expect(
        render.paints,
        greaterThanOrEqualTo(2),
        reason:
            'The settled compositor transform must be painted before interaction',
      );
      final settled = render.paints;
      await tester.pump(const Duration(seconds: 1));
      expect(
        render.paints,
        settled,
        reason: 'Startup priming is not an animation ticker',
      );
      motion.value++;
      await tester.pumpAndSettle();
      expect(render.paints, greaterThan(settled));
      expect(tester.takeException(), isNull);
    },
  );
}
