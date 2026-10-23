import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/widgets/clay_surface.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/measured_traffic_panel.dart';

void main() {
  const channel = MethodChannel('dev.nirang.client/control');
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> pumpPanel(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    VoidCallback? onParentBuild,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [performanceModeProvider.overrideWithValue(true)],
        child: MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: brightness,
            ),
          ),
          locale: locale,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Builder(
            builder: (_) {
              onParentBuild?.call();
              return const Scaffold(body: MeasuredTrafficPanel());
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    for (final locale in [const Locale('en'), const Locale('fa')]) {
      testWidgets(
        'traffic help is a compact themed dialog in ${brightness.name}/${locale.languageCode}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (_) async => {'available': true},
          );
          await pumpPanel(tester, brightness: brightness, locale: locale);
          await tester.tap(find.byIcon(Icons.info_outline_rounded));
          await tester.pumpAndSettle();
          final dialog = find.byType(NirangAlertDialog);
          expect(dialog, findsOneWidget);
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: dialog,
                    matching: find.byType(GlassSurface),
                  ),
                )
                .height,
            lessThan(400),
          );
          final explanation = find.descendant(
            of: dialog,
            matching: find.textContaining('≥'),
          );
          expect(explanation, findsOneWidget);
          final context = tester.element(explanation);
          expect(
            DefaultTextStyle.of(context).style.color,
            Theme.of(context).colorScheme.onSurfaceVariant,
          );
          expect(
            find.descendant(of: dialog, matching: find.byType(ClaySurface)),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.descendant(of: dialog, matching: find.byType(TextButton)).last,
          );
          await tester.pumpAndSettle();
          expect(dialog, findsNothing);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'shows actual measured totals and partial coverage without speed or per-config values',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'todayBytes': 2048,
          'monthBytes': 4096,
          'todayPartial': true,
          'monthPartial': false,
          'available': true,
        },
      );
      await pumpPanel(tester);
      expect(find.text('Measured traffic'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('≥ 2.00 KB'), findsOneWidget);
      expect(find.text('4.00 KB'), findsOneWidget);
      expect(find.textContaining('/s'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsupported or malformed native totals remain unknown in Persian at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'todayBytes': -1,
          'monthBytes': null,
          'available': false,
        },
      );
      await pumpPanel(tester, locale: const Locale('fa'));
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0 B'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'traffic refresh rebuilds only the panel and suspends when backgrounded',
    (tester) async {
      var bytes = 1024;
      var parentBuilds = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'todayBytes': bytes,
          'monthBytes': bytes,
          'available': true,
        },
      );
      await pumpPanel(tester, onParentBuild: () => parentBuilds++);
      expect(find.text('1.00 KB'), findsNWidgets(2));
      final initialBuilds = parentBuilds;
      bytes = 2048;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('2.00 KB'), findsNWidgets(2));
      expect(parentBuilds, initialBuilds);
      bytes = 4096;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('2.00 KB'), findsNWidgets(2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('4.00 KB'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
