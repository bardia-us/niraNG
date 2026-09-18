import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/formatters.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/glass_dialog.dart';
import '../vpn/app_controller.dart';
import 'server_information_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  Rect? _menuAnchor;
  ServerInfo? _serverActionsTarget;

  void _openMenu(Rect globalAnchor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    setState(() => _menuAnchor = globalAnchor.shift(-origin));
  }

  bool _handleHeaderScroll(ScrollNotification notification) => false;

  @override
  Widget build(BuildContext context) {
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
          child: RepaintBoundary(
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleHeaderScroll,
                      child: app.servers.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(
                                top: headerHeight + 10,
                              ),
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
                                    () => controller.reorderServers(
                                      oldIndex,
                                      newIndex,
                                    ),
                                  ),
                                );
                              },
                              proxyDecorator: (child, _, animation) =>
                                  view.performanceMode
                                  ? child
                                  : AnimatedBuilder(
                                      animation: animation,
                                      builder: (context, _) {
                                        final pressed = Curves.easeOutCubic
                                            .transform(animation.value);
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
                                            milliseconds: view.performanceMode
                                                ? 85
                                                : 140,
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
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                            border: Border.all(
                                              color: server.selected
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: .28)
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .outlineVariant
                                                        .withValues(alpha: .22),
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: ListTile(
                                                splashColor: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .10),
                                                leading: _SelectionIndicator(
                                                  selected: server.selected,
                                                  reducedEffects:
                                                      view.performanceMode,
                                                ),
                                                title: Row(
                                                  children: [
                                                    CountryFlagBadge(
                                                      countryCode:
                                                          server.country,
                                                      width: 25,
                                                      height: 18,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        displayServerName(
                                                          server.name,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                subtitle: Text(
                                                  '${server.protocol}  ${server.transport}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    _Latency(server: server),
                                                    IconButton(
                                                      tooltip: context.s(
                                                        'serverActions',
                                                      ),
                                                      onPressed: () =>
                                                          _serverActions(
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
                                                  () => controller.selectServer(
                                                    server.id,
                                                  ),
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
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 6,
          left: 8,
          right: 8,
          child: _ServersGlassHeader(
            height: headerHeight,
            serverCount: app.servers.length,
            isPinging: app.isPinging,
            isRefreshing: app.isRefreshing,
            reducedEffects: view.performanceMode,
            onMenu: _openMenu,
          ),
        ),
        if (_menuAnchor case final anchor?)
          Positioned.fill(
            child: _buildServerPageActions(context, controller, app, anchor),
          ),
        if (_serverActionsTarget case final server?)
          Positioned.fill(
            child: _ServerActionsSheetOverlay(
              server: server,
              performanceMode: view.performanceMode,
              onClosed: (action) {
                if (mounted) {
                  setState(() => _serverActionsTarget = null);
                }
                if (action != null && context.mounted) {
                  unawaited(_handleAction(context, controller, server, action));
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _buildServerPageActions(
    BuildContext context,
    AppController controller,
    AppSnapshot app,
    Rect anchor,
  ) {
    final size = MediaQuery.sizeOf(context);
    final menuWidth = (size.width - 16).clamp(220.0, 292.0).toDouble();
    final maxLeft = (size.width - menuWidth - 8).clamp(8.0, double.infinity);
    final maxTop = (size.height - 360).clamp(8.0, double.infinity);
    final left = (anchor.right - menuWidth + 8).clamp(8.0, maxLeft);
    final anchoredTop = anchor.bottom + 5;
    final top = anchoredTop.clamp(8.0, maxTop);
    return _ServerPageActionsPopover(
      left: left,
      top: top,
      width: menuWidth,
      app: app,
      onClosed: (action) {
        if (mounted) {
          setState(() => _menuAnchor = null);
        }
        if (action != null && context.mounted) {
          unawaited(_performServerPageAction(context, controller, action));
        }
      },
    );
  }

  Future<void> _performServerPageAction(
    BuildContext context,
    AppController controller,
    _ServerPageAction action,
  ) async {
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

  void _serverActions(ServerInfo server) {
    if (_serverActionsTarget != null) return;
    setState(() => _serverActionsTarget = server);
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

class _ServerActionsSheetOverlay extends StatefulWidget {
  const _ServerActionsSheetOverlay({
    required this.server,
    required this.performanceMode,
    required this.onClosed,
  });

  final ServerInfo server;
  final bool performanceMode;
  final ValueChanged<String?> onClosed;

  @override
  State<_ServerActionsSheetOverlay> createState() =>
      _ServerActionsSheetOverlayState();
}

class _ServerActionsSheetOverlayState extends State<_ServerActionsSheetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.performanceMode ? 90 : 190),
    reverseDuration: Duration(milliseconds: widget.performanceMode ? 70 : 140),
  );
  bool _closing = false;
  bool _glassReady = false;

  @override
  void initState() {
    super.initState();
    _primeGlass();
  }

  Future<void> _primeGlass() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closing) return;
    setState(() => _glassReady = true);
    _animation.forward();
  }

  Future<void> _close([String? action]) async {
    if (_closing) return;
    _closing = true;
    await _animation.reverse();
    widget.onClosed(action);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _close(),
          ),
        ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 4,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 2),
            child: GlassSurface(
              key: const ValueKey('server-actions-bottom-sheet-surface'),
              radius: 28,
              visibility: _glassReady ? 1 : 0,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(motion),
                child: FadeTransition(
                  opacity: motion,
                  child: Material(
                    color: Colors.transparent,
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
                                context,
                              ).colorScheme.outline.withValues(alpha: .48),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            title: Text(context.s('select')),
                            onTap: () => _close('select'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.network_ping_rounded),
                            title: Text(context.s('testLatency')),
                            onTap: () => _close('ping'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.info_outline_rounded),
                            title: Text(context.s('serverInformation')),
                            onTap: () => _close('info'),
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(
                              context.s('delete'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            onTap: () => _close('delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
    final menuBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    final headerBox = context.findRenderObject() as RenderBox?;
    if (menuBox == null || headerBox == null) return;
    final menuRect = menuBox.localToGlobal(Offset.zero) & menuBox.size;
    final headerRect = headerBox.localToGlobal(Offset.zero) & headerBox.size;
    widget.onMenu(
      Rect.fromLTRB(
        menuRect.left,
        menuRect.top,
        menuRect.right,
        headerRect.bottom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      radius: 26,
      darkBlur: GlassSurface.darkServersHeaderBlur,
      saturation: 1.78,
      tintOpacityScale: .35,
      showShadow: false,
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
  }
}

class _ServerPageActionsPopover extends StatefulWidget {
  const _ServerPageActionsPopover({
    required this.left,
    required this.top,
    required this.width,
    required this.app,
    required this.onClosed,
  });

  final double left;
  final double top;
  final double width;
  final AppSnapshot app;
  final ValueChanged<_ServerPageAction?> onClosed;

  @override
  State<_ServerPageActionsPopover> createState() =>
      _ServerPageActionsPopoverState();
}

class _ServerPageActionsPopoverState extends State<_ServerPageActionsPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: widget.app.settings.performanceMode ? 90 : 170,
    ),
    reverseDuration: Duration(
      milliseconds: widget.app.settings.performanceMode ? 70 : 120,
    ),
  );
  bool _closing = false;
  bool _glassReady = false;

  @override
  void initState() {
    super.initState();
    _primeGlass();
  }

  Future<void> _primeGlass() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closing) return;
    setState(() => _glassReady = true);
    _animation.forward();
  }

  Future<void> _close([_ServerPageAction? action]) async {
    if (_closing) return;
    _closing = true;
    await _animation.reverse();
    widget.onClosed(action);
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _close(),
          ),
        ),
        Positioned(
          left: widget.left,
          top: widget.top,
          width: widget.width,
          child: SafeArea(
            child: GlassSurface(
              key: const ValueKey('server-page-actions-surface'),
              radius: 26,
              blur: GlassSurface.liquidBlur,
              darkBlur: GlassSurface.darkServersTopMenuBlur,
              visibility: _glassReady ? 1 : 0,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.018),
                  end: Offset.zero,
                ).animate(curved),
                child: FadeTransition(
                  opacity: curved,
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ServerMenuTile(
                          icon: Icons.restart_alt_rounded,
                          label: context.s('restartService'),
                          enabled: widget.app.connection.isConnected,
                          onTap: () => _close(_ServerPageAction.restart),
                        ),
                        _ServerMenuTile(
                          icon: Icons.sort_rounded,
                          label: context.s('sortByTestResults'),
                          enabled: widget.app.servers.isNotEmpty,
                          onTap: () => _close(_ServerPageAction.sort),
                        ),
                        _ServerMenuTile(
                          icon: Icons.cable_rounded,
                          label: context.s('testTcpDelays'),
                          enabled:
                              widget.app.servers.isNotEmpty &&
                              !widget.app.isPinging,
                          onTap: () => _close(_ServerPageAction.tcpDelay),
                        ),
                        _ServerMenuTile(
                          icon: Icons.network_ping_rounded,
                          label: context.s('testRealDelays'),
                          enabled:
                              widget.app.servers.isNotEmpty &&
                              !widget.app.isPinging,
                          onTap: () => _close(_ServerPageAction.realDelay),
                        ),
                        _ServerMenuTile(
                          icon: Icons.sync_rounded,
                          label: context.s('refresh'),
                          enabled: !widget.app.isRefreshing,
                          onTap: () => _close(_ServerPageAction.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _ServerPageAction { restart, sort, realDelay, tcpDelay, refresh }

class _ServerMenuTile extends StatelessWidget {
  const _ServerMenuTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    leading: Icon(icon, size: 20),
    title: Text(label),
    enabled: enabled,
    onTap: enabled ? onTap : null,
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
