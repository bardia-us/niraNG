import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/header_excluded_control.dart';

class _PaintProbe extends LeafRenderObjectWidget {
  const _PaintProbe(this.onPaint);
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) => _Probe(onPaint);
}

class _Probe extends RenderBox {
  _Probe(this.onPaint);
  final VoidCallback onPaint;
  @override
  void performLayout() => size = constraints.constrain(const Size(40, 40));
  @override
  bool hitTestSelf(Offset position) => true;
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xFFFF0000),
    );
  }
}

void main() {
  testWidgets(
    'composited control follows rounded header through scroll and parent motion',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final translation = ValueNotifier(Offset.zero);
      addTearDown(translation.dispose);
      final header = GlobalKey();
      final frame = GlobalKey();
      var paints = 0;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: frame,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Colors.white),
                      ),
                      SingleChildScrollView(
                        controller: scroll,
                        child: Column(
                          children: [
                            const SizedBox(height: 350),
                            Align(
                              alignment: Alignment.center,
                              child: ValueListenableBuilder<Offset>(
                                valueListenable: translation,
                                builder: (context, offset, child) =>
                                    Transform.translate(
                                      offset: offset,
                                      child: child,
                                    ),
                                child: HeaderExcludedControl(
                                  headerKey: header,
                                  child: GestureDetector(
                                    onTap: () => taps++,
                                    child: SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: RepaintBoundary(
                                        child: _PaintProbe(() => paints++),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 350),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: SizedBox(key: header, width: 180, height: 64),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Future<int> greenAt(int x, int y) async =>
          (await tester.runAsync(() async {
            final boundary =
                frame.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final img = await boundary.toImage(pixelRatio: 1);
            try {
              final data = (await img.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return data.getUint8((y * img.width + x) * 4 + 1);
            } finally {
              img.dispose();
            }
          }))!;

      // Below the header: the actual child paints normally.
      scroll.jumpTo(250);
      await tester.pump();
      expect(paints, greaterThan(0));
      expect(await greenAt(100, 110), 0);
      final origin = tester.getTopLeft(find.byKey(frame));
      await tester.tapAt(origin + const Offset(100, 110));
      expect(taps, 1);

      // Top 24 pixels overlap the header; the lower part remains visible.
      scroll.jumpTo(300);
      await tester.pump();
      // Red's green channel is zero; the white canvas stays white under the header.
      expect(await greenAt(100, 60), 255);
      expect(await greenAt(100, 80), 0);
      await tester.tapAt(origin + const Offset(100, 60));
      expect(taps, 1);
      await tester.tapAt(origin + const Offset(100, 80));
      expect(taps, 2);

      // Fully covered: do not paint the control/filter subtree at all.
      final before = paints;
      scroll.jumpTo(320);
      await tester.pump();
      expect(paints, before);

      // Reorder/press transforms can move a cached row without scrolling.
      translation.value = const Offset(0, 100);
      await tester.pump();
      expect(await greenAt(100, 140), 0);
      translation.value = Offset.zero;
      await tester.pump();
      expect(await greenAt(100, 40), 255);

      scroll.jumpTo(250);
      await tester.pump();
      expect(await greenAt(100, 110), 0);
      // Do not cut the rounded corner as though the header were a rectangle.
      translation.value = const Offset(-70, -90);
      await tester.pump();
      expect(await greenAt(12, 12), 0);
      expect(await greenAt(30, 30), 255);
      translation.value = Offset.zero;
      await tester.pump();
      expect(await greenAt(100, 110), 0);
      await tester.tapAt(origin + const Offset(100, 110));
      expect(taps, 3);
      // Listener must be removed before the scrolling page is disposed.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
