import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';

/// Owns only its small display; traffic never enters the Home app snapshot.
class MeasuredTrafficPanel extends StatefulWidget {
  const MeasuredTrafficPanel({super.key});

  @override
  State<MeasuredTrafficPanel> createState() => _MeasuredTrafficPanelState();
}

class _MeasuredTrafficPanelState extends State<MeasuredTrafficPanel>
    with WidgetsBindingObserver {
  Timer? _timer;
  Map<dynamic, dynamic> _totals = const {};
  bool _reading = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_resumed) _start();
  }

  void _start() {
    _refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_reading || !_resumed) return;
    _reading = true;
    try {
      final totals = await NirangNative.measuredTraffic();
      if (mounted && _resumed) setState(() => _totals = totals);
    } catch (_) {
      if (mounted && _resumed) {
        setState(() => _totals = {..._totals, 'available': false});
      }
    } finally {
      _reading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  String _value(String key, String partialKey) {
    final raw = _totals[key];
    final bytes = raw is int && raw >= 0 ? raw : null;
    if (bytes == null) return '—';
    final partial =
        _totals[partialKey] == true || _totals['available'] == false;
    return '${partial ? '≥ ' : ''}${formatBytes(bytes)}';
  }

  void _showScope() => showNirangDialog<void>(
    context: context,
    builder: (dialogContext) => NirangAlertDialog(
      title: Text(
        context.s('measuredTraffic'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Text(context.s('trafficScope')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.data_usage_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.s('measuredTraffic'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: context.s('measuredTraffic'),
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: _showScope,
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TrafficValue(
                label: context.s('trafficToday'),
                value: _value('todayBytes', 'todayPartial'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _TrafficValue(
                label: context.s('trafficMonth'),
                value: _value('monthBytes', 'monthPartial'),
              ),
            ),
          ],
        ),
        if (_totals['available'] == false && _totals['todayBytes'] != null) ...[
          const SizedBox(height: 6),
          Text(
            context.s('trafficUnavailable'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    ),
  );
}

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: 3),
      Text(
        value,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}
