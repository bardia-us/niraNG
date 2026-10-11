import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/renderer/glass_backdrop_group_boundary.dart';

class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe({super.key});
  @override
  _PaintBox createRenderObject(BuildContext context) => _PaintBox();
}

class _PaintBox extends RenderBox {
  int paints = 0;
  @override
  bool get isRepaintBoundary => true;
  @override
  void performLayout() => size = constraints.constrain(const Size(30, 30));
  @override
  void paint(PaintingContext context, Offset offset) => paints++;
}

void main() {
  testWidgets(
    'steady shared backdrop does not repaint every member on row churn',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GlassBackdropGroupBoundary(
            child: Row(
              children: [
                _PaintProbe(key: ValueKey(1)),
                _PaintProbe(key: ValueKey(2)),
                _PaintProbe(key: ValueKey(3)),
              ],
            ),
          ),
        ),
      );
      final group = tester.renderObject<RenderGlassBackdropGroupBoundary>(
        find.byType(GlassBackdropGroupBoundary),
      );
      final first = tester.renderObject<_PaintBox>(
        find.byKey(const ValueKey(1)),
      );
      final second = tester.renderObject<_PaintBox>(
        find.byKey(const ValueKey(2)),
      );
      final third = tester.renderObject<_PaintBox>(
        find.byKey(const ValueKey(3)),
      );
      group.join(first);
      group.join(second);
      await tester.pumpAndSettle();
      final a = first.paints;
      final b = second.paints;
      group.join(third);
      await tester.pumpAndSettle();
      expect(first.paints, a, reason: '2 -> 3 leaves sharing enabled');
      expect(second.paints, b);
      group.leave(third);
      await tester.pumpAndSettle();
      expect(first.paints, a, reason: '3 -> 2 leaves sharing enabled');
      group.leave(second);
      await tester.pumpAndSettle();
      expect(
        first.paints,
        greaterThan(a),
        reason: '2 -> 1 must remove sharing',
      );
      expect(group.memberCount, 1);
    },
  );
}
