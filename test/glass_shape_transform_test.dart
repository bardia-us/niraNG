import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_blend_group.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_shape.dart';

class _Shape extends SingleChildRenderObjectWidget {
  const _Shape(this.link) : super(child: const SizedBox.square(dimension: 40));
  final GlassGroupLink link;
  @override
  RenderObject createRenderObject(BuildContext context) => RenderLiquidGlass(
    shape: const LiquidOval(),
    glassContainsChild: true,
    blendGroupLink: link,
  );
}

class _Owner extends SingleChildRenderObjectWidget {
  const _Owner({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOwner();
}

class _RenderOwner extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) =>
      (child! as RenderLiquidGlass).paintFromLayer(
        context,
        Matrix4.identity(),
        offset,
      );
}

void main() {
  for (final owned in [false, true]) {
    testWidgets(
      'a painted shape notifies geometry on transform changes (paintFromLayer=$owned)',
      (tester) async {
        final link = GlassGroupLink();
        final offset = ValueNotifier<double>(0);
        var notifications = 0;
        link.onShapeTransformChanged = (_) => notifications++;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AnimatedBuilder(
                animation: offset,
                child: owned ? _Owner(child: _Shape(link)) : _Shape(link),
                builder: (_, child) => Transform.translate(
                  offset: Offset(offset.value, 0),
                  child: child,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        notifications = 0;
        offset.value = 25;
        await tester.pump();
        await tester.pump();
        expect(
          notifications,
          greaterThan(0),
          reason:
              'Painting the glyph/shape is not equivalent to rebuilding the shared optical matte',
        );
        await tester.pumpWidget(const SizedBox());
        offset.dispose();
        link.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
