import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/formatters.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/glass_dialog.dart';
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
          connection: app?.connection ?? const ConnectionInfo(),
        );
      }),
    );
    final app = AppSnapshot(
      servers: view.servers,
      isPinging: view.isPinging,
      isRefreshing: view.isRefreshing,
      subscriptionConfigured: view.configured,
      connection: view.connection,
      settings: NativeSettings(performanceMode: view.performanceMode),
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
              : ReorderableListView.builder(
                  cacheExtent: 360,
                  buildDefaultDragHandles: false,
                  itemCount: app.servers.length,
                  padding: const EdgeInsets.fromLTRB(
                    8,
                    headerHeight + 16,
                    8,
                    16,
                  ),
                  onReorder: (oldIndex, newIndex) {
                    unawaited(
                      _perform(
                        context,
                        () => controller.reorderServers(oldIndex, newIndex),
                      ),
                    );
                  },
                  proxyDecorator: (child, _, animation) => view.performanceMode
                      ? child
                      : AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            final pressed = Curves.easeOutCubic.transform(
                              animation.value,
                            );
                            return Transform.translate(
                              offset: Offset(0, pressed * 2),
                              child: Transform.scale(
                                scale: 1 - (pressed * .015),
                                child: child,
                              ),
                            );
                          },
                        ),
                  itemBuilder: (context, index) {
                    final server = app.servers[index];
                    return Padding(
                      key: ValueKey(server.id),
                      padding: const EdgeInsets.only(bottom: 5),
                      child: RepaintBoundary(
                        child: ReorderableDelayedDragStartListener(
                          index: index,
                          child: _PressScale(
                            enabled: !view.performanceMode,
                            child: AnimatedContainer(
                              duration: Duration(
                                milliseconds: view.performanceMode ? 85 : 140,
                              ),
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                color: server.selected
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: .26)
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow
                                          .withValues(alpha: .42),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: server.selected
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: .28)
                                      : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: .22),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    splashColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: .10),
                                    leading: _SelectionIndicator(
                                      selected: server.selected,
                                      reducedEffects: view.performanceMode,
                                    ),
                                    title: Row(
                                      children: [
                                        CountryFlagBadge(
                                          countryCode: server.country,
                                          width: 25,
                                          height: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            displayServerName(server.name),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
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
                                          onPressed: () => _serverActions(
                                            context,
                                            controller,
                                            server,
                                          ),
                                          icon: const Icon(
                                            Icons.more_vert_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _perform(
                                      context,
                                      () => controller.selectServer(server.id),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
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
              onMenu: (anchor) =>
                  _serverPageActions(context, controller, app, anchor),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _serverPageActions(
    BuildContext context,
    AppController controller,
    AppSnapshot app,
    Rect anchor,
  ) async {
    final size = MediaQuery.sizeOf(context);
    final menuWidth = (size.width - 16).clamp(220.0, 292.0).toDouble();
    final maxLeft = (size.width - menuWidth - 8).clamp(8.0, double.infinity);
    final maxTop = (size.height - 360).clamp(8.0, double.infinity);
    final left = (anchor.right - menuWidth).clamp(8.0, maxLeft);
    final top = (anchor.bottom - 3).clamp(8.0, maxTop);
    final action = await showGeneralDialog<_ServerPageAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.pop(dialogContext),
              onPanStart: (_) => Navigator.pop(dialogContext),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: SafeArea(
              child: GlassSurface(
                radius: 18,
                blur: app.settings.performanceMode ? 0 : 8,
                surfaceOpacity: app.settings.performanceMode ? .97 : .90,
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ServerMenuTile(
                        icon: Icons.restart_alt_rounded,
                        label: dialogContext.s('restartService'),
                        enabled: app.connection.isConnected,
                        action: _ServerPageAction.restart,
                      ),
                      _ServerMenuTile(
                        icon: Icons.sort_rounded,
                        label: dialogContext.s('sortByTestResults'),
                        enabled: app.servers.isNotEmpty,
                        action: _ServerPageAction.sort,
                      ),
                      _ServerMenuTile(
                        icon: Icons.cable_rounded,
                        label: dialogContext.s('testTcpDelays'),
                        enabled: app.servers.isNotEmpty && !app.isPinging,
                        action: _ServerPageAction.tcpDelay,
                      ),
                      _ServerMenuTile(
                        icon: Icons.network_ping_rounded,
                        label: dialogContext.s('testRealDelays'),
                        enabled: app.servers.isNotEmpty && !app.isPinging,
                        action: _ServerPageAction.realDelay,
                      ),
                      _ServerMenuTile(
                        icon: Icons.sync_rounded,
                        label: dialogContext.s('refresh'),
                        enabled: !app.isRefreshing,
                        action: _ServerPageAction.refresh,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(begin: .94, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _ServerPageAction.restart:
        await _perform(context, controller.restartService);
      case _ServerPageAction.sort:
        await _perform(context, controller.sortServersByLatency);
      case _ServerPageAction.realDelay:
        await _perform(context, controller.pingAll);
      case _ServerPageAction.tcpDelay:
        await _perform(context, controller.tcpPingAll);
      case _ServerPageAction.refresh:
        await _perform(context, controller.refreshSubscription);
    }
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
          blur: 16,
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
          builder: (context) => NirangAlertDialog(
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

class _PressScale extends StatefulWidget {
  const _PressScale({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      _pressed = false;
      return widget.child;
    }
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? .982 : 1,
        duration: Duration(milliseconds: _pressed ? 70 : 125),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedSlide(
          offset: _pressed ? const Offset(0, .012) : Offset.zero,
          duration: Duration(milliseconds: _pressed ? 70 : 125),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

class _ServersGlassHeader extends StatefulWidget {
  const _ServersGlassHeader({
    required this.height,
    required this.serverCount,
    required this.isPinging,
    required this.isRefreshing,
    required this.reducedEffects,
    required this.onMenu,
  });

  final double height;
  final int serverCount;
  final bool isPinging;
  final bool isRefreshing;
  final bool reducedEffects;
  final ValueChanged<Rect> onMenu;

  @override
  State<_ServersGlassHeader> createState() => _ServersGlassHeaderState();
}

class _ServersGlassHeaderState extends State<_ServersGlassHeader> {
  final _menuKey = GlobalKey();

  void _openMenu() {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onMenu(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(
          alpha: widget.reducedEffects
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
        height: widget.height,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${context.s('servers')} (${widget.serverCount})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: _menuKey,
                tooltip: context.s('serverPageActions'),
                onPressed: _openMenu,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: widget.reducedEffects
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

enum _ServerPageAction { restart, sort, realDelay, tcpDelay, refresh }

class _ServerMenuTile extends StatelessWidget {
  const _ServerMenuTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.action,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final _ServerPageAction action;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(icon, size: 20),
    title: Text(label),
    enabled: enabled,
    onTap: enabled ? () => Navigator.pop(context, action) : null,
  );
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
    if (server.status == 'failed') {
      return Text(
        context.s('failed'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final ping = server.ping;
    if (ping == null) return const SizedBox.shrink();
    final color = ping <= 199
        ? context.semanticColors.success
        : ping <= 349
        ? context.semanticColors.warning
        : ping <= 599
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFF0A35A)
              : const Color(0xFFCF6B1C))
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
