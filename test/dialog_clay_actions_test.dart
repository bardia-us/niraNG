import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/clay_surface.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/features/vpn/app_controller.dart';

void main() {
  for (final dark in [false, true]) {
    for (final performance in [false, true]) {
      testWidgets('Apply paints clay depth and releases press dark=$dark '
          'performance=$performance', (tester) async {
        final key = GlobalKey();
        var applied = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [performanceModeProvider.overrideWithValue(performance)],
            child: MaterialApp(
              theme: AppTheme.forSettings(
                brightness: dark ? Brightness.dark : Brightness.light,
                reducedEffects: performance,
                accentColor: 'purple',
                darkCanvas: 'midnight',
              ),
              home: NirangAlertDialog(
                title: const Text('Settings'),
                actions: [
                  RepaintBoundary(
                    key: key,
                    child: FilledButton(
                      onPressed: () => applied++,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byType(FilledButton);
        final material = tester.widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        );
        expect(
          material.color?.a ?? 0,
          0,
          reason: 'An opaque Material covers the clay gradient',
        );

        Future<List<int>> pixels() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          return (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List().toList();
            image.dispose();
            return bytes;
          }))!;
        }

        final resting = await pixels();
        final clay = find.descendant(
          of: button,
          matching: find.byType(ClaySurface),
        );
        expect(clay, findsOneWidget);
        BoxDecoration decoration() =>
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: clay,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        final raised = decoration();
        expect(
          (material.shape! as RoundedRectangleBorder).borderRadius,
          raised.borderRadius,
          reason: 'The hit/ink contour must follow the visible clay contour',
        );
        final gesture = await tester.startGesture(tester.getCenter(button));
        await tester.pumpAndSettle();
        final pressed = decoration();
        expect(pressed.gradient, isNot(raised.gradient));
        expect(await pixels(), isNot(resting));
        expect(applied, 0);
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(decoration(), raised);
        expect(await pixels(), resting);
        expect(applied, 0);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(applied, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'destructive action keeps error tint and secondary keeps its clay',
    (tester) async {
      final theme = AppTheme.light;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [performanceModeProvider.overrideWithValue(true)],
          child: MaterialApp(
            theme: theme,
            home: NirangAlertDialog(
              actions: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () {},
                  child: const Text('Delete'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final clay = tester.widget<ClaySurface>(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(ClaySurface),
        ),
      );
      expect(clay.color, theme.colorScheme.error);
      final secondary = find.byType(TextButton);
      final material = tester.widget<Material>(
        find.descendant(of: secondary, matching: find.byType(Material)).first,
      );
      expect(
        material.clipBehavior,
        Clip.none,
        reason: 'Cancel must not gain a new clip that removes its clay shadow',
      );
      expect(
        find.ancestor(of: secondary, matching: find.byType(ClaySurface)),
        findsOneWidget,
      );
    },
  );

  testWidgets('Apply retains keyboard activation and disabled semantics', (
    tester,
  ) async {
    final focus = FocusNode();
    final enabled = ValueNotifier(true);
    addTearDown(focus.dispose);
    addTearDown(enabled.dispose);
    var applied = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [performanceModeProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: ValueListenableBuilder(
            valueListenable: enabled,
            builder: (_, active, _) => NirangAlertDialog(
              actions: [
                FilledButton(
                  focusNode: focus,
                  onPressed: active ? () => applied++ : null,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    // InkWell simulates a short press for keyboard activation; settling here
    // would deliberately advance past that press's release timer.
    await tester.pump();
    final press = find.descendant(
      of: find.byType(FilledButton),
      matching: find.byType(ClayPress),
    );
    expect(tester.widget<ClayPress>(press).pressed, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(applied, 1);
    expect(tester.widget<ClayPress>(press).pressed, isFalse);
    enabled.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(applied, 1);
    expect(tester.widget<ClayPress>(press).pressed, isFalse);
    expect(
      tester
          .widget<ClaySurface>(
            find.descendant(
              of: find.byType(FilledButton),
              matching: find.byType(ClaySurface),
            ),
          )
          .color,
      AppTheme.dark.colorScheme.surfaceContainerHigh,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
