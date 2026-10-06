import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/header_excluded_control.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/update_checker.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  _Controller({this.feedbackMode = 'haptic', this.performanceMode = false});
  final String feedbackMode;
  final bool performanceMode;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(
      feedbackMode: feedbackMode,
      performanceMode: performanceMode,
    ),
  );
}

void main() {
  for (final (brightness, performanceMode) in [
    (Brightness.light, false),
    (Brightness.light, true),
    (Brightness.dark, false),
    (Brightness.dark, true),
  ]) {
    testWidgets(
      'server actions fit the compact row as a circle ($brightness, performance=$performanceMode)',
      (tester) async {
        liveGlassReadyListenable.value = true;
        final header = GlobalKey();
        var selected = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(
                () => _Controller(
                  feedbackMode: 'off',
                  performanceMode: performanceMode,
                ),
              ),
            ],
            child: MaterialApp(
              theme: brightness == Brightness.dark
                  ? (performanceMode ? AppTheme.darkPerformance : AppTheme.dark)
                  : (performanceMode
                        ? AppTheme.lightPerformance
                        : AppTheme.light),
              home: Scaffold(
                body: Stack(
                  children: [
                    glass.GlassBackdropGroup(
                      child: Center(
                        child: ListTile(
                          title: const Text('Server'),
                          subtitle: const Text('VLESS TCP'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('120 ms'),
                              const SizedBox(width: 10),
                              LiquidActionMenu<int>(
                                serverActions: true,
                                triggerDecorator: (trigger) =>
                                    HeaderExcludedControl(
                                      headerKey: header,
                                      child: trigger,
                                    ),
                                tooltip: 'Server actions',
                                fallback: const Text('Fallback'),
                                onSelected: (_) => selected++,
                                items: const [
                                  LiquidActionItem(
                                    value: 1,
                                    label: 'Select server',
                                    icon: Icons.check,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SizedBox(key: header, width: 200, height: 64),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = tester.widget<glass.GlassButton>(
          find.byType(glass.GlassButton),
        );
        expect(button.width, button.height);
        expect(button.shape, isA<glass.LiquidOval>());
        expect(button.stretch, 0);
        expect(button.interactionScale, 1);
        expect(button.useOwnLayer, isTrue);
        expect(button.quality, glass.GlassQuality.premium);
        final lens = find.descendant(
          of: find.byType(glass.GlassButton),
          matching: find.byType(glass.AdaptiveGlass),
        );
        final lensSize = tester.getSize(lens);
        expect(
          lensSize.width,
          closeTo(lensSize.height, .01),
          reason: 'Compact server rows must not flatten the actual glass lens',
        );
        expect(lensSize.width, lessThanOrEqualTo(44));
        expect(lensSize, const Size(40, 40));
        final menu = tester.widget<glass.GlassMenu>(
          find.byType(glass.GlassMenu),
        );
        expect(menu.settings!.effectiveBlur, greaterThanOrEqualTo(6));
        expect(menu.settings!.effectiveFrost, 0);
        await tester.tap(find.byTooltip('Server actions'));
        await tester.pumpAndSettle();
        expect(find.text('Select server'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('Select server'),
            matching: find.byType(HeaderExcludedControl),
          ),
          findsNothing,
          reason: 'Only the trigger is masked, never its popup overlay',
        );
        await tester.tap(find.text('Select server'));
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final performanceMode in [false, true]) {
    test(
      'light panels use continuous blur without sharp ghost rows (performance=$performanceMode)',
      () {
        final settings = liquidSurfaceSettings(
          Brightness.light,
          performanceMode: performanceMode,
        );
        expect(settings.effectiveBlur, greaterThanOrEqualTo(6));
        expect(settings.effectiveFrost, 0);
        expect(settings.blurWeight, 1);
        expect(settings.frostClamp, 0);
        final control = liquidControlSettings(
          Brightness.light,
          performanceMode: performanceMode,
        );
        // The fix must not change the approved button or curved lens recipe.
        expect(settings.glassColor, control.glassColor);
        expect(settings.bodyMode, control.bodyMode);
        expect(settings.lensModel, control.lensModel);
        expect(settings.thickness, control.thickness);
        expect(settings.refractiveIndex, control.refractiveIndex);
        expect(settings.rimLight, control.rimLight);
        expect(control.effectiveFrost, greaterThan(0));
        expect(control.blur, 0);
        expect(
          liquidMessageSettings(
            Brightness.light,
            performanceMode: performanceMode,
          ),
          settings,
        );
        if (!performanceMode) {
          expect(GlassSurface.settingsFor(Brightness.light), settings);
        }
      },
    );
  }
  test(
    'large dark message material narrows highlights without smoking the body or changing controls',
    () {
      final panel = liquidSurfaceSettings(Brightness.dark);
      final message = liquidMessageSettings(Brightness.dark);
      expect(message.lightIntensity, lessThan(panel.lightIntensity));
      expect(message.thickness, lessThan(panel.thickness));
      expect(message.refractiveIndex, lessThan(panel.refractiveIndex));
      expect(message.glassColor, panel.glassColor);
      expect(message.blur, panel.blur);
      expect(message.whitenStrength, 0);
      expect(message.backerColor, isNull);
      expect(
        liquidMessageSettings(Brightness.light),
        liquidSurfaceSettings(Brightness.light),
      );
      expect(liquidControlSettings(Brightness.dark).lightIntensity, .35);
    },
  );
  test(
    'performance optical material removes redundant weighted GPU passes',
    () {
      final settings = liquidSurfaceSettings(
        Brightness.dark,
        performanceMode: true,
      );
      expect(settings.blurWeight, 1);
      expect(settings.frostWeight, 1);
      expect(settings.effectiveBlur, greaterThanOrEqualTo(6));
      expect(settings.frost, 0);
      expect(settings.glassColor.a, lessThan(.08));
      expect(settings.lensModel, glass.GlassLensModel.spherical);
      final control = liquidControlSettings(
        Brightness.dark,
        performanceMode: true,
      );
      expect(control.blur, 0);
      expect(control.frostWeight, 1);
      expect(control.frost, greaterThan(0));
    },
  );
  tearDown(() => liveGlassReadyListenable.value = false);
  test(
    'Android uses the approved upstream optical material, not the old renderer',
    () {
      final settings = GlassSurface.settingsFor(Brightness.dark);
      expect(settings, isA<glass.LiquidGlassSettings>());
      // A continuous native blur feeds the same optical shader. No sharp
      // ghost rows may make the text under a dark panel legible again.
      expect(settings.effectiveBlur, greaterThanOrEqualTo(6));
      expect(settings.frostWeight, 1);
      expect(settings.frostOpacity, lessThan(1));
      expect(settings.frost, 0);
      expect(settings.glassColor.a, lessThan(.08));
      expect(settings.glassColor.r, greaterThan(.9));
      expect(settings.lensModel, glass.GlassLensModel.spherical);
      expect(settings.lightIntensity, greaterThan(0));
      expect(settings.fresnelStrength, greaterThan(0));
    },
  );

  testWidgets('unsupported renderer has a visible clipped blur fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_Controller.new)],
        child: const MaterialApp(
          home: Scaffold(body: GlassSurface(child: Text('Readable'))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Readable'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'upstream short action menu keeps rows fixed and honors silent feedback',
    (tester) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      liveGlassReadyListenable.value = true;
      int selected = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(
              () => _Controller(feedbackMode: 'off'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: LiquidActionMenu<int>(
                  tooltip: 'Menu',
                  fallback: const Text('Fallback'),
                  items: const [
                    LiquidActionItem(
                      value: 1,
                      label: 'First',
                      icon: Icons.copy,
                    ),
                    LiquidActionItem(
                      value: 2,
                      label: 'Second',
                      icon: Icons.refresh,
                    ),
                  ],
                  onSelected: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(glass.GlassMenu), findsOneWidget);
      final menu = tester.widget<glass.GlassMenu>(find.byType(glass.GlassMenu));
      expect(menu.menuHeight, isNull);
      expect(menu.enableHaptics, isFalse);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      final before = tester.getCenter(find.text('Second'));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: before, scrollDelta: const Offset(0, 90)),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Second')), before);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('First')),
      );
      await gesture.moveTo(before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);
      if (selected == 0) {
        await tester.tap(find.text('Second'));
        await tester.pumpAndSettle();
      }
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'five actions fit a narrow RTL phone without scroll or overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 640),
                  textScaler: TextScaler.linear(1.4),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: LiquidActionMenu<int>(
                      tooltip: 'عملیات',
                      fallback: const Text('Fallback'),
                      onSelected: (_) {},
                      items: const [
                        LiquidActionItem(
                          value: 0,
                          label: 'راه‌اندازی دوباره سرویس',
                          icon: Icons.restart_alt,
                        ),
                        LiquidActionItem(
                          value: 1,
                          label: 'مرتب‌سازی بر اساس پینگ',
                          icon: Icons.sort,
                        ),
                        LiquidActionItem(
                          value: 2,
                          label: 'بررسی اتصال TCP',
                          icon: Icons.network_ping,
                        ),
                        LiquidActionItem(
                          value: 3,
                          label: 'بررسی تأخیر واقعی',
                          icon: Icons.timer,
                        ),
                        LiquidActionItem(
                          value: 4,
                          label: 'به‌روزرسانی اشتراک',
                          icon: Icons.refresh,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('عملیات'));
      await tester.pumpAndSettle();
      final last = find.text('به‌روزرسانی اشتراک');
      expect(last, findsOneWidget);
      final before = tester.getRect(last);
      expect(before.left, greaterThanOrEqualTo(0));
      expect(before.right, lessThanOrEqualTo(360));
      expect(before.bottom, lessThanOrEqualTo(640));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: before.center,
          scrollDelta: const Offset(0, 90),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(last), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shield state motion settles instead of running forever', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionShield(
            state: 'connecting',
            connected: false,
            color: Colors.green,
            reducedEffects: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionShield(
            state: 'connected',
            connected: true,
            color: Colors.green,
            reducedEffects: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('this build carries genuine bilingual release notes offline', (
    tester,
  ) async {
    final notes = await const GitHubUpdateChecker().releaseNotes('1.2.1');
    expect(notes.english, contains('Liquid Glass'));
    expect(notes.persian, contains('بلور پیوسته'));
    expect(notes.english, contains('1.2.1'));
    expect(notes.english, contains('stay circular'));
    expect(notes.english, isNot(contains('## فارسی')));
  });
}
