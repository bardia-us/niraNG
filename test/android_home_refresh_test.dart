import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/home_screen.dart';

class _HomeController extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    settings: NativeSettings(performanceMode: true),
    servers: [
      ServerInfo(
        id: 'a',
        name: 'Test',
        country: 'SE',
        protocol: 'VLESS',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        selected: true,
        status: 'idle',
      ),
    ],
    connection: ConnectionInfo(
      state: 'connected',
      serverId: 'a',
      publicIp: '203.0.113.2',
      publicIpChecked: true,
    ),
    usage: SubscriptionUsage(used: 65, total: 80, remaining: 15),
  );
}

void main() {
  for (final rejectedByError in [false, true]) {
    testWidgets(
      'late IP ${rejectedByError ? 'failure' : 'rejection'} cannot restore a previous network result',
      (tester) async {
        const channel = MethodChannel('dev.nirang.client/control');
        const events = MethodChannel('dev.nirang.client/events');
        final reply = Completer<bool>();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          events,
          (_) async => null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'initialize') {
              return {
                'settings': <String, Object?>{},
                'servers': <Object?>[],
                'connection': {
                  'state': 'connected',
                  'serverId': 'a',
                  'publicIp': '203.0.113.2',
                  'publicIpChecked': true,
                },
              };
            }
            if (call.method == 'refreshPublicIp') return reply.future;
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            events,
            null,
          );
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(appControllerProvider.future);
        final request = container
            .read(appControllerProvider.notifier)
            .refreshPublicIp();
        final checked = expectLater(
          request,
          rejectedByError ? throwsA(isA<PlatformException>()) : completes,
        );
        await tester.pump();
        for (final state in ['reconnecting', 'connected']) {
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            events.name,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'type': 'connectionState',
              'data': {
                'state': state,
                'serverId': 'a',
                'publicIpChecked': false,
              },
            }),
            (_) {},
          );
          await tester.pump();
        }
        if (rejectedByError) {
          reply.completeError(PlatformException(code: 'refresh_rejected'));
        } else {
          reply.complete(false);
        }
        await checked;
        final connection = container
            .read(appControllerProvider)
            .requireValue
            .connection;
        expect(connection.state, 'connected');
        expect(connection.publicIp, isNull);
        expect(connection.publicIpChecked, isFalse);
        await tester.pump(const Duration(seconds: 3));
      },
    );
  }

  testWidgets('usage tap clears and replays to the real consumed proportion', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_HomeController.new)],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(bar).value, .8125);
    await tester.tap(bar);
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(bar).value, 0);
    await tester.pump(const Duration(milliseconds: 250));
    final current = tester.widget<LinearProgressIndicator>(bar).value!;
    expect(current, greaterThan(0));
    expect(current, lessThan(.8125));
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(bar).value, .8125);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public IP refresh removes stale result before response and coalesces taps',
    (tester) async {
      const channel = MethodChannel('dev.nirang.client/control');
      const events = MethodChannel('dev.nirang.client/events');
      final reply = Completer<bool>();
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        events,
        (_) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'initialize') {
          return {
            'settings': <String, Object?>{},
            'servers': <Object?>[],
            'connection': {
              'state': 'connected',
              'serverId': 'a',
              'publicIp': '203.0.113.2',
              'publicIpChecked': true,
            },
          };
        }
        if (call.method == 'refreshPublicIp') {
          calls++;
          return reply.future;
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          events,
          null,
        );
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(appControllerProvider.future);
      final controller = container.read(appControllerProvider.notifier);
      final request = controller.refreshPublicIp();
      final duplicate = controller.refreshPublicIp();
      await tester.pump();
      expect(calls, 1);
      expect(
        container.read(appControllerProvider).requireValue.connection.publicIp,
        isNull,
      );
      expect(
        container
            .read(appControllerProvider)
            .requireValue
            .connection
            .publicIpChecked,
        isFalse,
      );
      reply.complete(true);
      await request;
      await duplicate;
    },
  );
}
