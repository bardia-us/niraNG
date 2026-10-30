import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/features/vpn/app_controller.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'download dialog has a distinct opaque surface in $brightness',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [performanceModeProvider.overrideWithValue(true)],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const NirangAlertDialog(
                emphasized: true,
                title: Text('Downloading'),
                content: LinearProgressIndicator(value: .4),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('emphasized-dialog-surface')),
        );
        final decoration = surface.decoration as BoxDecoration;
        final scheme = Theme.of(
          tester.element(find.text('Downloading')),
        ).colorScheme;
        expect(decoration.color!.a, 1);
        expect(decoration.color, isNot(scheme.surfaceContainerHigh));
        expect(decoration.border, isNotNull);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      },
    );
  }
}
