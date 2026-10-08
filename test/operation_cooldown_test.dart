import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/async_operation_guard.dart';

void main() {
  testWidgets('failed commands cool down and then recover', (tester) async {
    var elapsed = Duration.zero;
    final guard = AsyncOperationGuard(elapsed: () => elapsed);
    await expectLater(
      guard.run('ping', () async {
        throw StateError('probe failed');
      }),
      throwsStateError,
    );
    var accepted = 0;
    Future<void> retry() async {
      accepted++;
    }

    elapsed = const Duration(milliseconds: 499);
    await guard.run('ping', retry);
    expect(accepted, 0);
    elapsed = const Duration(milliseconds: 500);
    await guard.run('ping', retry);
    expect(accepted, 1);
  });

  testWidgets('disconnect remains available during an active connect request', (
    tester,
  ) async {
    final guard = AsyncOperationGuard();
    final connecting = Completer<void>();
    final connect = guard.run('connect', () => connecting.future);
    var stopped = false;
    await guard.run('disconnect', () async {
      stopped = true;
    });
    expect(stopped, isTrue);
    connecting.complete();
    await connect;
  });
  testWidgets(
    'fast operations reject repeats for 500ms without delaying first call',
    (tester) async {
      var elapsed = Duration.zero;
      final guard = AsyncOperationGuard(elapsed: () => elapsed);
      var calls = 0;
      Future<void> command() async {
        calls++;
      }

      final first = guard.run('disconnect', command);
      expect(calls, 1);
      await first;
      await tester.pump(const Duration(milliseconds: 499));
      elapsed += const Duration(milliseconds: 499);
      await guard.run('disconnect', command);
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      elapsed += const Duration(milliseconds: 1);
      await guard.run('disconnect', command);
      expect(calls, 2);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'long commands stay single-flight and get cooldown after completion',
    (tester) async {
      var elapsed = Duration.zero;
      final guard = AsyncOperationGuard(elapsed: () => elapsed);
      final release = Completer<void>();
      var calls = 0;
      Future<void> command() async {
        calls++;
        await release.future;
      }

      final first = guard.run('ping', command);
      final duplicate = guard.run('ping', command);
      await tester.pump(const Duration(seconds: 2));
      elapsed += const Duration(seconds: 2);
      expect(calls, 1);
      release.complete();
      await Future.wait([first, duplicate]);
      await tester.pump(const Duration(milliseconds: 499));
      elapsed += const Duration(milliseconds: 499);
      await guard.run('ping', command);
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      elapsed += const Duration(milliseconds: 1);
      await guard.run('ping', command);
      expect(calls, 2);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
}
