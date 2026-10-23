import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';

class _PaintCounter extends LeafRenderObjectWidget {
  const _PaintCounter({super.key});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintCounter();
}

class _RenderPaintCounter extends RenderBox {
  int paints = 0;
  @override
  void performLayout() => size = constraints.constrain(const Size(40, 40));
  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
  }
}

void main() {
  testWidgets(
    'disabled optical capture schedules no paint on scroll, including after toggling',
    (tester) async {
      final source = OpticalBackdropSource();
      final enabled = ValueNotifier(false);
      final motion = ValueNotifier(0);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: ValueListenableBuilder(
              valueListenable: enabled,
              child: _PaintCounter(key: key),
              builder: (context, value, child) => OpticalBackdropCapture(
                source: source,
                motion: motion,
                enabled: value,
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final counter =
          key.currentContext!.findRenderObject() as _RenderPaintCounter;
      for (final value in [false, true, false, true, false]) {
        enabled.value = value;
        await tester.pumpAndSettle();
        final before = counter.paints;
        motion.value++;
        await tester.pumpAndSettle();
        if (value) {
          expect(counter.paints, greaterThan(before));
        } else {
          expect(
            counter.paints,
            before,
            reason:
                'Performance/high-contrast bypass must not retain a hidden capture listener',
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      enabled.dispose();
      motion.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
