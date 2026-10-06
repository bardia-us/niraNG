import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/theme/app_scroll_behavior.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot();
}

Future<void> mount(WidgetTester tester, Widget content) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(_Controller.new)],
      child: MaterialApp(
        scrollBehavior: const NirangScrollBehavior(reducedEffects: false),
        home: NirangAlertDialog(
          title: const Text('Settings'),
          content: content,
          actions: [TextButton(onPressed: () {}, child: const Text('Save'))],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keyboard-constrained form scrolls without hiding Save', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 760);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await mount(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 6; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextFormField(
                decoration: InputDecoration(labelText: 'Field $index'),
              ),
            ),
        ],
      ),
    );
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(find.text('Save').hitTestable(), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'fitting form stays fixed during a drag even with bouncing app physics',
    (tester) async {
      await mount(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('VPN MTU'),
            TextFormField(initialValue: '1500'),
          ],
        ),
      );
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('VPN MTU')),
      );
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(scroll.position.pixels, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overflowing notes can still scroll with actions always reachable',
    (tester) async {
      await mount(tester, Text('Long release notes\n' * 100));
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(find.text('Save').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
