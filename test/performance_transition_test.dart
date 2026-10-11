import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/settings/settings_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  final changes = <bool>[];
  bool failSave = false;

  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: true));

  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    if (failSave) throw StateError('save failed');
    changes.add(values['performanceMode']! as bool);
    state = AsyncData(
      state.requireValue.copyWith(
        settings: state.requireValue.settings.withUpdates(values),
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Controller controller,
  Future<void> Function() prepare,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        liveGlassPreparationProvider.overrideWithValue(prepare),
      ],
      child: const MaterialApp(
        localizationsDelegates: [AppStrings.delegate],
        home: Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Theme & Appearance'), 350);
  await tester.tap(find.text('Theme & Appearance'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Performance Mode'), 250);
  await tester.pumpAndSettle();
}

Finder get _switch => find.widgetWithText(SwitchListTile, 'Performance Mode');

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  testWidgets('already prepared glass does not load again', (tester) async {
    liveGlassReadyListenable.value = true;
    final controller = _Controller();
    await _open(tester, controller, () async {
      throw StateError('should not reload cached shaders');
    });
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'leaving settings during preparation does not save or use disposed state',
    (tester) async {
      final controller = _Controller();
      final prepared = Completer<void>();
      await _open(tester, controller, () => prepared.future);
      await tester.tap(_switch);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      prepared.complete();
      await tester.pumpAndSettle();
      expect(controller.changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('leaving matte waits for glass behind visible busy feedback', (
    tester,
  ) async {
    final controller = _Controller();
    final prepared = Completer<void>();
    var loads = 0;
    await _open(tester, controller, () {
      loads++;
      return prepared.future;
    });
    await tester.tap(_switch);
    expect(controller.changes, isEmpty);
    expect(loads, 0); // Preparation starts only after feedback can paint.
    await tester.pump();
    expect(loads, 1);
    expect(controller.state.requireValue.settings.performanceMode, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<SwitchListTile>(_switch).onChanged, isNull);
    await tester.tap(_switch);
    await tester.pump();
    expect(loads, 1);
    prepared.complete();
    await tester.pumpAndSettle();
    expect(controller.changes, [false]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(controller.changes, [false, true]);
    expect(loads, 1); // Returning to matte never loads shaders.
  });

  testWidgets('failed save clears preparation feedback and keeps matte', (
    tester,
  ) async {
    final controller = _Controller()..failSave = true;
    await _open(tester, controller, () async {});
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(controller.state.requireValue.settings.performanceMode, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<SwitchListTile>(_switch).onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
