import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_surface.dart';
import '../vpn/app_controller.dart';
import 'server_information_screen.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          servers: app?.servers ?? const <ServerInfo>[],
          isPinging: app?.isPinging ?? false,
          isRefreshing: app?.isRefreshing ?? false,
          configured: app?.subscriptionConfigured ?? false,
          performanceMode: app?.settings.performanceMode ?? false,
        );
      }),
    );
    final app = AppSnapshot(
      servers: view.servers,
      isPinging: view.isPinging,
      isRefreshing: view.isRefreshing,
      subscriptionConfigured: view.configured,
    );
    final controller = ref.read(appControllerProvider.notifier);
    const headerHeight = 64.0;
    return Stack(
      children: [
        Positioned.fill(
          child: app.servers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: headerHeight + 10),
                  child: _EmptyServers(app: app),
                )
              : ListView.separated(
                  cacheExtent: 360,
                  itemCount: app.servers.length,
                  padding: const EdgeInsets.fromLTRB(
                    8,
                    headerHeight + 16,
                    8,
                    16,
                  ),
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (context, index) {
                    final server = app.servers[index];
                    return RepaintBoundary(
                      child: AnimatedContainer(
                        duration: Duration(
                          milliseconds: view.performanceMode ? 85 : 140,
                        ),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: server.selected
                              ? Theme.of(context).colorScheme.primaryContainer
                                    .withValues(alpha: .26)
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow
                                    .withValues(alpha: .42),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: server.selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .28)
                                : Theme.of(context).colorScheme.outlineVariant
                                      .withValues(alpha: .22),
                          ),
                        ),
                        child: ListTile(
                          leading: _SelectionIndicator(
                            selected: server.selected,
                            reducedEffects: view.performanceMode,
                          ),
                          title: Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${server.protocol}  ${server.transport}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Latency(server: server),
                              IconButton(
                                tooltip: context.s('serverActions'),
                                onPressed: () =>
                                    _serverActions(context, controller, server),
                                icon: const Icon(Icons.more_vert_rounded),
                              ),
                            ],
                          ),
                          onTap: () => _perform(
                            context,
                            () => controller.selectServer(server.id),
                          ),
                          onLongPress: () =>
                              _serverActions(context, controller, server),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Positioned(
          top: 6,
          left: 8,
          right: 8,
          child: RepaintBoundary(
            child: _ServersGlassHeader(
              height: headerHeight,
              serverCount: app.servers.length,
              isPinging: app.isPinging,
              isRefreshing: app.isRefreshing,
              reducedEffects: view.performanceMode,
              onPing: app.servers.isEmpty
                  ? null
                  : app.isPinging
                  ? controller.cancelPing
                  : () => _perform(context, controller.pingAll),
              onRefresh: app.isRefreshing
                  ? null
                  : () => _perform(context, controller.refreshSubscription),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _serverActions(
    BuildContext context,
    AppController controller,
    ServerInfo server,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .32),
      builder: (sheetContext) => SafeArea(
        minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: GlassSurface(
          radius: 22,
          blur: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      sheetContext,
                    ).colorScheme.outline.withValues(alpha: .48),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: Text(sheetContext.s('select')),
                  onTap: () => Navigator.pop(sheetContext, 'select'),
                ),
                ListTile(
                  leading: const Icon(Icons.network_ping_rounded),
                  title: Text(sheetContext.s('testLatency')),
                  onTap: () => Navigator.pop(sheetContext, 'ping'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(sheetContext.s('serverInformation')),
                  onTap: () => Navigator.pop(sheetContext, 'info'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    sheetContext.s('delete'),
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    if (action != null) {
      await _handleAction(context, controller, server, action);
    }
  }

  Future<void> _handleAction(
    BuildContext context,
    AppController controller,
    ServerInfo server,
    String action,
  ) async {
    switch (action) {
      case 'select':
        await _perform(context, () => controller.selectServer(server.id));
      case 'ping':
        await _perform(context, () => controller.pingServer(server.id));
      case 'info':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/server-information'),
            builder: (_) => ServerInformationScreen(server: server),
          ),
        );
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.s('deleteServer')),
            content: Text('${context.s('deleteServerBody')}\n\n${server.name}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.s('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.s('delete')),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await _perform(context, () => controller.deleteServer(server.id));
        }
    }
  }
}

class _ServersGlassHeader extends StatelessWidget {
  const _ServersGlassHeader({
    required this.height,
    required this.serverCount,
    required this.isPinging,
    required this.isRefreshing,
    required this.reducedEffects,
    required this.onPing,
    required this.onRefresh,
  });

  final double height;
  final int serverCount;
  final bool isPinging;
  final bool isRefreshing;
  final bool reducedEffects;
  final VoidCallback? onPing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(
          alpha: reducedEffects
              ? .96
              : dark
              ? .70
              : .88,
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: dark ? .48 : .62),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  '${context.s('servers')} ($serverCount)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onPing,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                  isPinging ? Icons.close_rounded : Icons.network_ping_rounded,
                  size: 19,
                ),
                label: Text(
                  isPinging ? context.s('cancel') : context.s('testAll'),
                ),
              ),
              IconButton(
                tooltip: context.s('refresh'),
                onPressed: onRefresh,
                visualDensity: VisualDensity.compact,
                icon: isRefreshing
                    ? const SizedBox.square(
                        dimension: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ],
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: reducedEffects
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: dark ? 10 : 6,
                sigmaY: dark ? 10 : 6,
              ),
              child: content,
            ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({
    required this.selected,
    required this.reducedEffects,
  });

  final bool selected;
  final bool reducedEffects;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Duration(milliseconds: reducedEffects ? 85 : 140),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Colors.transparent,
      border: Border.all(
        width: selected ? 0 : 1.5,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    ),
    child: selected
        ? Icon(
            Icons.check_rounded,
            size: 15,
            color: Theme.of(context).colorScheme.onPrimary,
          )
        : null,
  );
}

class _Latency extends StatelessWidget {
  const _Latency({required this.server});
  final ServerInfo server;
  @override
  Widget build(BuildContext context) {
    if (server.status == 'testing') {
      return Text(
        context.s('testing'),
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      );
    }
    if (server.status == 'timeout') {
      return Text(
        context.s('timeout'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final ping = server.ping;
    if (ping == null) return const SizedBox.shrink();
    final color = ping < 150
        ? context.semanticColors.success
        : ping < 300
        ? context.semanticColors.warning
        : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 58,
      child: Text(
        '$ping ms',
        textAlign: TextAlign.end,
        style: TextStyle(color: color),
      ),
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.app});
  final AppSnapshot app;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            app.subscriptionConfigured
                ? context.s('emptyServers')
                : context.s('notConfigured'),
            textAlign: TextAlign.center,
          ),
          if (!app.subscriptionConfigured) ...[
            const SizedBox(height: 8),
            Text(context.s('configureHint'), textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );
}

Future<void> _perform(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.s('operationFailed')}: $error')),
      );
    }
  }
}
