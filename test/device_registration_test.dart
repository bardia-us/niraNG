import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/registration/device_registration.dart';
import 'package:nirang/features/registration/registration_bootstrap.dart';

void main() {
  testWidgets('Home is not built until Android registration consent is saved', (
    tester,
  ) async {
    final coordinator = _FakeCoordinator();
    await tester.pumpWidget(
      ProviderScope(
        child: NirangRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOME_READY'), findsNothing);
    expect(find.text('Accept & Continue'), findsOneWidget);
    expect(find.textContaining('does not collect IMEI'), findsOneWidget);

    await tester.ensureVisible(find.text('Accept & Continue'));
    await tester.tap(find.text('Accept & Continue'));
    await tester.pumpAndSettle();

    expect(coordinator.accepts, 1);
    expect(find.text('HOME_READY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Exit does not grant consent', (tester) async {
    final coordinator = _FakeCoordinator();
    await tester.pumpWidget(
      ProviderScope(
        child: NirangRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Exit'));
    await tester.tap(find.text('Exit'));
    await tester.pump();

    expect(coordinator.exits, 1);
    expect(coordinator.accepts, 0);
    expect(find.text('HOME_READY'), findsNothing);
  });
}

final class _FakeCoordinator implements DeviceRegistrationCoordinator {
  int accepts = 0;
  int exits = 0;

  @override
  Future<bool> initialize() async => false;

  @override
  Future<void> accept() async {
    accepts++;
  }

  @override
  Future<void> exitApplication() async {
    exits++;
  }
}
