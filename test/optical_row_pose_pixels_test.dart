import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_row_anchor.dart';

void main() {
  testWidgets(
    'detached control paints the same affine press pose as its anchor',
    (tester) async {
      final link = OpticalRowLink();
      final frame = ValueNotifier<double>(1);
      final boundaryKey = GlobalKey();
      final anchorKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 200,
                height: 120,
                child: ColoredBox(
                  color: const Color(0xff000000),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 80,
                        top: 30,
                        width: 40,
                        height: 40,
                        child: ValueListenableBuilder<double>(
                          valueListenable: frame,
                          builder: (_, value, child) => Transform.translate(
                            offset: Offset(0, (1 - value) * 10),
                            child: Transform.scale(scale: value, child: child),
                          ),
                          child: OpticalRowAnchor(
                            key: anchorKey,
                            link: link,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 80,
                        top: 30,
                        width: 40,
                        height: 40,
                        child: OpticalControlFollow(
                          link: link,
                          enabled: false,
                          child: const ColoredBox(color: Color(0xffff0000)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final scale in [.72, .87, 1.0]) {
        frame.value = scale;
        link.pressFrame(true);
        await tester.pump();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = boundary.toImageSync();
        final pixels = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final anchor =
            anchorKey.currentContext!.findRenderObject()! as RenderBox;
        final expected = MatrixUtils.transformRect(
          anchor.getTransformTo(boundary),
          Offset.zero & anchor.size,
        );
        for (var y = 10; y < 100; y++) {
          for (var x = 50; x < 150; x++) {
            final point = Offset(x + .5, y + .5);
            if (expected.inflate(1).contains(point) &&
                !expected.deflate(1).contains(point)) {
              continue;
            }
            expect(
              pixels.getUint8((y * image.width + x) * 4),
              expected.contains(point) ? 255 : 0,
              reason:
                  'Actual painted menu pixels must follow translation AND scale $scale, not only reported geometry',
            );
          }
        }
        image.dispose();
      }
      link.pressFrame(false);
      await tester.pumpWidget(const SizedBox());
      frame.dispose();
      link.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
