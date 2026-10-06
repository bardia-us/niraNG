import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/features/settings/settings_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _PreferencesController extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot();
  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    final app = state.asData!.value;
    state = AsyncData(app.copyWith(settings: app.settings.withUpdates(values)));
  }
}

Future<void> _tapSetting(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  test('missing appearance preferences use safe Windows-style defaults', () {
    final settings = NativeSettings.fromMap(const {});
    expect(settings.accentColor, 'purple');
    expect(settings.darkCanvas, AppTheme.darkCanvases.keys.first);
    expect(settings.feedbackMode, 'haptic');
  });
  test(
    'valid appearance and feedback survive an unrelated settings update',
    () {
      final settings = NativeSettings.fromMap(const {
        'accentColor': 'blue',
        'darkCanvas': 'oled',
        'feedbackMode': 'sound',
      }).withUpdates({'language': 'fa'});
      expect(settings.accentColor, 'blue');
      expect(settings.darkCanvas, 'oled');
      expect(settings.feedbackMode, 'sound');
    },
  );
  test('unknown stored appearance or feedback values fall back safely', () {
    final settings = NativeSettings.fromMap(const {
      'accentColor': 'invalid',
      'darkCanvas': false,
      'feedbackMode': null,
    });
    expect(settings.accentColor, 'purple');
    expect(settings.darkCanvas, AppTheme.darkCanvases.keys.first);
    expect(settings.feedbackMode, 'haptic');
  });
  test('invalid optimistic updates preserve the current preference', () {
    final settings =
        NativeSettings.fromMap(const {
          'accentColor': 'rose',
          'darkCanvas': 'midnight',
          'feedbackMode': 'off',
        }).withUpdates({
          'accentColor': null,
          'darkCanvas': 'bad',
          'feedbackMode': 7,
        });
    expect(settings.accentColor, 'rose');
    expect(settings.darkCanvas, 'midnight');
    expect(settings.feedbackMode, 'off');
  });
  test('default dark canvas and light canvas match the Windows choices', () {
    expect(
      AppTheme.dark.scaffoldBackgroundColor,
      AppTheme.darkCanvases.values.first,
    );
    expect(AppTheme.light.scaffoldBackgroundColor, const Color(0xFFF8F8FC));
  });
  test(
    'personalized appearance changes primary and preserves semantic colors',
    () {
      final theme = AppTheme.forSettings(
        brightness: Brightness.dark,
        reducedEffects: true,
        accentColor: 'blue',
        darkCanvas: 'midnight',
      );
      expect(theme.scaffoldBackgroundColor, const Color(0xFF10111A));
      expect(
        theme.colorScheme.primary,
        isNot(AppTheme.dark.colorScheme.primary),
      );
      expect(
        theme.extension<NirangSemanticColors>()!.success,
        const Color(0xFF6FC5AA),
      );
      expect(
        theme.extension<NirangSemanticColors>()!.warning,
        const Color(0xFFE0B465),
      );
      expect(
        AppTheme.forSettings(
          brightness: Brightness.dark,
          reducedEffects: false,
          accentColor: 'rose',
          darkCanvas: 'oled',
        ).scaffoldBackgroundColor,
        Colors.black,
      );
    },
  );
  test('unknown theme choices safely reuse normalized default themes', () {
    final unknown = AppTheme.forSettings(
      brightness: Brightness.dark,
      reducedEffects: false,
      accentColor: 'bad',
      darkCanvas: 'bad',
    );
    final defaults = AppTheme.forSettings(
      brightness: Brightness.dark,
      reducedEffects: false,
      accentColor: 'purple',
      darkCanvas: 'midnight',
    );
    expect(unknown, same(defaults));
  });
  testWidgets('appearance choices apply only after confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_PreferencesController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
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
    await _tapSetting(tester, 'Theme & Appearance');
    await _tapSetting(tester, 'Accent color');
    await tester.tap(find.text('Blue'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Purple'), findsOneWidget);
    await _tapSetting(tester, 'Accent color');
    await tester.tap(find.text('Blue'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Blue'), findsOneWidget);
    await _tapSetting(tester, 'Dark background');
    final dialog = find.byType(Dialog);
    final dialogSurface = find.descendant(
      of: dialog,
      matching: find.byType(GlassSurface),
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(tester.getSize(dialogSurface).height, lessThan(350));
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Graphite')),
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Graphite'), findsOneWidget);
    await _tapSetting(tester, 'Interaction feedback');
    await tester.tap(find.text('Sound'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Sound'), findsOneWidget);
  });
}
