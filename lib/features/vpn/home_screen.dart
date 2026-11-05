import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/server_name_text.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/decorative_glass_surface.dart';
import '../../core/widgets/liquid_controls.dart';
import '../../core/widgets/clay_surface.dart';
import 'app_controller.dart';
import 'measured_traffic_panel.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/connection_diagnostics_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          servers: app?.servers ?? const <ServerInfo>[],
          connection: app?.connection ?? const ConnectionInfo(),
          usage: app?.usage ?? const SubscriptionUsage(),
          configured: app?.subscriptionConfigured ?? false,
          error: app?.subscriptionError,
        );
      }),
    );
    final app = AppSnapshot(
      servers: view.servers,
      connection: view.connection,
      usage: view.usage,
      subscriptionConfigured: view.configured,
      subscriptionError: view.error,
    );
    final controller = ref.read(appControllerProvider.notifier);
    return RefreshIndicator(
      edgeOffset: MediaQuery.paddingOf(context).top + 6,
      displacement: 28,
      onRefresh: controller.refreshSubscription,
      child: DecorativeGlassScope(
        child: ListView(
          controller: _scrollController,
          // Ordinary Flutter painting: async Ping/IP labels now repaint
          // their own row instead of invalidating a full-page optical pass.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.paddingOf(context).top + 6,
            16,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            SizeChangedLayoutNotifier(
              child: _ConnectionCard(
                app: app,
                controller: controller,
                reducedEffects: MediaQuery.disableAnimationsOf(context),
              ),
            ),
            if (app.subscriptionError != null) ...[
              const SizedBox(height: 8),
              Text(
                app.subscriptionError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            _SubscriptionSection(usage: app.usage),
            const SizedBox(height: 12),
            const MeasuredTrafficPanel(),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.app,
    required this.controller,
    required this.reducedEffects,
  });

  final AppSnapshot app;
  final AppController controller;
  final bool reducedEffects;

  @override
  Widget build(BuildContext context) {
    final selected = app.selectedServer;
    final connection = app.connection;
    final statusColor = _statusColor(context, connection.state);
    final countryCode = connection.publicCountry?.trim().toUpperCase();
    final publicIp = connection.publicIp;
    final isPsiphon =
        selected?.profileKind == 'aether' && selected!.psiphonEnabled;
    final observedCountry =
        connection.isConnected &&
            connection.serverId == selected?.id &&
            connection.publicIpChecked &&
            publicIp != null &&
            publicIp.isNotEmpty &&
            countryCode != null &&
            RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)
        ? countryCode
        : '';
    final publicIpValue = publicIp == null
        ? (connection.isConnected && !connection.publicIpChecked
              ? context.s('checking')
              : '—')
        : countryCode != null && countryCode.length == 2
        ? '($countryCode) $publicIp'
        : publicIp;
    return GlassSurface(
      padding: const EdgeInsets.all(16),
      // Restart animates its own layout extent. Everything below follows that
      // extent, instead of jumping inside an independently animated clip.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ConnectionShield(
                state: connection.state,
                color: statusColor,
                connected: connection.isConnected,
                reducedEffects:
                    reducedEffects || MediaQuery.disableAnimationsOf(context),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.s('status'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.s(connection.state),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              _ConnectionAction(connection: connection, controller: controller),
            ],
          ),
          if (connection.error?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              connection.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(),
          ),
          Row(
            textDirection: TextDirection.ltr,
            children: [
              Expanded(
                child: Text(
                  context.s('selectedServer').toUpperCase(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(letterSpacing: .75),
                ),
              ),
              const SizedBox(width: 8),
              ClaySurface(
                radius: 13,
                child: IconButton(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  tooltip: Localizations.localeOf(context).languageCode == 'fa'
                      ? 'بررسی اتصال'
                      : 'Check connection',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  iconSize: 19,
                  onPressed: () => showNirangDialog<void>(
                    context: context,
                    builder: (_) => const ConnectionDiagnosticsDialog(),
                  ),
                  icon: const Icon(Icons.troubleshoot_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (selected == null)
            Text(
              app.subscriptionConfigured
                  ? context.s('emptyServers')
                  : context.s('notConfigured'),
            )
          else ...[
            Row(
              children: [
                CountryFlagBadge(
                  key: const ValueKey('selected-server-country'),
                  countryCode: isPsiphon ? observedCountry : selected.country,
                  width: 31,
                  height: 23,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ServerNameText(
                        selected.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${selected.protocol} · ${selected.transport} · ${selected.security}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (selected.profileKind == 'aether' &&
                connection.serverId == selected.id &&
                connection.aetherEndpoint != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  '${Localizations.localeOf(context).languageCode == 'fa' ? 'آدرس اتصال' : 'Endpoint'}: ${connection.aetherEndpoint}${connection.aetherInnerEndpoint == null ? '' : ' → ${connection.aetherInnerEndpoint}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CompactMetric(
                    icon: Icons.public_rounded,
                    label: context.s('publicIp'),
                    value: publicIpValue,
                    subtitle: connection.publicCity,
                    fitValue: true,
                    busy: connection.isConnected && !connection.publicIpChecked,
                    onTap: connection.isConnected
                        ? () => _perform(context, controller.refreshPublicIp)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactMetric(
                    icon: Icons.network_ping_rounded,
                    label: context.s('ping'),
                    value: switch (selected.status) {
                      'testing' => context.s('testing'),
                      'timeout' => context.s('timeout'),
                      'failed' => context.s('failed'),
                      _ => selected.ping == null ? '—' : '${selected.ping} ms',
                    },
                    onTap: () => _perform(
                      context,
                      () => controller.pingServer(selected.id),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionAction extends StatelessWidget {
  const _ConnectionAction({required this.connection, required this.controller});

  final ConnectionInfo connection;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final canCancel = connection.isBusy && connection.state != 'stopping';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        LiquidConnectButton(
          onPressed: connection.isConnected || canCancel
              ? () => _perform(context, controller.disconnect)
              : connection.canConnect
              ? () => _perform(context, controller.connect)
              : null,
          icon: connection.isConnected
              ? const Icon(Icons.stop_rounded, size: 18)
              : connection.isBusy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 19),
          label: context.s(
            connection.isConnected
                ? 'disconnect'
                : canCancel
                ? 'cancel'
                : connection.isBusy
                ? connection.state
                : 'connect',
          ),
        ),
        AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion ? 0 : 360),
          reverseDuration: Duration(milliseconds: reduceMotion ? 0 : 300),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: connection.isConnected
              ? Padding(
                  key: const ValueKey('restart-visible'),
                  padding: const EdgeInsets.only(top: 5),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                    ),
                    onPressed: () =>
                        _perform(context, controller.restartService),
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                    label: Text(context.s('restartService')),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('restart-hidden')),
        ),
      ],
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.subtitle,
    this.fitValue = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool fitValue;
  final bool busy;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(11),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: busy
                ? SizedBox.square(
                    key: const ValueKey('checking-ip'),
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : Icon(
                    icon,
                    key: const ValueKey('metric-ready'),
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                if (fitValue)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  )
                else
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({required this.usage});
  final SubscriptionUsage usage;

  void _showScope(BuildContext context) {
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final total = usage.total;
    final allowance = total != null && total > 0
        ? (persian
              ? 'سهمیهٔ شما ${formatBytes(total)} است.'
              : 'Your allowance is ${formatBytes(total)}.')
        : (persian
              ? 'مقدار سهمیه را پلن اشتراک شما مشخص می‌کند.'
              : 'Your subscription plan defines the allowance.');
    showNirangDialog<void>(
      context: context,
      builder: (dialogContext) => NirangAlertDialog(
        title: Text(
          context.s('subscriptionUsage'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                persian
                    ? 'این سهمیه فقط برای کانفیگ‌های اختصاصی اشتراک است. $allowance هر روز ساعت ۰۰:۰۰ (۱۲ شب) خودکار شارژ می‌شود.'
                    : 'This allowance is only for dedicated subscription configs. $allowance It recharges automatically every day at 00:00 (midnight).',
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: DiagnosticAction(
                  label: MaterialLocalizations.of(context).closeButtonLabel,
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUsage = usage.used != null || usage.unlimited;
    final progress =
        usage.total != null && usage.total! > 0 && usage.used != null
        ? (usage.used! / usage.total!).clamp(0.0, 1.0)
        : null;
    return _Section(
      icon: Icons.data_usage_rounded,
      title: context.s('subscriptionUsage'),
      onHelp: () => _showScope(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 15),
        child: !hasUsage
            ? Text(context.s('subscriptionUsageUnknown'))
            : Column(
                children: [
                  _ValueRow(
                    label: context.s('used'),
                    value: formatBytes(usage.used),
                    strong: true,
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 9),
                    _ReplayUsageBar(value: progress),
                    const SizedBox(height: 7),
                  ],
                  _ValueRow(
                    label: context.s('remaining'),
                    value: usage.unlimited
                        ? context.s('unlimited')
                        : formatBytes(usage.remaining),
                  ),
                  if (usage.expire != null && usage.expire! > 0)
                    _ValueRow(
                      label: context.s('expires'),
                      value: formatDateTime(
                        usage.expire! * 1000,
                        dateOnly: true,
                      ),
                    ),
                  if (usage.expired)
                    _ValueRow(
                      label: context.s('status'),
                      value: context.s('expired'),
                      valueColor: Theme.of(context).colorScheme.error,
                    ),
                ],
              ),
      ),
    );
  }
}

class _ReplayUsageBar extends StatefulWidget {
  const _ReplayUsageBar({required this.value});
  final double value;
  @override
  State<_ReplayUsageBar> createState() => _ReplayUsageBarState();
}

class _ReplayUsageBarState extends State<_ReplayUsageBar>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.s('subscriptionUsage'),
    value: '${(widget.value * 100).round()}%',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!MediaQuery.disableAnimationsOf(context)) {
          _animation.forward(from: 0);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final t = MediaQuery.disableAnimationsOf(context)
                ? 1.0
                : Curves.easeOutCubic.transform(_animation.value);
            return Transform.scale(
              scale: 1 + .02 * (1 - t),
              child: SizedBox(
                height: 6,
                width: double.infinity,
                child: CustomPaint(
                  painter: _CapsuleUsagePainter(
                    value: widget.value * t,
                    color: Theme.of(context).colorScheme.primary,
                    trackColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    textDirection: Directionality.of(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _CapsuleUsagePainter extends CustomPainter {
  const _CapsuleUsagePainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.textDirection,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final height = math.min(size.height, size.width);
    final radius = height / 2;
    final top = (size.height - height) / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, size.width, height),
      Radius.circular(radius),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    final fraction = value.clamp(0.0, 1.0);
    if (fraction == 0) return;

    // A short fill stays round without claiming a minimum amount of usage.
    // Its painted area is exactly the same fraction of the capsule track.
    final capArea = math.pi * radius * radius;
    final area = (height * (size.width - height) + capArea) * fraction;
    final paint = Paint()..color = color;
    canvas.save();
    if (textDirection == TextDirection.rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    if (area <= capArea) {
      canvas.drawCircle(
        Offset(radius, size.height / 2),
        math.sqrt(area / math.pi),
        paint,
      );
    } else {
      final width = (area - capArea) / height + height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, width, height),
          Radius.circular(radius),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CapsuleUsagePainter oldDelegate) =>
      value != oldDelegate.value ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor ||
      textDirection != oldDelegate.textDirection;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.onHelp,
  });
  final IconData icon;
  final String title;
  final Widget child;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) => GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (onHelp != null)
                IconButton(
                  tooltip: title,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onHelp,
                  icon: const Icon(Icons.help_outline_rounded),
                ),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

Color _statusColor(BuildContext context, String state) => switch (state) {
  'connected' => context.semanticColors.success,
  'error' => Theme.of(context).colorScheme.error,
  'connecting' ||
  'preparing' ||
  'restarting' ||
  'switching' ||
  'reconnecting' ||
  'stopping' => context.semanticColors.warning,
  _ => Theme.of(context).colorScheme.outline,
};

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
