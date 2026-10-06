import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';

// Exercise the compositor contract without substituting a fake geometry image:
// on a cold frame the real base render object has no image yet.
class _ColdGlass extends SingleChildRenderObjectWidget {
  const _ColdGlass({required super.key})
    : super(child: const SizedBox(width: 120, height: 46));

  @override
  _ColdGlassRender createRenderObject(BuildContext context) =>
      _ColdGlassRender();
}

class _ColdGlassRender extends LiquidGlassRenderObject {
  _ColdGlassRender()
    : super(
        link: GeometryRenderLink(),
        settings: const LiquidGlassSettings(),
        devicePixelRatio: 3,
      );
  @override
  Size get desiredMatteSize => const Size(400, 800);
  @override
  Matrix4 get matteTransform => getTransformTo(null);
  bool get hasGeometry => geometryImage != null;
  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) {}
}

void main() {
  testWidgets(
    'cold nested glass reserves compositor layers before its matte exists',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(child: _ColdGlass(key: key)),
          ),
        ),
      );
      final render =
          key.currentContext!.findRenderObject()! as _ColdGlassRender;
      expect(render.hasGeometry, isFalse);
      expect(render.needsCompositing, isTrue);
      // A settings update / another idle frame must not depend on user scrolling.
      render.settings = render.settings.copyWith(visibility: .5);
      await tester.pump();
      expect(render.needsCompositing, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
