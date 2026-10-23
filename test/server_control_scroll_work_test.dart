import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_list_controls.dart';

void main() {
  testWidgets(
    'fractional scrolling moves controls without rebuilding their stage',
    (tester) async {
      final scroll = ScrollController();
      var stageBuilds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 180,
              height: 360,
              child: Stack(
                children: [
                  ListView(
                    controller: scroll,
                    itemExtent: 65,
                    children: List.generate(30, (_) => const SizedBox()),
                  ),
                  Positioned.fill(
                    child: OpticalListControls(
                      scroll: scroll,
                      paddingTop: 0,
                      controls: List.generate(
                        30,
                        (i) =>
                            SizedBox(key: ValueKey(i), width: 40, height: 40),
                      ),
                      stageBuilder: (child) {
                        stageBuilds++;
                        return child;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialBuilds = stageBuilds;
      final first = find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.key == const ValueKey(0),
      );
      final initialCenter = tester.getCenter(first);
      for (final offset in [.25, .5, 1.25, 20.5, 40.75]) {
        scroll.jumpTo(offset);
        await tester.pump(Duration.zero, EnginePhase.layout);
        expect(
          tester.getCenter(first).dy,
          closeTo(initialCenter.dy - offset, .001),
        );
        await tester.pump();
        expect(
          stageBuilds,
          initialBuilds,
          reason:
              'Moving an existing batch must not rebuild every Positioned control',
        );
      }
      scroll.jumpTo(500);
      await tester.pump();
      expect(stageBuilds, greaterThan(initialBuilds));
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.key == const ValueKey(10),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
