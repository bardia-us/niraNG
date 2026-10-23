// Contract of the pinned renderer adapter, without faking GPU frame timings.
// ignore_for_file: implementation_imports
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe(this.oldImage, this.blur, {super.key});
  final ui.Image oldImage;
  final double blur;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ProbeRender(oldImage, blur);
}

class _ProbeRender extends LiquidGlassRenderObject {
  _ProbeRender(ui.Image oldImage, double blur)
    : super(
        link: GeometryRenderLink(),
        settings: LiquidGlassSettings(blur: blur, thickness: 30),
        devicePixelRatio: 1,
        captureImage: oldImage,
      );
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
  ) => throw StateError('Shape-free adapter probe');
}

void main() {
  testWidgets(
    'live header clears captures and shares only pristine blur input without allocating images',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xff442244), BlendMode.src);
      final picture = recorder.endRecording();
      final oldImage = picture.toImageSync(12, 12);
      picture.dispose();
      final source = OpticalBackdropSource(
        sharedBlurSigma: 4.5,
        regionalBlurSigmas: const [4.5, 2.4],
      );
      final motion = ValueNotifier<double>(0);
      final headerKey = GlobalKey();
      final buttonKey = GlobalKey();
      final previous = ui.Image.onCreate;
      var images = 0;
      ui.Image.onCreate = (_) => images++;
      addTearDown(() => ui.Image.onCreate = previous);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ValueListenableBuilder<double>(
              valueListenable: motion,
              builder: (_, value, child) =>
                  Transform.translate(offset: Offset(value, 0), child: child),
              child: LiveGlassViewport(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: OpticalBackdropBoundary(
                          source: source,
                          child: const ColoredBox(color: Color(0xff556677)),
                        ),
                      ),
                      OpticalBackdropCapture(
                        source: source,
                        motion: motion,
                        liveBackdrop: true,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              height: 40,
                              child: _Probe(oldImage, 4.5, key: headerKey),
                            ),
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: _Probe(oldImage, 2.4, key: buttonKey),
                            ),
                          ],
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
      await tester.pumpAndSettle();
      final header =
          headerKey.currentContext!.findRenderObject()! as _ProbeRender;
      final button =
          buttonKey.currentContext!.findRenderObject()! as _ProbeRender;
      expect(header.captureImage, isNull);
      expect(button.captureImage, isNull);
      expect(header.backdropKey, isNotNull);
      expect(button.backdropKey, same(header.backdropKey));
      expect(header.enclosingBackdropPassRect(), isNotNull);
      expect(
        header.combineClearBlur,
        isFalse,
        reason:
            'Each blur must restore pristine input before refraction, not consume the sibling glass',
      );
      header.bindCapturedBackdropForPaint(
        oldImage,
        origin: Offset.zero,
        pixelRatio: 1,
      );
      expect(header.settings.blur, 0);
      header.markNeedsPaint();
      await tester.pump();
      expect(
        header.settings.blur,
        4.5,
        reason: 'Leaving a fade capture restores the original native blur',
      );
      for (final offset in [-80.0, -160.0, 0.0]) {
        motion.value = offset;
        header.markNeedsPaint();
        button.markNeedsPaint();
        await tester.pump();
        final box = source.key.currentContext!.findRenderObject()! as RenderBox;
        expect(
          header.samplingBoundsInScreenSpace,
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
        );
        expect(header.captureImage, isNull);
      }
      expect(
        images,
        0,
        reason:
            'Ordinary header motion must not create raw or atlas backdrop textures',
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      ui.Image.onCreate = previous;
      motion.dispose();
      source.dispose();
      oldImage.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
