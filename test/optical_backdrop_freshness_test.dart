import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';

class _RegionalSource extends OpticalBackdropSource {
  int fullCaptureRequests = 0;

  @override
  ui.Image? capture(double ratio, double sigma) {
    fullCaptureRequests++;
    return super.capture(ratio, sigma);
  }
}

void main() {
  testWidgets(
    'shared regional input preserves both blur recipes and freshness',
    (tester) async {
      final source = OpticalBackdropSource(sharedBlurSigma: 4.5);
      final colorKey = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 160,
            height: 140,
            child: OpticalBackdropBoundary(
              source: source,
              child: DecoratedBox(
                key: colorKey,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff2255aa), Color(0xffcc7711)],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final ratio in [1.0, .75]) {
        for (final sigma in [4.5, 2.4]) {
          const rect = Rect.fromLTWH(24, 20, 80, 64);
          final regional = source.captureRegion(ratio, sigma, rect)!.$1;
          final full = source.capture(ratio, sigma)!;
          final a = (await tester.runAsync(() => regional.toByteData()))!;
          final b = (await tester.runAsync(() => full.toByteData()))!;
          final x0 = (rect.left * ratio).round();
          final y0 = (rect.top * ratio).round();
          for (var y = 0; y < regional.height; y += 5) {
            for (var x = 0; x < regional.width; x += 5) {
              for (var c = 0; c < 4; c++) {
                expect(
                  a.getUint8((y * regional.width + x) * 4 + c),
                  closeTo(
                    b.getUint8(((y + y0) * full.width + x + x0) * 4 + c),
                    1,
                  ),
                  reason: 'Shared input must preserve sigma=$sigma at $ratio',
                );
              }
            }
          }
        }
      }
      final old = [
        for (final sigma in [4.5, 2.4])
          source
              .captureRegion(1, sigma, const Rect.fromLTWH(24, 20, 80, 64))!
              .$1,
      ];
      final box =
          colorKey.currentContext!.findRenderObject()! as RenderDecoratedBox;
      box.decoration = const BoxDecoration(color: Color(0xffff0000));
      source.invalidate();
      for (var i = 0; i < 2; i++) {
        final image = source
            .captureRegion(
              1,
              [4.5, 2.4][i],
              const Rect.fromLTWH(24, 20, 80, 64),
            )!
            .$1;
        expect(image, isNot(same(old[i])));
        final bytes = (await tester.runAsync(() => image.toByteData()))!;
        expect(bytes.getUint8((32 * 80 + 40) * 4), 255);
        expect(bytes.getUint8((32 * 80 + 40) * 4 + 2), 0);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );
  testWidgets(
    'unblurred regional input uses one snapshot without a zero blur copy',
    (tester) async {
      final source = OpticalBackdropSource();
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: 120,
            height: 100,
            child: OpticalBackdropBoundary(
              source: source,
              child: const ColoredBox(color: Color(0x804488cc)),
            ),
          ),
        ),
      );
      final previous = ui.Image.onCreate;
      var allocations = 0;
      ui.Image.onCreate = (_) => allocations++;
      late (ui.Image, Offset) captured;
      try {
        captured = source.captureRegion(
          .75,
          0,
          const Rect.fromLTWH(20, 16, 48, 40),
        )!;
      } finally {
        ui.Image.onCreate = previous;
      }
      expect(
        allocations,
        1,
        reason: 'No Gaussian pass is needed for the raw underlay',
      );
      expect(captured.$1.width, 36);
      expect(captured.$1.height, 30);
      expect(captured.$2, source.origin + const Offset(20, 16));
      final pixels = (await tester.runAsync(() => captured.$1.toByteData()))!;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        expect(pixels.getUint8(i), closeTo(34, 1));
        expect(pixels.getUint8(i + 1), closeTo(68, 1));
        expect(pixels.getUint8(i + 2), closeTo(102, 1));
        expect(pixels.getUint8(i + 3), 128);
      }
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );
  testWidgets('regional capture respects the intermediate underlay boundary', (
    tester,
  ) async {
    final base = OpticalBackdropSource();
    final middle = OpticalBackdropSource(underlay: base);
    final front = OpticalBackdropSource(underlay: middle);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 160,
            height: 140,
            child: Stack(
              children: [
                Positioned.fill(
                  child: OpticalBackdropBoundary(
                    source: base,
                    child: const ColoredBox(color: Color(0xffff0000)),
                  ),
                ),
                Positioned(
                  left: 40,
                  top: 0,
                  width: 80,
                  height: 140,
                  child: OpticalBackdropBoundary(
                    source: middle,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: OpticalBackdropBoundary(
                    source: front,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final image = front
        .captureRegion(1, 0, const Rect.fromLTWH(0, 0, 160, 140))!
        .$1;
    final bytes = (await tester.runAsync(() => image.toByteData()))!;
    expect(
      bytes.getUint8((70 * 160 + 20) * 4 + 3),
      0,
      reason: 'A narrow intermediate source must still clip its own underlay',
    );
    expect(bytes.getUint8((70 * 160 + 80) * 4), 255);
    await tester.pumpWidget(const SizedBox());
    front.dispose();
    middle.dispose();
    base.dispose();
  });
  testWidgets('regional underlay preserves pixels across recipes and repaint', (
    tester,
  ) async {
    final base = _RegionalSource();
    final front = OpticalBackdropSource(underlay: base);
    final baseKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 160,
            height: 140,
            child: Stack(
              children: [
                Positioned.fill(
                  child: OpticalBackdropBoundary(
                    source: base,
                    child: DecoratedBox(
                      key: baseKey,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xff2255aa), Color(0xffcc7711)],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 15,
                  width: 120,
                  height: 110,
                  child: OpticalBackdropBoundary(
                    source: front,
                    child: const ColoredBox(color: Color(0x5533aa55)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (final ratio in [1.0, .75]) {
      for (final rect in [
        const Rect.fromLTWH(16, 12, 64, 60),
        const Rect.fromLTWH(0, 0, 48, 36),
        const Rect.fromLTWH(72, 72, 48, 36),
      ]) {
        final regional = front.captureRegion(ratio, 2, rect)!;
        final full = front.capture(ratio, 2)!;
        final a = (await tester.runAsync(() => regional.$1.toByteData()))!;
        final b = (await tester.runAsync(() => full.toByteData()))!;
        final x0 = (rect.left * ratio).round(), y0 = (rect.top * ratio).round();
        for (var y = 0; y < regional.$1.height; y += 5) {
          for (var x = 0; x < regional.$1.width; x += 5) {
            for (var c = 0; c < 4; c++) {
              expect(
                a.getUint8((y * regional.$1.width + x) * 4 + c),
                closeTo(
                  b.getUint8(((y + y0) * full.width + x + x0) * 4 + c),
                  1,
                ),
                reason: 'Pixel equivalence at ratio=$ratio, rect=$rect',
              );
            }
          }
        }
      }
    }
    await tester
        .pump(); // Also exercise the ordinary scene after repeated capture.
    final baseBox =
        baseKey.currentContext!.findRenderObject()! as RenderDecoratedBox;
    baseBox.decoration = const BoxDecoration(color: Color(0xffff0000));
    base.invalidate();
    front.invalidate();
    final updated = front
        .captureRegion(1, 0, const Rect.fromLTWH(0, 0, 120, 110))!
        .$1;
    final fresh = (await tester.runAsync(() => updated.toByteData()))!;
    expect(fresh.getUint8((55 * 120 + 60) * 4), closeTo(187, 1));
    expect(fresh.getUint8((55 * 120 + 60) * 4 + 1), closeTo(57, 1));
    await tester.pump();
    expect(
      front.captureRegion(1, 0, const Rect.fromLTWH(0, 0, 120, 110))!.$1,
      same(updated),
    );
    await tester.pumpWidget(const SizedBox());
    front.dispose();
    base.dispose();
  });
  testWidgets(
    'regional blur matches full backdrop pixels without full-page allocation',
    (tester) async {
      final source = _RegionalSource();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 140,
              child: OpticalBackdropBoundary(
                source: source,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xff2255aa), Color(0xffcc7711)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final region = source.captureRegion(
        1,
        2,
        const Rect.fromLTWH(40, 40, 60, 50),
      )!;
      expect(
        source.fullCaptureRequests,
        0,
        reason:
            'A first regional sample must not construct a full-page raw snapshot',
      );
      final originalOrigin = source.origin;
      final full = source.capture(1, 2)!;
      expect(region.$1.width, 60);
      expect(region.$1.height, 50);
      expect(region.$2, originalOrigin + const Offset(40, 40));
      final fullBytes = (await tester.runAsync(() => full.toByteData()))!;
      final regionBytes = (await tester.runAsync(
        () => region.$1.toByteData(),
      ))!;
      for (var y = 0; y < 50; y += 7) {
        for (var x = 0; x < 60; x += 7) {
          for (var c = 0; c < 4; c++) {
            expect(
              regionBytes.getUint8((y * 60 + x) * 4 + c),
              closeTo(fullBytes.getUint8(((y + 40) * 160 + x + 40) * 4 + c), 1),
            );
          }
        }
      }
      expect(
        source.captureRegion(1, 2, const Rect.fromLTWH(40, 40, 60, 50))!.$1,
        same(region.$1),
      );
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );
  testWidgets('retained page motion updates origin without recapturing pixels', (
    tester,
  ) async {
    final source = OpticalBackdropSource();
    final motion = ValueNotifier(Offset.zero);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: AnimatedBuilder(
            animation: motion,
            child: SizedBox.square(
              dimension: 40,
              child: OpticalBackdropBoundary(
                source: source,
                child: const ColoredBox(color: Color(0xff3377aa)),
              ),
            ),
            builder: (context, child) =>
                Transform.translate(offset: motion.value, child: child),
          ),
        ),
      ),
    );
    final image = source.capture(1, 0)!;
    final origin = source.origin;
    // PageView retains the source boundary's local display list while its
    // ancestor translates. No scroll listener/tap invalidates that image.
    for (final offset in [
      const Offset(-160, 0),
      const Offset(80, 0),
      Offset.zero,
    ]) {
      motion.value = offset;
      await tester.pump();
      expect(source.capture(1, 0), same(image));
      expect(
        source.origin,
        origin + offset,
        reason:
            'Cached image pixels are local; their live screen origin is not cached',
      );
    }
    await tester.pumpWidget(const SizedBox());
    motion.dispose();
    source.dispose();
  });
  testWidgets('a pending backdrop paint is consumed before optical sampling', (
    tester,
  ) async {
    final source = OpticalBackdropSource();
    final colorKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 40,
            child: OpticalBackdropBoundary(
              source: source,
              child: DecoratedBox(
                key: colorKey,
                decoration: const BoxDecoration(color: Color(0xff0000ff)),
              ),
            ),
          ),
        ),
      ),
    );
    final oldImage = source.capture(1, 0)!;
    final box =
        colorKey.currentContext!.findRenderObject()! as RenderDecoratedBox;
    box.decoration = const BoxDecoration(color: Color(0xffff0000));
    source.invalidate();
    // Same frame: a deeper optical boundary may paint before the dirty source.
    // Returning the previous image makes moving text trail its real position.
    final currentImage = source.capture(1, 0)!;
    expect(currentImage, isNot(same(oldImage)));
    final bytes = await tester.runAsync(
      () => currentImage.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes!.getUint8(0), 255);
    expect(bytes.getUint8(2), 0);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    expect(tester.takeException(), isNull);
  });
}
