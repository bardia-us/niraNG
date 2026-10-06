import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/choice_dialog_options.dart';

void main() {
  Future<void> mount(WidgetTester tester, double height, {double scale = 1}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: SizedBox(
                  width: 240,
                  height: height,
                  child: ChoiceDialogOptions(
                    values: const {'en': 'English', 'fa': 'فارسی'},
                    current: 'en',
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  testWidgets('two fitting choices have no scrollable', (tester) async {
    await mount(tester, 180);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('small viewport can reach overflowing choices', (tester) async {
    await mount(tester, 90);
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -50));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('large accessibility text does not overflow', (tester) async {
    await mount(tester, 110, scale: 2.2);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
