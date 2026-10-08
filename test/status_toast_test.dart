import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/status_toast.dart';

void main() {
  testWidgets('profile failure uses a themed transient error toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showErrorToast(context, 'Could not save'),
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Could not save'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('success toast is readable and dismisses in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: brightness,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showSuccessToast(context, 'Already up to date'),
                child: const Text('Check'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Already up to date'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final message = tester.element(find.text('Already up to date'));
      final foreground = DefaultTextStyle.of(message).style.color!;
      final background = tester
          .widget<SnackBar>(find.byType(SnackBar))
          .backgroundColor!;
      final luminances = [
        foreground.computeLuminance(),
        background.computeLuminance(),
      ]..sort();
      expect(
        (luminances.last + .05) / (luminances.first + .05),
        greaterThan(4.5),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Already up to date'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
