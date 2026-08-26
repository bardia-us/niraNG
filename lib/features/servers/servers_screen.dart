import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 10, 8),
          child: Row(
            children: [
              Text(
                '${app.servers.length} ${context.s('serverCount')}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (app.isPinging)
                TextButton.icon(
                  onPressed: controller.cancelPing,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(context.s('cancel')),
                )
              else
                TextButton.icon(
                  onPressed: app.servers.isEmpty
                      ? null
                      : () => _perform(context, controller.pingAll),
                  icon: const Icon(Icons.network_ping_rounded),
                  label: Text(context.s('testAll')),
                ),
              IconButton(
                tooltip: context.s('refresh'),
                onPressed: app.isRefreshing
                    ? null
                    : () => _perform(context, controller.refreshSubscription),
                icon: app.isRefreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: app.servers.isEmpty
              ? _EmptyServers(app: app)
              : ListView.separated(
                  cacheExtent: 360,
                  itemCount: app.servers.length,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (context, index) {
                    final server = app.servers[index];
                    return RepaintBoundary(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
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
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(context.s('select')),
                onTap: () => Navigator.pop(context, 'select'),
              ),
              ListTile(
                leading: const Icon(Icons.network_ping_rounded),
                title: Text(context.s('testLatency')),
                onTap: () => Navigator.pop(context, 'ping'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.s('serverInformation')),
                onTap: () => Navigator.pop(context, 'info'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  context.s('delete'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
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

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 140),
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
