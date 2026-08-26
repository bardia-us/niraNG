import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_surface.dart';
import 'app_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      onRefresh: controller.refreshSubscription,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _ConnectionCard(app: app, controller: controller),
          if (app.subscriptionError != null) ...[
            const SizedBox(height: 8),
            Text(
              app.subscriptionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          _SubscriptionSection(usage: app.usage),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.app, required this.controller});

  final AppSnapshot app;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final selected = app.selectedServer;
    final connection = app.connection;
    final statusColor = _statusColor(context, connection.state);
    final countryCode = connection.publicCountry?.trim().toUpperCase();
    final publicIp = connection.publicIp;
    final publicIpValue = publicIp == null
        ? (connection.isConnected ? context.s('checking') : '—')
        : countryCode != null && countryCode.length == 2
        ? '($countryCode) $publicIp'
        : publicIp;
    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  connection.isConnected
                      ? Icons.shield_rounded
                      : Icons.shield_outlined,
                  color: statusColor,
                  size: 21,
                ),
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
              _ConnectionAction(
                connection: connection,
                enabled: selected != null,
                controller: controller,
              ),
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
          Text(
            context.s('selectedServer').toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(letterSpacing: .75),
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
                selected.country.isEmpty
                    ? Icon(
                        Icons.cloud_queue_rounded,
                        size: 26,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Text(
                        countryFlag(selected.country),
                        style: const TextStyle(fontSize: 27),
                      ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
  const _ConnectionAction({
    required this.connection,
    required this.enabled,
    required this.controller,
  });

  final ConnectionInfo connection;
  final bool enabled;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (connection.isConnected) {
      return FilledButton.tonalIcon(
        onPressed: connection.isBusy
            ? null
            : () => _perform(context, controller.disconnect),
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: Text(context.s('disconnect')),
      );
    }
    return FilledButton.icon(
      onPressed: connection.canConnect && enabled
          ? () => _perform(context, controller.connect)
          : null,
      icon: connection.isBusy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.play_arrow_rounded, size: 19),
      label: Text(context.s(connection.isBusy ? connection.state : 'connect')),
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
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool fitValue;

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
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
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
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                    ),
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

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
        SnackBar(content: Text('${context.s('operationFailed')}: $error')),
      );
    }
  }
}
