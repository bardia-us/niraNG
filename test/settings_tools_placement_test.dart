import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/settings/settings_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: true));
}

void main() {
  testWidgets(
    'Quick Settings action belongs to General; no battery query or entry',
    (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('dev.nirang.client/control');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'batteryOptimizationStatus' ? false : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        calls,
        isNot(contains('batteryOptimizationStatus')),
        reason:
            'A removed settings entry must not still issue its async platform query',
      );
      await tester.scrollUntilVisible(find.text('General'), 400);
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      final tile = find.text('Quick Settings VPN tile');
      expect(tile, findsOneWidget);
      final parent = tester.widget<ExpansionTile>(
        find.ancestor(of: tile, matching: find.byType(ExpansionTile)),
      );
      expect((parent.title as Text).data, 'General');
      await tester.scrollUntilVisible(find.text('Advanced'), 400);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(
        find.text('Battery optimization', skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
