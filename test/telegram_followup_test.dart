import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/registration/device_registration.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/app_shell.dart';

class _Controller extends AppController {
  _Controller(this.stage);
  final String stage;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    appVersion: '1.2.0',
    appBuild: 22,
    whatsNewSeenBuild: 22,
    telegramEligible: true,
    telegramStage: stage,
    connection: const ConnectionInfo(state: 'connected', serverId: 'a'),
    settings: const NativeSettings(performanceModePrompted: true),
  );
  void completePing() =>
      state = AsyncData(state.requireValue.copyWith(hasCompletedPing: true));
  @override
  Future<void> recordTelegramDecision(String decision) async {
    state = AsyncData(state.requireValue.copyWith(telegramEligible: false));
  }
}

Future<_Controller> _mount(WidgetTester tester, String stage) async {
  final controller = _Controller(stage);
  startupNetworkReady.value = true;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  tearDown(() => startupNetworkReady.value = false);
  testWidgets('mandatory first invitation has no Later option', (tester) async {
    await _mount(tester, 'first');
    expect(find.text('Join Telegram'), findsWidgets);
    expect(find.text('بعداً'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'optional followup waits for a fresh ping and is Persian in English UI',
    (tester) async {
      final controller = await _mount(tester, 'second');
      expect(find.text('بعداً'), findsNothing);
      controller.completePing();
      await tester.pumpAndSettle();
      expect(find.text('اخبار niraNG در تلگرام'), findsOneWidget);
      expect(find.text('بعداً'), findsOneWidget);
      await tester.tap(find.text('بعداً'));
      await tester.pumpAndSettle();
      controller.completePing();
      await tester.pumpAndSettle();
      expect(find.text('بعداً'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('optional invitation waits until an existing popup closes', (
    tester,
  ) async {
    final controller = await _mount(tester, 'second');
    final lease = MenuActivity.begin();
    controller.completePing();
    await tester.pumpAndSettle();
    expect(find.text('بعداً'), findsNothing);
    MenuActivity.end(lease);
    await tester.pumpAndSettle();
    expect(find.text('بعداً'), findsOneWidget);
    await tester.tap(find.text('بعداً'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'native ping completion gates followup and cancel does not count',
    (tester) async {
      const control = MethodChannel('dev.nirang.client/control');
      const events = MethodChannel('dev.nirang.client/events');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        control,
        (call) async => {
          'telegramEligible': true,
          'telegramStage': 'second',
          'connection': {'state': 'connected', 'serverId': 'a'},
          'settings': {'performanceModePrompted': true},
        },
      );
      messenger.setMockMethodCallHandler(events, (call) async => null);
      final container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        messenger.setMockMethodCallHandler(control, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      await container.read(appControllerProvider.future);
      Future<void> emit(String type, [Object? data]) async {
        messenger.handlePlatformMessage(
          events.name,
          const StandardMethodCodec().encodeSuccessEnvelope({
            'type': type,
            'data': data,
          }),
          (_) {},
        );
        await tester.pump();
      }

      expect(
        container.read(appControllerProvider).requireValue.telegramStage,
        'second',
      );
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isFalse,
      );
      await emit('pingCancelled');
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isFalse,
      );
      await emit('serverPing', {
        'id': 'a',
        'status': 'testing',
        'probeId': 'session-a:1:a',
      });
      await emit('serverPing', {
        'id': 'a',
        'status': 'success',
        'ping': 90,
        'probeId': 'session-a:1:a',
      });
      await emit('pingCompleted');
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
      await emit('connectionState', {'state': 'disconnected'});
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isFalse,
      );
      await emit('connectionState', {'state': 'connected', 'serverId': 'a'});
      // Finishing the old probe must not qualify the new connection, even
      // when it connects to the same server and another fresh probe started.
      await emit('serverPing', {
        'id': 'a',
        'status': 'testing',
        'probeId': 'session-b:1:a',
      });
      await emit('serverPing', {
        'id': 'a',
        'status': 'success',
        'ping': 90,
        'probeId': 'session-a:1:a',
      });
      await emit('pingCompleted');
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isFalse,
      );
      await emit('serverPing', {
        'id': 'a',
        'status': 'success',
        'ping': 70,
        'probeId': 'session-b:1:a',
      });
      await emit('pingCompleted');
      expect(
        container.read(appControllerProvider).requireValue.hasCompletedPing,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
