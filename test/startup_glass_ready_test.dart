import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/startup_loading.dart';
import 'package:nirang/core/registration/device_registration.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/main.dart';

class _Controller extends AppController {
  _Controller(this.performance);
  final bool performance;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(
      performanceMode: performance,
      performanceModePrompted: true,
      feedbackMode: 'off',
    ),
  );
}

void main() {
  for (final performance in [false, true]) {
    testWidgets(
      'startup waits for local optical readiness only in normal mode ($performance)',
      (tester) async {
        final warmUp = Completer<void>();
        var preparations = 0;
        var requests = 0;
        const channel = MethodChannel('dev.nirang.client/control');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'deviceRegistrationStatus') return true;
            if (call.method == 'verifyDeviceAccess') requests++;
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          startupNetworkReady.value = false;
          deviceAccessVerified.value = 0;
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(
                () => _Controller(performance),
              ),
              liveGlassPreparationProvider.overrideWithValue(() {
                preparations++;
                return warmUp.future;
              }),
            ],
            child: const NirangStartup(),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (performance) {
          expect(preparations, 0);
          expect(find.text('Connection status'), findsOneWidget);
        } else {
          expect(preparations, 1);
          expect(find.byType(StartupLoadingScreen), findsOneWidget);
          expect(find.text('Connection status'), findsNothing);
          expect(requests, 0);
          warmUp.complete();
          await tester.pumpAndSettle();
          expect(find.text('Connection status'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
