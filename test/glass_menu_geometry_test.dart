import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

const _selectionColor = Color(0xFF123456);

Future<void> _mountMenu(
  WidgetTester tester,
  glass.GlassMenuController controller, {
  double textScale = 1,
  double width = 280,
  TextDirection direction = TextDirection.ltr,
  List<String> labels = const ['First', 'Second', 'Third', 'Fourth'],
  ValueChanged<int>? onSelected,
  ValueChanged<bool>? onVisibilityChanged,
  List<Widget>? customItems,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: direction,
            child: Builder(
              builder: (context) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: glass.GlassMenu(
                    controller: controller,
                    onVisibilityChanged: onVisibilityChanged,
                    quality: glass.GlassQuality.minimal,
                    menuAlignment: glass.GlassMenuAlignment.topLeft,
                    menuWidth: width,
                    selectionColor: _selectionColor,
                    trigger: const SizedBox(width: 44, height: 44),
                    items:
                        customItems ??
                        [
                          for (var i = 0; i < labels.length; i++)
                            glass.GlassMenuItem(
                              title: labels[i],
                              icon: const Icon(Icons.copy),
                              height: 48,
                              maxLines: 2,
                              titleStyle: Theme.of(
                                context,
                              ).textTheme.bodyMedium,
                              onTap: () => onSelected?.call(i),
                            ),
                        ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  controller.open();
  await tester.pumpAndSettle();
}

Finder _pill() => find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).color == _selectionColor,
);

Finder _row(String label) => find.byWidgetPredicate(
  (widget) => widget is glass.GlassMenuItem && widget.title == label,
);

void main() {
  for (final scale in [1.0, 1.2, 1.4]) {
    testWidgets(
      'short rows own their actual highlight and hit area at $scale',
      (tester) async {
        final controller = glass.GlassMenuController();
        int? selected;
        await _mountMenu(
          tester,
          controller,
          textScale: scale,
          onSelected: (index) => selected = index,
        );
        final third = tester.getRect(_row('Third'));
        final gesture = await tester.startGesture(third.center);
        await tester.pumpAndSettle();
        final activeRow = tester.getRect(_row('Third'));
        expect(
          tester.getRect(_pill()).center.dy,
          closeTo(activeRow.center.dy, .1),
        );
        expect(tester.getRect(_pill()).height, closeTo(activeRow.height, .1));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('four short rows leave only menu padding at $scale', (
      tester,
    ) async {
      await _mountMenu(tester, glass.GlassMenuController(), textScale: scale);
      final menuBody = find.byWidgetPredicate(
        (widget) => widget is glass.GlassContainer && widget.width == 280,
      );
      final bottom = tester.getRect(menuBody).bottom;
      final lastBottom = tester.getRect(_row('Fourth')).bottom;
      expect(bottom - lastBottom, closeTo(12, .1));
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.physics, isA<NeverScrollableScrollPhysics>());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'narrow RTL wrapped title keeps later hit and highlight aligned',
    (tester) async {
      final controller = glass.GlassMenuController();
      int? selected;
      await _mountMenu(
        tester,
        controller,
        width: 240,
        textScale: 1.4,
        direction: TextDirection.rtl,
        labels: const ['مرتب‌سازی بر اساس تأخیر واقعی اتصال', 'کپی', 'حذف'],
        onSelected: (index) => selected = index,
      );
      final first = tester.getRect(_row('مرتب‌سازی بر اساس تأخیر واقعی اتصال'));
      final second = tester.getRect(_row('کپی'));
      expect(first.height, greaterThan(second.height));
      final gesture = await tester.startGesture(second.center);
      await tester.pumpAndSettle();
      final activeRow = tester.getRect(_row('کپی'));
      expect(
        tester.getRect(_pill()).center.dy,
        closeTo(activeRow.center.dy, .1),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visibility remains true through close until overlay removal', (
    tester,
  ) async {
    final controller = glass.GlassMenuController();
    final changes = <bool>[];
    await _mountMenu(tester, controller, onVisibilityChanged: changes.add);
    expect(changes, [true]);
    controller.close();
    expect(controller.isOpen, isTrue);
    expect(changes, [true]);
    await tester.pump(const Duration(milliseconds: 16));
    expect(changes, [true]);
    await tester.pumpAndSettle();
    expect(controller.isOpen, isFalse);
    expect(changes, [true, false]);
  });

  testWidgets('disposing an open menu releases visibility once', (
    tester,
  ) async {
    final controller = glass.GlassMenuController();
    final changes = <bool>[];
    await _mountMenu(tester, controller, onVisibilityChanged: changes.add);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(changes, [true, false]);
    expect(controller.isOpen, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual tall trailing widget controls later row geometry', (
    tester,
  ) async {
    int? selected;
    await _mountMenu(
      tester,
      glass.GlassMenuController(),
      customItems: [
        glass.GlassMenuItem(
          title: 'Tall trailing',
          trailing: const SizedBox(width: 72, height: 64),
          onTap: () {},
        ),
        glass.GlassMenuItem(title: 'Second', onTap: () => selected = 1),
      ],
    );
    final gesture = await tester.startGesture(tester.getCenter(_row('Second')));
    await tester.pumpAndSettle();
    final second = tester.getRect(_row('Second'));
    expect(tester.getRect(_pill()).center.dy, closeTo(second.center.dy, .1));
    expect(tester.getRect(_row('Tall trailing')).height, greaterThan(64));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening during close retains one visibility interval', (
    tester,
  ) async {
    final controller = glass.GlassMenuController();
    final changes = <bool>[];
    await _mountMenu(tester, controller, onVisibilityChanged: changes.add);
    controller.close();
    await tester.pump(const Duration(milliseconds: 32));
    controller.open();
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(controller.isOpen, isTrue);
    controller.close();
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
  });

  testWidgets('route push releases overlay visibility immediately', (
    tester,
  ) async {
    final controller = glass.GlassMenuController();
    final navigatorKey = GlobalKey<NavigatorState>();
    final changes = <bool>[];
    await _mountMenu(
      tester,
      controller,
      navigatorKey: navigatorKey,
      onVisibilityChanged: changes.add,
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Next route')),
      ),
    );
    await tester.pump();
    expect(controller.isOpen, isFalse);
    expect(changes, [true, false]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
