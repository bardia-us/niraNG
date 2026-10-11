// Diagnostic entrypoint only. Production APKs keep lib/main.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nirang/core/diagnostics.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/main.dart' as app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = Stopwatch()..start();
  var count = 0;
  final frames = <Map<String, Object>>[];
  void report() {
    if (frames.isEmpty) return;
    // Stay below Android's per-log-line limit; never dump private app state.
    for (var start = 0; start < frames.length; start += 10) {
      final end = (start + 10).clamp(0, frames.length);
      debugPrint(
        'NIRANG_FRAME_PROBE ${jsonEncode(frames.sublist(start, end))}',
        wrapWidth: 1000000,
      );
    }
    frames.clear();
  }

  void timings(List<FrameTiming> batch) {
    final context = nirangNavigatorKey.currentContext;
    final mode = context == null
        ? 'startup'
        : ProviderScope.containerOf(
            context,
            listen: false,
          ).read(performanceModeProvider)
        ? 'matte'
        : 'glass';
    for (final frame in batch) {
      if (++count > 6000) break;
      frames.add({
        'feature': NirangDiagnostics.currentFeature,
        'mode': mode,
        'atMs': clock.elapsedMilliseconds,
        'vsyncUs': frame.timestampInMicroseconds(FramePhase.vsyncStart),
        'rasterFinishUs': frame.timestampInMicroseconds(
          FramePhase.rasterFinish,
        ),
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
        'totalUs': frame.totalSpan.inMicroseconds,
      });
    }
  }

  SchedulerBinding.instance.addTimingsCallback(timings);
  final timer = Timer.periodic(const Duration(seconds: 2), (_) => report());
  Timer(const Duration(minutes: 3), () {
    SchedulerBinding.instance.removeTimingsCallback(timings);
    timer.cancel();
    report();
  });
  await app.main();
}
