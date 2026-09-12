import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../vpn/app_controller.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();
  bool _nearBottom = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.logs ?? const <LogEntry>[],
      ),
    );
    ref.listen(
      appControllerProvider.select((value) {
        final current = value.asData?.value.logs ?? const <LogEntry>[];
        return (
          count: current.length,
          last: current.isEmpty ? 0 : current.last.time.millisecondsSinceEpoch,
        );
      }),
      (_, _) {
        if (!_nearBottom) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          );
        });
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _nearBottom = _scrollController.position.extentAfter < 48;
    });
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const GlassSurface(
          radius: 0,
          style: NirangGlassStyle.chrome,
          showShadow: false,
          showBorder: false,
          child: SizedBox.expand(),
        ),
        title: Text(context.s('logs')),
        actions: [
          IconButton(
            tooltip: context.s('refresh'),
            onPressed: ref.read(appControllerProvider.notifier).refreshLogs,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: context.s('clear'),
            onPressed: logs.isEmpty ? null : () => _confirmClear(context, ref),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: logs.isEmpty
                ? Center(child: Text(context.s('noLogs')))
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      _nearBottom = notification.metrics.extentAfter < 48;
                      return false;
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      cacheExtent: 420,
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const Divider(indent: 50),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final color = switch (log.level) {
                          'error' => Theme.of(context).colorScheme.error,
                          'warning' => context.semanticColors.warning,
                          _ => Theme.of(context).colorScheme.primary,
                        };
                        return ListTile(
                          leading: Icon(Icons.circle, size: 9, color: color),
                          title: Text(
                            log.message,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            formatDateTime(log.time.millisecondsSinceEpoch),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => NirangAlertDialog(
        title: Text(context.s('clearLogs')),
        content: Text(context.s('clearLogsBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.s('clear')),
          ),
        ],
      ),
    );
    if (clear == true) {
      try {
        await ref.read(appControllerProvider.notifier).clearLogs();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.s('operationFailed')}: $error')),
          );
        }
      }
    }
  }
}
