import 'package:flutter/material.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/clay_surface.dart';
import '../../core/widgets/country_flag_badge.dart';

/// Configured topology, not inferred reachability of every intermediate hop.
List<String> connectionPathLabels(ServerInfo server) {
  final hops = <String>[];
  if (server.profileKind == 'json') {
    hops.add('Custom JSON');
  } else if (server.profileKind == 'aether') {
    if (server.psiphonPlacement != 'only') {
      hops.addAll(switch (server.aetherMode) {
        'masque' => ['MASQUE'],
        'wireguard' => ['WireGuard'],
        'wireguard-over-masque' => ['MASQUE', 'WireGuard'],
        'warp-in-warp' => ['WireGuard', 'WireGuard'],
        'masque-in-masque' => ['MASQUE', 'MASQUE'],
        _ => ['Aether'],
      });
    }
    if (server.psiphonPlacement == 'reverse') {
      hops.insert(0, 'Psiphon');
    } else if (const {'chain', 'only'}.contains(server.psiphonPlacement)) {
      hops.add('Psiphon');
    }
  } else {
    hops.add(server.protocol);
  }
  return ['Device', ...hops, 'Exit'];
}

class ConnectionPathCard extends StatefulWidget {
  const ConnectionPathCard({
    required this.server,
    required this.connection,
    this.compact = false,
    super.key,
  });
  final ServerInfo server;
  final ConnectionInfo connection;
  final bool compact;
  @override
  State<ConnectionPathCard> createState() => _ConnectionPathCardState();
}

class _ConnectionPathCardState extends State<ConnectionPathCard> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String en, String ir) => fa ? ir : en;
    final c = widget.connection;
    final matching = c.serverId == widget.server.id;
    final active = matching && c.isConnected;
    final observed =
        active && c.publicIpChecked && (c.publicIp?.isNotEmpty ?? false);
    final stage = matching && c.isBusy ? c.aetherStage : null;
    final status = matching && c.state == 'stopping'
        ? t('Disconnecting', 'در حال قطع اتصال')
        : matching && c.state == 'error'
        ? t('Connection error', 'خطای اتصال')
        : stage == 'registering'
        ? t('Registering identity', 'دریافت کلید اتصال')
        : stage == 'finding_endpoint'
        ? t('Discovering path', 'در حال یافتن مسیر')
        : matching && c.isBusy
        ? t('Preparing connection', 'آماده‌سازی اتصال')
        : active
        ? t('Core running', 'هسته فعال است')
        : t('Configured path', 'مسیر تنظیم‌شده');
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    final scheme = Theme.of(context).colorScheme;
    final labels = connectionPathLabels(widget.server);
    return RepaintBoundary(
      child: ClaySurface(
        radius: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                key: const ValueKey('connection-path-toggle'),
                borderRadius: BorderRadius.circular(24),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.alt_route_rounded,
                            color: scheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              t('Connection path', 'مسیر اتصال'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? .5 : 0,
                            duration: duration,
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      AnimatedSwitcher(
                        duration: duration,
                        child: Align(
                          key: ValueKey(status),
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            status,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: active
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                      if (!widget.compact || _expanded) ...[
                        const SizedBox(height: 12),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < labels.length; i++)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest
                                            .withValues(alpha: .65),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withValues(alpha: .45),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (labels[i] == 'Exit' &&
                                              observed) ...[
                                            CountryFlagBadge(
                                              countryCode:
                                                  c.publicCountry ?? '',
                                              width: 22,
                                              height: 16,
                                            ),
                                            const SizedBox(width: 5),
                                          ],
                                          Text(
                                            switch (labels[i]) {
                                              'Device' => t('Device', 'گوشی'),
                                              'Exit' => t('Exit', 'خروجی'),
                                              'Custom JSON' => t(
                                                'Custom JSON',
                                                'JSON سفارشی',
                                              ),
                                              _ => labels[i],
                                            },
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (i < labels.length - 1)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 16,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(height: 16),
                          Text(
                            t(
                              'Configured stages; individual hops are not separately health-checked.',
                              'این مراحل از تنظیمات اتصال می‌آیند؛ سلامت هر واسطه جداگانه آزمایش نشده.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (widget.server.profileKind == 'json')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                t(
                                  'Routing and outbound chains are defined by the JSON profile.',
                                  'مسیرها و زنجیره‌های خروجی را خود JSON تعیین می‌کند.',
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text('${t('Core', 'هسته')}: ${widget.server.engine}'),
                          if (matching &&
                              (active || c.isBusy) &&
                              c.aetherEndpoint != null)
                            SelectableText(
                              '${t('Endpoint', 'آدرس اتصال')}: ${c.aetherEndpoint}',
                              textDirection: TextDirection.ltr,
                            ),
                          if (matching &&
                              (active || c.isBusy) &&
                              c.aetherInnerEndpoint != null)
                            SelectableText(
                              '${t('Inner endpoint', 'آدرس داخلی')}: ${c.aetherInnerEndpoint}',
                              textDirection: TextDirection.ltr,
                            ),
                          if (observed)
                            SelectableText(
                              '${t('Observed exit', 'خروجی مشاهده‌شده')}: ${c.publicIp}${c.publicCountry == null ? '' : ' · ${c.publicCountry}'}',
                              textDirection: TextDirection.ltr,
                            )
                          else
                            Text(
                              t(
                                'Exit location appears after a successful IP check.',
                                'کشور خروجی بعد از بررسی موفق IP نمایش داده می‌شود.',
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
