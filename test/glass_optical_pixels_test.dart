import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';

// Actual packaged geometry + final shaders, not AdaptiveGlass's desktop fallback.
Future<ui.Image> _raster(
  ui.FragmentShader shader,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  testWidgets('clear lens keeps the inner face at backdrop scale and lights side bevels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final geometryProgram = await ui.FragmentProgram.fromAsset(
        'packages/liquid_glass_widgets/shaders/liquid_glass_geometry_blended.frag',
      );
      final finalProgram = await ui.FragmentProgram.fromAsset(
        'packages/liquid_glass_widgets/shaders/liquid_glass_render_clear.frag',
      );
      final geo = geometryProgram.fragmentShader();
      // One 152x72 rounded header, at DPR=1; thickness40 / 3.
      for (var i = 0; i < 121; i++) {
        geo.setFloat(i, 0);
      }
      for (final e in <int, double>{
        0: 160,
        1: 80,
        2: 1.24,
        4: 40 / 3,
        6: 1,
        7: 1,
        8: 3,
        9: 80,
        10: 40,
        11: 152,
        12: 72,
        13: 20,
        14: 20,
        120: 1,
      }.entries) {
        geo.setFloat(e.key, e.value);
      }
      final matte = await _raster(geo, 160, 80);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (var y = 0; y < 80; y++) {
        canvas.drawRect(
          ui.Rect.fromLTWH(0, y.toDouble(), 160, 1),
          ui.Paint()..color = ui.Color.fromARGB(255, y * 3, y * 3, y * 3),
        );
      }
      final picture = recorder.endRecording();
      final backdrop = await picture.toImage(160, 80);
      picture.dispose();
      final shader = finalProgram.fragmentShader();
      for (var i = 0; i < 53; i++) {
        shader.setFloat(i, 0);
      }
      for (final e in <int, double>{
        0: 160,
        1: 80,
        4: 160,
        5: 80,
        10: 1.24,
        12: 40 / 3,
        13: 1,
        16: 1,
        18: -1,
        30: 1 / 3,
        33: 1,
        40: 1,
        44: 1,
        49: 1,
        52: 1,
      }.entries) {
        shader.setFloat(e.key, e.value);
      }
      shader.setImageSampler(0, backdrop);
      shader.setImageSampler(1, matte);
      final plain = await _raster(shader, 160, 80);
      final plainBytes = (await plain.toByteData())!;
      final sourceBytes = (await backdrop.toByteData())!;
      int red(dynamic bytes, int x, int y) => bytes.getUint8((y * 160 + x) * 4);
      // Three points span an icon-sized patch, just inside the bevel's body side.
      for (final y in [12, 13, 14]) {
        expect(
          red(plainBytes, 80, y),
          closeTo(red(sourceBytes, 80, y), 1),
          reason:
              'Inner header content must not be rescaled by the broad lens slope at y=$y',
        );
      }
      expect(
        (red(plainBytes, 80, 5) - red(sourceBytes, 80, 5)).abs(),
        greaterThan(10),
        reason:
            'Outer bevel must retain real lens refraction, not turn into a plain blur',
      );
      // On a black backdrop, side lighting must be present but remain subtle.
      final blackRecorder = ui.PictureRecorder();
      ui.Canvas(
        blackRecorder,
      ).drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
      final blackPicture = blackRecorder.endRecording();
      final black = await blackPicture.toImage(160, 80);
      blackPicture.dispose();
      shader.setImageSampler(0, black);
      shader.setFloat(38, 1.3);
      final lit = await _raster(shader, 160, 80);
      final bytes = (await lit.toByteData())!;
      expect(
        [
          for (var x = 3; x <= 7; x++) red(bytes, x, 40),
        ].reduce((a, b) => a > b ? a : b),
        inInclusiveRange(4, 45),
        reason: 'Side bevel needs a soft reflective lobe, not a thick outline',
      );
      expect(
        red(bytes, 80, 40),
        0,
        reason: 'No white wash over the glass face',
      );
      final triggerMaterial = liquidServerHeaderSettings(
        ui.Brightness.light,
        trigger: true,
      );
      shader.setFloat(38, triggerMaterial.rimLight);
      final restrained = await _raster(shader, 160, 80);
      final restrainedBytes = (await restrained.toByteData())!;
      final oldSpread = [
        for (var x = 3; x <= 16; x++) red(bytes, x, 40),
      ].reduce((a, b) => a + b);
      final newSpread = [
        for (var x = 3; x <= 16; x++) red(restrainedBytes, x, 40),
      ].reduce((a, b) => a + b);
      expect(
        newSpread,
        lessThan(oldSpread * .85),
        reason:
            'Reduce the broad lighting halo, not lens refraction or source blur',
      );
      expect(
        newSpread,
        greaterThan(8),
        reason: 'The physical reflective rim must remain visible',
      );
      expect(red(restrainedBytes, 80, 40), 0);
      restrained.dispose();
      // The new header recipe must not replace the optical material with blur.
      expect(triggerMaterial.blur, 2.4);
      expect(triggerMaterial.thickness, 40);
      expect(triggerMaterial.refractiveIndex, 1.24);
      shader.setFloat(38, 1.3);
      // A packed texture must not change touch-glow radius or sample its
      // neighbour. Bottom slot is black; the upper, unrelated slot is red.
      shader.setFloat(14, 1);
      shader.setFloat(34, 80);
      shader.setFloat(35, 10);
      shader.setFloat(36, 1);
      shader.setFloat(45, 1.5);
      shader.setFloat(46, 1.5);
      shader.setFloat(47, 158.5);
      shader.setFloat(48, 78.5);
      final independentTouch = await _raster(shader, 160, 80);
      final atlasRecorder = ui.PictureRecorder();
      final atlasCanvas = ui.Canvas(atlasRecorder)
        ..drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
      atlasCanvas.drawImage(black, const ui.Offset(0, 80), ui.Paint());
      final atlasPicture = atlasRecorder.endRecording();
      final atlas = await atlasPicture.toImage(160, 160);
      atlasPicture.dispose();
      shader.setImageSampler(0, atlas);
      shader.setFloat(1, 160);
      shader.setFloat(27, 80);
      shader.setFloat(46, 81.5);
      shader.setFloat(48, 158.5);
      final packedTouch = await _raster(shader, 160, 80);
      final independentTouchBytes = (await independentTouch.toByteData())!;
      final packedTouchBytes = (await packedTouch.toByteData())!;
      var maxAtlasError = 0;
      for (var i = 0; i < independentTouchBytes.lengthInBytes; i++) {
        final error =
            (independentTouchBytes.getUint8(i) - packedTouchBytes.getUint8(i))
                .abs();
        if (error > maxAtlasError) maxAtlasError = error;
      }
      expect(
        maxAtlasError,
        lessThanOrEqualTo(2),
        reason:
            'Packed slot must preserve refraction, neighbour clamp and touch-light radius',
      );
      for (final image in [independentTouch, atlas, packedTouch]) {
        image.dispose();
      }
      for (final image in [matte, backdrop, plain, black, lit]) {
        image.dispose();
      }
      geo.dispose();
      shader.dispose();
    });
  });
}
