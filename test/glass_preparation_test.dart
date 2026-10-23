import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/widgets/glass_preparation.dart';

void main() {
  test(
    'normal startup loads premium before advertising optical readiness',
    () async {
      var programsLoaded = false;
      final preparation = GlassPreparation(
        supported: () => true,
        initialize: (mode) async {
          // The real library skips both premium programs when passed `never`.
          programsLoaded = mode == glass.GlassWarmUpMode.always;
        },
        programsReady: () => programsLoaded,
      );
      await preparation.prepare();
      expect(preparation.ready.value, isTrue);
    },
  );

  test('concurrent readiness requests share one pending shader load', () async {
    var loads = 0;
    final loaded = Completer<void>();
    final preparation = GlassPreparation(
      supported: () => true,
      initialize: (_) {
        loads++;
        return loaded.future;
      },
      programsReady: () => true,
    );
    final first = preparation.prepare();
    final second = preparation.prepare();
    expect(loads, 1);
    expect(preparation.ready.value, isFalse);
    loaded.complete();
    await Future.wait([first, second]);
    expect(preparation.ready.value, isTrue);
  });

  test(
    'unsupported or failed loading keeps the visible non-optical fallback',
    () async {
      var calls = 0;
      final unsupported = GlassPreparation(
        supported: () => false,
        initialize: (_) async {
          calls++;
        },
        programsReady: () => true,
      );
      await unsupported.prepare();
      expect(calls, 0);
      expect(unsupported.ready.value, isFalse);
      final failed = GlassPreparation(
        supported: () => true,
        initialize: (_) async => throw StateError('shader unavailable'),
        programsReady: () => true,
      );
      await failed.prepare();
      expect(failed.ready.value, isFalse);
    },
  );

  testWidgets(
    'a slow shader load does not permanently lock normal mode to fallback',
    (tester) async {
      final loaded = Completer<void>();
      final preparation = GlassPreparation(
        supported: () => true,
        initialize: (_) => loaded.future,
        programsReady: () => loaded.isCompleted,
      );
      final boundedStartup = preparation.prepare();
      await tester.pump(const Duration(seconds: 3));
      await boundedStartup;
      expect(preparation.ready.value, isFalse);
      loaded.complete();
      await tester.pump();
      expect(preparation.ready.value, isTrue);
    },
  );

  test(
    'a loader Future completing without actual programs is not ready',
    () async {
      final preparation = GlassPreparation(
        supported: () => true,
        initialize: (_) async {},
        programsReady: () => false,
      );
      await preparation.prepare();
      expect(preparation.ready.value, isFalse);
    },
  );
}
