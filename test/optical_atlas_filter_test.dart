import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';

class _BackdropPattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffe8e4f0),
    );
    for (var y = 0.0; y < size.height; y += 9) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 3),
        Paint()
          ..color = y % 18 == 0
              ? const Color(0xff142536)
              : const Color(0x805500cc),
      );
    }
    canvas.drawCircle(
      const Offset(30, 27),
      17,
      Paint()..color = const Color(0xffffaa00),
    );
    canvas.drawRect(
      const Rect.fromLTWH(120, 110, 40, 30),
      Paint()..color = const Color(0xff1166bb),
    );
  }

  @override
  bool shouldRepaint(covariant _BackdropPattern oldDelegate) => false;
}

void main() {
  testWidgets('atlas refreshes both recipes before the next source paint', (
    tester,
  ) async {
    final source = OpticalBackdropSource(
      sharedBlurSigma: 4.5,
      regionalBlurSigmas: const [4.5, 2.4],
    );
    final colorKey = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: SizedBox.square(
          dimension: 80,
          child: OpticalBackdropBoundary(
            source: source,
            child: DecoratedBox(
              key: colorKey,
              decoration: const BoxDecoration(color: Color(0xff0000ff)),
            ),
          ),
        ),
      ),
    );
    final first = source.captureAtlasRegion(
      1,
      4.5,
      const Rect.fromLTWH(0, 0, 80, 80),
    )!;
    final box =
        colorKey.currentContext!.findRenderObject()! as RenderDecoratedBox;
    box.decoration = const BoxDecoration(color: Color(0xffff0000));
    source.invalidate();
    for (final sigma in [4.5, 2.4]) {
      final fresh = source.captureAtlasRegion(
        1,
        sigma,
        const Rect.fromLTWH(0, 0, 80, 80),
      )!;
      expect(fresh.image, isNot(same(first.image)));
      final bytes = (await tester.runAsync(() => fresh.image.toByteData()))!;
      final at =
          ((fresh.sampleBounds.top.toInt() + 40) * fresh.image.width + 40) * 4;
      expect(bytes.getUint8(at), 255);
      expect(bytes.getUint8(at + 2), 0);
    }
    expect(
      source.captureAtlasRegion(1, 1.3, const Rect.fromLTWH(0, 0, 80, 80)),
      isNull,
      reason: 'Animated intermediate blur uses the unchanged independent path',
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('atlas filtering retains translucent source-edge alpha', (
    tester,
  ) async {
    final source = OpticalBackdropSource(
      sharedBlurSigma: 4.5,
      regionalBlurSigmas: const [4.5, 2.4],
    );
    await tester.pumpWidget(
      Center(
        child: SizedBox.square(
          dimension: 40,
          child: OpticalBackdropBoundary(
            source: source,
            child: const ColoredBox(color: Color(0x804488cc)),
          ),
        ),
      ),
    );
    for (final sigma in [4.5, 2.4]) {
      final sample = source.captureAtlasRegion(
        1,
        sigma,
        const Rect.fromLTWH(0, 0, 40, 40),
      )!;
      final image = sample.image;
      final bytes = (await tester.runAsync(() => image.toByteData()))!;
      for (
        var i = sample.sampleBounds.top.toInt() * image.width * 4;
        i < sample.sampleBounds.bottom.toInt() * image.width * 4;
        i += 4
      ) {
        expect(bytes.getUint8(i), closeTo(34, 1));
        expect(bytes.getUint8(i + 1), closeTo(68, 1));
        expect(bytes.getUint8(i + 2), closeTo(102, 1));
        expect(bytes.getUint8(i + 3), 128);
      }
    }
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('two header blur recipes share one atlas and one raw image', (
    tester,
  ) async {
    final source = OpticalBackdropSource(
      sharedBlurSigma: 4.5,
      regionalBlurSigmas: const [4.5, 2.4],
    );
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 160,
          height: 140,
          child: OpticalBackdropBoundary(
            source: source,
            child: CustomPaint(painter: _BackdropPattern()),
          ),
        ),
      ),
    );
    final previous = ui.Image.onCreate;
    var created = 0;
    ui.Image.onCreate = (image) {
      previous?.call(image);
      created++;
    };
    final images = <ui.Image>[];
    try {
      for (final sigma in [4.5, 2.4]) {
        images.add(
          source
              .captureAtlasRegion(
                1,
                sigma,
                const Rect.fromLTWH(16, 12, 80, 64),
              )!
              .image,
        );
      }
    } finally {
      ui.Image.onCreate = previous;
    }
    expect(
      created,
      2,
      reason:
          'One shared raw image and one packed Gaussian output; no duplicate scene replay',
    );
    expect(images[0], same(images[1]));
    expect(images[0].width, 80);
    expect(images[0].height, 128);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('atlas Gaussian preserves pixels at edges and fractional scale', (
    tester,
  ) async {
    final source = OpticalBackdropSource(
      sharedBlurSigma: 4.5,
      regionalBlurSigmas: const [4.5, 2.4],
    );
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 160,
          height: 140,
          child: OpticalBackdropBoundary(
            source: source,
            child: CustomPaint(painter: _BackdropPattern()),
          ),
        ),
      ),
    );
    for (final ratio in [1.0, .75]) {
      for (final sigma in [4.5, 2.4]) {
        // The full path is the existing independent raw-image + Gaussian path.
        final full = source.capture(ratio, sigma)!;
        final fullBytes = (await tester.runAsync(() => full.toByteData()))!;
        for (final region in [
          const Rect.fromLTWH(0, 0, 60, 52),
          const Rect.fromLTWH(36, 32, 60, 52),
          const Rect.fromLTWH(100, 88, 60, 52),
        ]) {
          final captured = source.captureAtlasRegion(ratio, sigma, region)!;
          final bytes = (await tester.runAsync(
            () => captured.image.toByteData(),
          ))!;
          final x0 = (region.left * ratio).round();
          final y0 = (region.top * ratio).round();
          var maxError = 0;
          for (var y = 0; y < captured.sampleBounds.height; y++) {
            for (var x = 0; x < captured.sampleBounds.width; x++) {
              for (var c = 0; c < 4; c++) {
                final error =
                    (bytes.getUint8(
                              ((y + captured.sampleBounds.top.toInt()) *
                                              captured.image.width +
                                          x) *
                                      4 +
                                  c,
                            ) -
                            fullBytes.getUint8(
                              ((y + y0) * full.width + x + x0) * 4 + c,
                            ))
                        .abs();
                if (error > maxError) maxError = error;
              }
            }
          }
          expect(
            maxError,
            lessThanOrEqualTo(2),
            reason: 'Same Gaussian sigma=$sigma ratio=$ratio region=$region',
          );
          expect(
            captured.origin + captured.sampleBounds.topLeft / ratio,
            source.origin + region.topLeft,
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    expect(tester.takeException(), isNull);
  });
}
