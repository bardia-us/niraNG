import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/country_flag_badge.dart';

class ServerInformationScreen extends StatelessWidget {
  const ServerInformationScreen({required this.server, super.key});

  final ServerInfo server;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.s('serverInformation'))),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CountryFlagBadge(
                  countryCode: server.country,
                  width: 36,
                  height: 27,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${server.protocol} · ${server.transport} · ${server.security}',
                      ),
                    ],
                  ),
                ),
                if (server.selected) Chip(label: Text(context.s('selected'))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _InfoSection(
          title: context.s('generalInformation'),
          children: [
            _InfoRow(label: context.s('name'), value: server.name),
            _InfoRow(label: context.s('protocol'), value: server.protocol),
            _InfoRow(label: context.s('transport'), value: server.transport),
            _InfoRow(label: context.s('security'), value: server.security),
            _InfoRow(
              label: context.s('country'),
              value: server.country.isEmpty
                  ? context.s('unknown')
                  : server.country,
            ),
            _InfoRow(
              label: context.s('port'),
              value: server.port > 0 ? '${server.port}' : '—',
            ),
            if (server.sni.isNotEmpty)
              _InfoRow(label: 'SNI', value: server.sni, ltr: true),
            _InfoRow(
              label: context.s('ping'),
              value: server.ping == null
                  ? context.s('neverTested')
                  : '${server.ping} ms',
            ),
            _InfoRow(
              label: context.s('status'),
              value: context.s(server.status),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoSection(
          title: context.s('protectedCredentials'),
          subtitle: context.s('credentialsProtected'),
          children: [
            if (server.credentialMasked.isNotEmpty)
              _InfoRow(
                label: server.credentialLabel == 'Password'
                    ? context.s('password')
                    : 'UUID',
                value: server.credentialMasked,
                ltr: true,
              ),
            if (server.realityPublicKeyMasked.isNotEmpty)
              _InfoRow(
                label: context.s('realityPublicKey'),
                value: server.realityPublicKeyMasked,
                ltr: true,
              ),
            if (server.shortIdMasked.isNotEmpty)
              _InfoRow(
                label: context.s('shortId'),
                value: server.shortIdMasked,
                ltr: true,
              ),
          ],
        ),
      ],
    ),
  );
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Directionality(
            textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );
}
