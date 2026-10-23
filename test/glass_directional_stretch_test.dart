// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/stretch.dart';

void main() {
  for (final drag in [
    const Offset(100, 0),
    const Offset(0, -100),
    const Offset(-100, 100),
    const Offset(100, 100),
  ]) {
    testWidgets('free lens stretch contracts across drag $drag', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RawLiquidStretch(
              key: key,
              stretchPixels: drag,
              child: const SizedBox.square(dimension: 44),
            ),
          ),
        ),
      );
      final render =
          key.currentContext!.findRenderObject()! as RenderRawLiquidStretch;
      final matrix = Matrix4.identity();
      render.applyPaintTransform(render.child!, matrix);
      final origin = MatrixUtils.transformPoint(matrix, Offset.zero);
      Offset mapped(Offset v) => MatrixUtils.transformPoint(matrix, v) - origin;
      final along = drag / drag.distance;
      final across = Offset(-along.dy, along.dx);
      expect(mapped(along).distance, inInclusiveRange(1.01, 1.28));
      expect(mapped(across).distance, inInclusiveRange(.85, .999));
      expect(
        matrix.determinant(),
        lessThanOrEqualTo(1.02),
        reason: 'Diagonal pulling must not inflate the whole lens',
      );
      expect(
        (mapped(along).dx * along.dy - mapped(along).dy * along.dx).abs(),
        lessThan(.001),
      );
    });
  }
}
