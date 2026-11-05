import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'diagnostics.dart';

/// An explicitly started, memory-only capture. FrameTiming measures Flutter's
/// UI/raster work, not hardware GPU utilization or display-presented FPS.
class UiLagCapture extends ChangeNotifier with WidgetsBindingObserver {
  UiLagCapture._();
  static final instance = UiLagCapture._();
  static const _limit = 4096;
  final _build = Int64List(_limit);
  final _raster = Int64List(_limit);
  final _total = Int64List(_limit);
  final _start = Int64List(_limit);
  final _scenes = <String>[];
  Timer? _timer, _drain;
  int? _scheduledFrame;
  int _count = 0, _origin = 0, _end = 0, _ticks = 0;
  bool active = false, finishing = false, cancelled = false;
  bool showReadyBanner = false;
  bool _full = false, _listening = false;
  Map<String, Object?>? result;
  Map<String, Object?> _metadata = {};
  double? _refresh;
  int get remaining => (20 - _ticks).clamp(0, 20);

  void start({
    required ui.FlutterView view,
    required Map<dynamic, dynamic> device,
    required bool performanceMode,
    required bool glassReady,
  }) {
    if (active || finishing) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      cancel();
      return;
    }
    result = null;
    showReadyBanner = false;
    cancelled = false;
    _count = _ticks = 0;
    _full = false;
    _scenes.clear();
    final hz = view.display.refreshRate;
    _refresh = hz.isFinite && hz >= 1 && hz <= 1000 ? hz : null;
    _metadata = {
      'schema_version': 1,
      'requested_duration_ms': 20000,
      'refresh_rate_hz': _refresh,
      'display': {
        'pixel_ratio': view.devicePixelRatio.clamp(0.01, 10),
        'width_px': view.physicalSize.width.round().clamp(1, 20000),
        'height_px': view.physicalSize.height.round().clamp(1, 20000),
      },
      'device': _device(device),
      'settings': {
        'performance_mode': performanceMode,
        'glass_ready': glassReady,
      },
    };
    active = true;
    WidgetsBinding.instance.addObserver(this);
    // Start on an actual engine frame: this clock shares FrameTiming's epoch.
    // currentFrameTimeStamp is time-dilated and must not be used here.
    _scheduledFrame = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduledFrame = null;
      if (!active) return;
      _origin =
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      _end = _origin + 20000000;
      _scene();
      SchedulerBinding.instance.addTimingsCallback(_timings);
      _listening = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _ticks = timer.tick;
        _scene();
        if (_ticks >= 20) {
          active = false;
          finishing = true;
          _timer?.cancel();
          // Release builds batch FrameTiming roughly once per second. Keep a
          // bounded drain window and reject frames starting after the cutoff.
          _drain = Timer(const Duration(milliseconds: 1100), _finish);
        }
        notifyListeners();
      });
    });
    notifyListeners();
  }

  static Map<String, Object?> _device(Map<dynamic, dynamic> data) {
    String label(Object? value) {
      if (value is! String) return '';
      final out = StringBuffer();
      var bytes = 0;
      for (final rune in value.runes) {
        final part = String.fromCharCode(rune);
        final length = utf8.encode(part).length;
        if (bytes + length > 80) break;
        out.write(part);
        bytes += length;
      }
      return out.toString();
    }

    final sdk = data['android_sdk'];
    final thermal = data['thermal_status'];
    return {
      'manufacturer': label(data['manufacturer']),
      'model': label(data['model']),
      'android_sdk': sdk is int && sdk >= 21 && sdk <= 1000 ? sdk : null,
      'soc_model': data['soc_model'] is String
          ? label(data['soc_model'])
          : null,
      'power_save': data['power_save'] is bool ? data['power_save'] : null,
      'thermal_status': thermal is int && thermal >= 0 && thermal <= 6
          ? thermal
          : null,
    };
  }

  void _scene() {
    final feature = NirangDiagnostics.currentRoute == '/feedback'
        ? 'feedback'
        : NirangDiagnostics.currentFeature;
    final scene =
        const [
          'startup',
          'home',
          'servers',
          'settings',
          'feedback',
        ].contains(feature)
        ? feature
        : 'other';
    if (_scenes.length < 8 && !_scenes.contains(scene)) _scenes.add(scene);
  }

  void _timings(List<ui.FrameTiming> frames) {
    if (!active && !finishing) return;
    for (final frame in frames) {
      final start = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
      if (start < _origin || start >= _end) continue;
      if (_count >= _limit) {
        _full = true;
        continue;
      }
      _start[_count] = start;
      _build[_count] =
          frame.timestampInMicroseconds(ui.FramePhase.buildFinish) - start;
      _raster[_count] =
          frame.timestampInMicroseconds(ui.FramePhase.rasterFinish) -
          frame.timestampInMicroseconds(ui.FramePhase.rasterStart);
      _total[_count] =
          frame.timestampInMicroseconds(ui.FramePhase.rasterFinish) -
          frame.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      _count++;
    }
  }

  Map<String, Object?> _aggregate(int from, int to) {
    final builds = <int>[],
        rasters = <int>[],
        totals = <int>[],
        intervals = <int>[];
    var buildOver = 0, rasterOver = 0, totalOver = 0;
    final budget = _refresh == null ? null : 1000000 / _refresh!;
    for (var i = from; i < to; i++) {
      builds.add(_build[i].clamp(0, 60000000));
      rasters.add(_raster[i].clamp(0, 60000000));
      totals.add(_total[i].clamp(0, 60000000));
      if (budget != null && _build[i] > budget) buildOver++;
      if (budget != null && _raster[i] > budget) rasterOver++;
      if (budget != null && _total[i] > budget) totalOver++;
      if (i > from && _start[i] > _start[i - 1]) {
        intervals.add((_start[i] - _start[i - 1]).clamp(0, 60000000));
      }
    }
    return {
      'frames': to - from,
      'interval_samples': intervals.length,
      'build_over_budget_frames': buildOver,
      'raster_over_budget_frames': rasterOver,
      'total_over_budget_frames': totalOver,
      'build_ms': _stats(builds),
      'raster_ms': _stats(rasters),
      'total_span_ms': _stats(totals),
      'flutter_interval_ms': _stats(intervals),
    };
  }

  static Map<String, Object?>? _stats(List<int> values) {
    if (values.isEmpty) return null;
    values.sort();
    double p(double fraction) =>
        values[((values.length * fraction).ceil() - 1).clamp(
          0,
          values.length - 1,
        )] /
        1000;
    return {
      'p50': p(.5),
      'p95': p(.95),
      'p99': p(.99),
      'max': values.last / 1000,
    };
  }

  void _detach() {
    _timer?.cancel();
    _drain?.cancel();
    if (_scheduledFrame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_scheduledFrame!);
    }
    _scheduledFrame = null;
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      _listening = false;
    }
    WidgetsBinding.instance.removeObserver(this);
  }

  void _finish() {
    _detach();
    active = finishing = false;
    var split = 0;
    while (split < _count && _start[split] < _origin + 5000000) {
      split++;
    }
    result = {
      ..._metadata,
      'duration_ms': 20000,
      'sample_limit_reached': _full,
      'scenes': List<String>.of(_scenes),
      'phases': {
        'all': _aggregate(0, _count),
        'initial_5s': _aggregate(0, split),
        'warm': _aggregate(split, _count),
      },
    };
    showReadyBanner = true;
    notifyListeners();
  }

  void dismissBanner() {
    showReadyBanner = false;
    notifyListeners();
  }

  void cancel() {
    _detach();
    active = finishing = false;
    cancelled = true;
    showReadyBanner = false;
    result = null;
    notifyListeners();
  }

  void clear() {
    result = null;
    showReadyBanner = false;
    cancelled = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((active || finishing) && state != AppLifecycleState.resumed) cancel();
  }
}

/// Mount above the navigator so recording survives leaving Feedback. Rebuilds
/// only this small banner once a second; never requests continuous app frames.
class UiLagCaptureOverlay extends StatefulWidget {
  const UiLagCaptureOverlay({
    required this.child,
    this.onOpenReport,
    super.key,
  });
  final Widget child;
  final VoidCallback? onOpenReport;
  @override
  State<UiLagCaptureOverlay> createState() => _UiLagCaptureOverlayState();
}

class _UiLagCaptureOverlayState extends State<UiLagCaptureOverlay> {
  @override
  void dispose() {
    final capture = UiLagCapture.instance;
    if (capture.active || capture.finishing) capture.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned(
        top: 0,
        left: 12,
        right: 12,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: UiLagCapture.instance,
            builder: (context, _) {
              final capture = UiLagCapture.instance;
              if (!capture.active &&
                  !capture.finishing &&
                  !capture.showReadyBanner) {
                return const SizedBox.shrink();
              }
              final fa = Localizations.localeOf(context).languageCode == 'fa';
              final seconds = fa
                  ? '${capture.remaining}'
                        .split('')
                        .map((d) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(d)])
                        .join()
                  : '${capture.remaining}';
              return Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.speed_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          capture.showReadyBanner
                              ? (fa ? 'گزارش لگ آماده است' : 'UI report ready')
                              : capture.finishing
                              ? (fa
                                    ? 'آماده‌سازی گزارش لگ…'
                                    : 'Preparing UI report…')
                              : (fa
                                    ? 'ثبت لگ: $seconds ثانیه'
                                    : 'UI capture: ${capture.remaining}s'),
                        ),
                      ),
                      if (capture.showReadyBanner) ...[
                        if (widget.onOpenReport != null)
                          TextButton(
                            onPressed: () {
                              capture.dismissBanner();
                              widget.onOpenReport!();
                            },
                            child: Text(fa ? 'مشاهده' : 'View report'),
                          ),
                        IconButton(
                          onPressed: capture.dismissBanner,
                          tooltip: fa ? 'بستن' : 'Dismiss',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ] else
                        TextButton(
                          onPressed: capture.cancel,
                          child: Text(fa ? 'لغو' : 'Cancel'),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
