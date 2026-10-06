import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nirang/core/registration/device_registration.dart';
import 'package:nirang/features/registration/registration_bootstrap.dart';

class _Coordinator implements DeviceRegistrationCoordinator {
  int requests = 0;
  bool blocked = false;
  bool offline = false;
  bool cachedBlock = false;
  bool outdated = false;
  Future<void>? pending;
  @override
  Future<bool> initialize() async {
    if (cachedBlock) throw PlatformException(code: 'blocked');
    return true;
  }

  @override
  Future<void> verifyAccess() async {
    requests++;
    await pending;
    if (blocked) throw PlatformException(code: 'blocked');
    if (outdated) throw PlatformException(code: 'outdated');
    if (offline) throw PlatformException(code: 'network');
  }

  @override
  Future<void> accept() async {}
  @override
  Future<void> exitApplication() async {}
}

void main() {
  testWidgets('refresh can change a saved block into an update requirement', (
    tester,
  ) async {
    final pending = Completer<void>();
    final coordinator = _Coordinator()
      ..cachedBlock = true
      ..outdated = true
      ..pending = pending.future;
    await tester.pumpWidget(
      ProviderScope(
        child: NirangRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('LOCAL_HOME')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access blocked'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Access blocked'), findsNothing);
    expect(find.textContaining('Update required'), findsOneWidget);
    expect(find.text('LOCAL_HOME'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  tearDown(() {
    clearDeviceAccessBlocked();
    clearDeviceUpdateRequired();
  });
  testWidgets(
    'network starts only AFTER saved settings and the first Home frame',
    (tester) async {
      final local = Completer<void>();
      final coordinator = _Coordinator();
      await tester.pumpWidget(
        NirangRegistrationBootstrap(
          coordinator: coordinator,
          prepareApp: () => local.future,
          child: const MaterialApp(home: Text('LOCAL_HOME')),
        ),
      );
      await tester.pump(const Duration(seconds: 12));
      expect(coordinator.requests, 0);
      expect(find.text('LOCAL_HOME'), findsNothing);
      local.complete();
      await tester.pumpAndSettle();
      expect(find.text('LOCAL_HOME'), findsOneWidget);
      expect(coordinator.requests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('offline API cannot delay local Home or create a false block', (
    tester,
  ) async {
    final coordinator = _Coordinator()..offline = true;
    await tester.pumpWidget(
      NirangRegistrationBootstrap(
        coordinator: coordinator,
        child: const MaterialApp(home: Text('LOCAL_HOME')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOCAL_HOME'), findsOneWidget);
    expect(coordinator.requests, 1);
    expect(find.text('LOCAL_HOME'), findsOneWidget);
    expect(deviceAccessBlock.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('deferred explicit administrator denial still replaces Home', (
    tester,
  ) async {
    final pending = Completer<void>();
    final coordinator = _Coordinator()..pending = pending.future;
    await tester.pumpWidget(
      ProviderScope(
        child: NirangRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('LOCAL_HOME')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('LOCAL_HOME'), findsOneWidget);
    coordinator.blocked = true;
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('LOCAL_HOME'), findsNothing);
    expect(find.text('Access blocked'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disposing during local loading never starts API', (
    tester,
  ) async {
    final coordinator = _Coordinator();
    final local = Completer<void>();
    await tester.pumpWidget(
      NirangRegistrationBootstrap(
        coordinator: coordinator,
        prepareApp: () => local.future,
        child: const MaterialApp(home: Text('LOCAL_HOME')),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    local.complete();
    await tester.pump(const Duration(seconds: 8));
    expect(coordinator.requests, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a stalled API stops waiting after seven seconds without hiding Home',
    (tester) async {
      final pending = Completer<void>();
      final coordinator = _Coordinator()..pending = pending.future;
      await tester.pumpWidget(
        NirangRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('LOCAL_HOME')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LOCAL_HOME'), findsOneWidget);
      expect(coordinator.requests, 1);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.text('LOCAL_HOME'), findsOneWidget);
      expect(tester.takeException(), isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(deviceAccessVerified.value, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
