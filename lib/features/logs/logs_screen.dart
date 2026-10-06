import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent, ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/user_facing_error.dart';
import '../vpn/app_controller.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();
  bool _nearBottom = false;
  bool _selectionActive = false;
  List<LogEntry> _visibleLogs = const [];

  void _selectionChanged(SelectedContent? content) {
    final wasActive = _selectionActive;
    _selectionActive = content != null && content.plainText.isNotEmpty;
    if (wasActive && !_selectionActive) {
      // Keep the selected snapshot intact until the native selection is gone.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_selectionActive) setState(() {});
      });
    }
  }

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
    // Native batches can replace or trim old entries. Applying them during a
    // selection would move its handles or change what the user is copying.
    if (!_selectionActive) _visibleLogs = logs;
    final visibleLogs = _visibleLogs;
    ref.listen(
      appControllerProvider.select((value) {
        final current = value.asData?.value.logs ?? const <LogEntry>[];
        return (
          count: current.length,
          last: current.isEmpty ? 0 : current.last.time.millisecondsSinceEpoch,
        );
      }),
      (_, _) {
        if (!_nearBottom || _selectionActive) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients || _selectionActive) {
            return;
          }
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
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
            child: visibleLogs.isEmpty
                ? Center(child: Text(context.s('noLogs')))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: GlassSurface(
                      showShadow: false,
                      child: SelectionArea(
                        onSelectionChanged: _selectionChanged,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            _nearBottom = notification.metrics.extentAfter < 48;
                            return false;
                          },
                          child: ListView.separated(
                            controller: _scrollController,
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              420,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: visibleLogs.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 38,
                              endIndent: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: .35),
                            ),
                            itemBuilder: (context, index) {
                              final log = visibleLogs[index];
                              final color = switch (log.level) {
                                'error' => Theme.of(context).colorScheme.error,
                                'warning' => context.semanticColors.warning,
                                _ => Theme.of(context).colorScheme.primary,
                              };
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 7),
                                      child: Icon(
                                        Icons.circle,
                                        size: 7,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            log.message,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(height: 1.5),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            formatDateTime(
                                              log.time.millisecondsSinceEpoch,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await showNirangDialog<bool>(
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
            SnackBar(
              content: Text(
                userFacingError(
                  error,
                  persian: Localizations.localeOf(context).languageCode == 'fa',
                ).combined,
              ),
            ),
          );
        }
      }
    }
  }
}
