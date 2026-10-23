import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: true));
}

void main() {
  testWidgets(
    'Performance dialogs never introduce blur during entrance or exit',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showNirangDialog<void>(
                    context: context,
                    builder: (dialogContext) => NirangAlertDialog(
                      title: const Text('Usage'),
                      content: const Text('Measured by niraNG'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpAndSettle();
    },
  );
}
