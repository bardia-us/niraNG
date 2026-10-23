import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _draw(ui.FragmentShader shader, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(width, height);
  picture.dispose();
  return result;
}

void main() {
  testWidgets('clear optical edge samples the lens all the way to opaque coverage', (
    tester,
  ) async {
    // A red annulus surrounds a blue interior. A plain/exterior-sampling strip
    // remains red; a continuous inward lens reads blue up to its covered edge.
    // Exercises the packaged geometry+render shaders, not a border mock.
    await tester.runAsync(() async {
      final geometry = await ui.FragmentProgram.fromAsset(
        'packages/liquid_glass_widgets/shaders/liquid_glass_geometry_blended.frag',
      );
      final render = await ui.FragmentProgram.fromAsset(
        'packages/liquid_glass_widgets/shaders/liquid_glass_render_clear.frag',
      );
      for (final dpr in [1.0, 2.625, 3.0]) {
        for (final pill in [false, true]) {
          final width = ((pill ? 180 : 72) * dpr).ceil();
          final height = (72 * dpr).ceil();
          final center = ui.Offset(width / 2 + .5, height / 2 + .5);
          final size = ui.Size((pill ? 152 : 44) * dpr, 44 * dpr);
          final rect = ui.Rect.fromCenter(
            center: center,
            width: size.width,
            height: size.height,
          );
          final geo = geometry.fragmentShader();
          final shader = render.fragmentShader();
          final images = <ui.Image>[];
          try {
            for (var i = 0; i < 121; i++) {
              geo.setFloat(i, 0);
            }
            for (final e in <int, double>{
              0: width.toDouble(),
              1: height.toDouble(),
              2: 1.24,
              4: 40 * dpr / 3,
              6: 1,
              7: dpr,
              8: pill ? 3 : 2,
              9: center.dx,
              10: center.dy,
              11: size.width,
              12: size.height,
              13: pill ? 22 * dpr : 0,
              14: pill ? 22 * dpr : 0,
              120: 1,
            }.entries) {
              geo.setFloat(e.key, e.value);
            }
            final matte = await _draw(geo, width, height);
            images.add(matte);
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder)
              ..drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
            final blue = ui.Paint()..color = const ui.Color(0xff0000ff);
            if (pill) {
              canvas.drawRRect(
                ui.RRect.fromRectAndRadius(
                  rect.deflate(6 * dpr),
                  ui.Radius.circular(16 * dpr),
                ),
                blue,
              );
            } else {
              canvas.drawOval(rect.deflate(6 * dpr), blue);
            }
            final picture = recorder.endRecording();
            final backdrop = await picture.toImage(width, height);
            picture.dispose();
            images.add(backdrop);
            for (var i = 0; i < 53; i++) {
              shader.setFloat(i, 0);
            }
            for (final e in <int, double>{
              0: width.toDouble(),
              1: height.toDouble(),
              4: width.toDouble(),
              5: height.toDouble(),
              10: 1.24,
              12: 40 * dpr / 3,
              13: 1,
              16: 1,
              18: -1,
              30: dpr / 3,
              33: 1,
              37: .30,
              39: .12,
              40: 1,
              44: 1,
              49: 1,
              52: 1,
            }.entries) {
              shader.setFloat(e.key, e.value);
            }
            shader.setImageSampler(0, backdrop);
            shader.setImageSampler(1, matte);
            final output = await _draw(shader, width, height);
            images.add(output);
            final coverage = (await matte.toByteData())!;
            final pixels = (await output.toByteData())!;
            final directions = pill
                ? [0.0, math.pi / 2, math.pi, math.pi * 1.5]
                : [for (var i = 0; i < 8; i++) i * math.pi / 4];
            for (final angle in directions) {
              final radial = pill && (angle == 0 || angle == math.pi)
                  ? size.width / 2
                  : size.height / 2;
              var sampled = 0;
              final visited = <int>{};
              for (var depth = -3.0; depth <= 2 * dpr; depth += .25) {
                final x = (center.dx + math.cos(angle) * (radial - depth))
                    .floor();
                final y = (center.dy + math.sin(angle) * (radial - depth))
                    .floor();
                final offset = (y * width + x) * 4;
                if (!visited.add(offset) ||
                    coverage.getUint8(offset + 3) < 254) {
                  continue;
                }
                sampled++;
                expect(
                  pixels.getUint8(offset + 2),
                  greaterThan(190),
                  reason:
                      'Unrefracted annulus at dpr=$dpr pill=$pill angle=$angle depth=$depth',
                );
              }
              expect(sampled, greaterThan(0));
            }
            // The optical fix must not turn the flat central face into a lens.
            // Probe the flat face, not the ellipse SDF's undefined gradient at
            // its exact mathematical centre.
            final centerOffset =
                (center.dy.floor() * width + (center.dx + 2 * dpr).floor()) * 4;
            expect(pixels.getUint8(centerOffset + 2), greaterThan(250));
          } finally {
            for (final image in images) {
              image.dispose();
            }
            geo.dispose();
            shader.dispose();
          }
        }
      }
    });
  });
}
