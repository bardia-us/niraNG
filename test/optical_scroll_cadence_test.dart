// Isolate the product adapter's repaint scheduling from GPU shader cost.
// This is a logical frame-cadence test, NOT a device FPS benchmark.
// ignore_for_file: implementation_imports
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';

class _Owner extends SingleChildRenderObjectWidget {
  const _Owner(this.link, {required super.child});
  final GeometryRenderLink link;
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOwner(link);
}

class _RenderOwner extends LiquidGlassRenderObject {
  _RenderOwner(GeometryRenderLink link)
    : super(
        link: link,
        settings: const LiquidGlassSettings(),
        devicePixelRatio: 1,
      );
  @override
  bool get isRepaintBoundary => true;
  @override
  Size get desiredMatteSize => size;
  @override
  Matrix4 get matteTransform => getTransformTo(null);
  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) => throw StateError('No optical geometry in the scheduling probe');
}

class _PaintRecorder extends LeafRenderObjectWidget {
  const _PaintRecorder(this.record);
  final VoidCallback record;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRecorder(record);
}

class _RenderRecorder extends RenderBox {
  _RenderRecorder(this.record);
  final VoidCallback record;
  @override
  void performLayout() => size = constraints.biggest;
  @override
  void paint(PaintingContext context, Offset offset) => record();
}

void main() {
  testWidgets(
    'scroll notification repaints independent optical owner in the same logical frame',
    (tester) async {
      final source = OpticalBackdropSource();
      final scroll = ScrollController();
      final link = GeometryRenderLink();
      var paintedOffset = -1.0;
      var paints = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 180,
              height: 360,
              child: Stack(
                children: [
                  OpticalBackdropBoundary(
                    source: source,
                    child: ListView(
                      controller: scroll,
                      itemExtent: 65,
                      children: List.generate(
                        30,
                        (i) => ColoredBox(
                          color: i.isEven
                              ? const Color(0xff0000ff)
                              : const Color(0xffff0000),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    width: 180,
                    height: 64,
                    child: OpticalBackdropCapture(
                      source: source,
                      motion: scroll,
                      child: _Owner(
                        link,
                        child: _PaintRecorder(() {
                          // Keep the real boundary/snapshot/invalidation path. Only expensive
                          // final shader geometry is omitted on the software test backend.
                          source.captureRegion(
                            1,
                            0,
                            const Rect.fromLTWH(0, 0, 180, 96),
                          );
                          paintedOffset = scroll.offset;
                          paints++;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final startPaints = paints;
      final movement = scroll.animateTo(
        300,
        duration: const Duration(seconds: 1),
        curve: Curves.linear,
      );
      var movingFrames = 0;
      var previous = scroll.offset;
      for (var i = 0; i < 122; i++) {
        await tester.pump(const Duration(microseconds: 8333));
        if (scroll.offset != previous) {
          movingFrames++;
          expect(
            paintedOffset,
            scroll.offset,
            reason:
                'The independently cached optical owner must not lag the list',
          );
        }
        previous = scroll.offset;
      }
      await movement;
      expect(movingFrames, greaterThanOrEqualTo(119));
      expect(paints - startPaints, greaterThanOrEqualTo(movingFrames));
      debugPrint(
        'OPTICAL_CADENCE_PROBE movingFrames=$movingFrames ownerPaints=${paints - startPaints}; logical scheduling only',
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      source.dispose();
      link.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
