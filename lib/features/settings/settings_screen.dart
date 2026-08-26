import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/update_checker.dart';
import '../vpn/app_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingUpdates = false;

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          settings: app?.settings ?? const NativeSettings(),
          lastUpdated: app?.lastUpdated ?? 0,
          isRefreshing: app?.isRefreshing ?? false,
          deletedCount: app?.deletedServerCount ?? 0,
          coreVersion: app?.coreVersion ?? 'Bundled',
          appVersion: app?.appVersion ?? '1.0.5',
        );
      }),
    );
    final app = AppSnapshot(
      settings: view.settings,
      lastUpdated: view.lastUpdated,
      isRefreshing: view.isRefreshing,
      deletedServerCount: view.deletedCount,
      coreVersion: view.coreVersion,
      appVersion: view.appVersion,
    );
    final settings = app.settings;
    final controller = ref.read(appControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(context.s('vpnSettings')),
        ListTile(
          leading: const Icon(Icons.vpn_key_outlined),
          title: Text(context.s('connectionMode')),
          subtitle: Text(context.s(settings.connectionMode)),
          onTap: () => _chooseValue(
            context,
            title: context.s('connectionMode'),
            current: settings.connectionMode,
            values: {'vpn': context.s('vpn'), 'proxy': context.s('proxy')},
            onSelected: (value) =>
                controller.updateSettings({'connectionMode': value}),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dns_outlined),
          title: Text(context.s('enableLocalDns')),
          subtitle: Text(context.s('enableLocalDnsSummary')),
          value: settings.enableLocalDns,
          onChanged: (value) => _perform(
            context,
            () => controller.updateSettings({'enableLocalDns': value}),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.auto_awesome_outlined),
          title: Text(context.s('enableFakeDns')),
          subtitle: Text(context.s('enableFakeDnsSummary')),
          value: settings.enableFakeDns,
          onChanged: settings.enableLocalDns
              ? (value) => _perform(
                  context,
                  () => controller.updateSettings({'enableFakeDns': value}),
                )
              : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lan_outlined),
          title: Text(context.s('enableIpv6')),
          subtitle: Text(context.s('enableIpv6Summary')),
          value: settings.enableIpv6,
          onChanged: (value) => _perform(
            context,
            () => controller.updateSettings({'enableIpv6': value}),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.swap_vert_circle_outlined),
          title: Text(context.s('preferIpv6')),
          subtitle: Text(context.s('preferIpv6Summary')),
          value: settings.preferIpv6,
          onChanged: settings.enableIpv6
              ? (value) => _perform(
                  context,
                  () => controller.updateSettings({'preferIpv6': value}),
                )
              : null,
        ),
        ListTile(
          enabled: !settings.enableLocalDns && settings.connectionMode == 'vpn',
          leading: const Icon(Icons.router_outlined),
          title: Text(context.s('vpnDns')),
          subtitle: Text(settings.vpnDns),
          onTap: settings.enableLocalDns || settings.connectionMode != 'vpn'
              ? null
              : () => _editSingleValue(
                  context,
                  title: context.s('vpnDns'),
                  initial: settings.vpnDns,
                  validator: (value) => _validateIpAddress(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'vpnDns': value}),
                ),
        ),
        ListTile(
          enabled: settings.connectionMode == 'vpn',
          leading: const Icon(Icons.settings_ethernet_rounded),
          title: Text(context.s('vpnInterfaceAddress')),
          subtitle: Text(settings.vpnInterfaceAddress),
          onTap: settings.connectionMode != 'vpn'
              ? null
              : () => _editSingleValue(
                  context,
                  title: context.s('vpnInterfaceAddress'),
                  initial: settings.vpnInterfaceAddress,
                  validator: (value) => _validateVpnAddress(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'vpnInterfaceAddress': value}),
                ),
        ),
        ListTile(
          enabled: settings.connectionMode == 'vpn',
          leading: const Icon(Icons.straighten_rounded),
          title: Text(context.s('vpnMtu')),
          subtitle: Text('${settings.vpnMtu} · ${context.s('vpnMtuSummary')}'),
          onTap: settings.connectionMode == 'vpn'
              ? () => _editMtu(context, controller, settings.vpnMtu)
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.electrical_services_outlined),
          title: Text(context.s('localSocksPort')),
          subtitle: Text('${settings.localSocksPort}'),
          onTap: () => _editPort(context, controller, settings.localSocksPort),
        ),
        const Divider(indent: 56),
        _Header(context.s('coreSettings')),
        SwitchListTile(
          secondary: const Icon(Icons.manage_search_rounded),
          title: Text(context.s('enableSniffing')),
          subtitle: Text(context.s('sniffingSummary')),
          value: settings.sniffingEnabled,
          onChanged: (value) => _perform(
            context,
            () => controller.updateSettings({'sniffingEnabled': value}),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.alt_route_rounded),
          title: Text(context.s('enableRouteOnly')),
          subtitle: Text(context.s('routeOnlySummary')),
          value: settings.routeOnly,
          onChanged: settings.sniffingEnabled
              ? (value) => _perform(
                  context,
                  () => controller.updateSettings({'routeOnly': value}),
                )
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: Text(context.s('realPingConcurrency')),
          subtitle: Text('${settings.realPingConcurrency}'),
          onTap: () => _chooseValue(
            context,
            title: context.s('realPingConcurrency'),
            current: '${settings.realPingConcurrency}',
            values: const {'4': '4', '8': '8', '16': '16', '32': '32'},
            onSelected: (value) => controller.updateSettings({
              'realPingConcurrency': int.parse(value),
            }),
          ),
        ),
        const Divider(indent: 56),
        _Header(context.s('routing')),
        ListTile(
          leading: const Icon(Icons.route_outlined),
          title: Text(context.s('routing')),
          subtitle: Text(_routingLabel(context, settings.routingMode)),
          onTap: () => _chooseRouting(context, controller, settings),
        ),
        if (settings.routingMode == 'custom')
          ListTile(
            leading: const Icon(Icons.rule_rounded),
            title: Text(context.s('custom')),
            subtitle: Text(context.s('customRuleHint')),
            onTap: () => _editCustomRules(context, controller, settings),
          ),
        const Divider(indent: 56),
        _Header(context.s('dns')),
        ListTile(
          leading: const Icon(Icons.public_outlined),
          title: Text(context.s('remoteDns')),
          subtitle: Text(settings.remoteDns),
          onTap: () => _editSingleValue(
            context,
            title: context.s('remoteDns'),
            initial: settings.remoteDns,
            validator: (value) => _validateDnsResolvers(context, value),
            onSave: (value) => controller.updateSettings({'remoteDns': value}),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(context.s('domainStrategy')),
          subtitle: Text(settings.domainStrategy),
          onTap: () => _chooseValue(
            context,
            title: context.s('domainStrategy'),
            current: settings.domainStrategy,
            values: const {
              'AsIs': 'AsIs',
              'IPIfNonMatch': 'IPIfNonMatch',
              'IPOnDemand': 'IPOnDemand',
            },
            onSelected: (value) =>
                controller.updateSettings({'domainStrategy': value}),
          ),
        ),
        const Divider(indent: 56),
        _Header(context.s('subscriptionUpdate')),
        ListTile(
          leading: const Icon(Icons.sync_rounded),
          title: Text(context.s('refresh')),
          subtitle: Text(
            '${context.s('lastUpdated')}: ${formatDateTime(app.lastUpdated)}',
          ),
          trailing: app.isRefreshing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: app.isRefreshing
              ? null
              : () => _perform(context, controller.refreshSubscription),
        ),
        ListTile(
          enabled: app.deletedServerCount > 0,
          leading: const Icon(Icons.restore_from_trash_outlined),
          title: Text(context.s('restoreDeletedServers')),
          subtitle: Text(
            app.deletedServerCount == 0
                ? context.s('noDeletedServers')
                : '${app.deletedServerCount} ${context.s('deletedServersCount')}',
          ),
          onTap: app.deletedServerCount == 0
              ? null
              : () => _perform(context, () async {
                  await controller.restoreDeletedServers();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.s('serversRestored'))),
                    );
                  }
                }),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.update_rounded),
          title: Text(context.s('autoUpdate')),
          value: settings.autoUpdate,
          onChanged: (value) => _perform(
            context,
            () => controller.updateSettings({'autoUpdate': value}),
          ),
        ),
        ListTile(
          enabled: settings.autoUpdate,
          leading: const Icon(Icons.schedule_rounded),
          title: Text(context.s('updateInterval')),
          subtitle: Text(context.s('hours${settings.updateIntervalHours}')),
          onTap: !settings.autoUpdate
              ? null
              : () => _chooseValue(
                  context,
                  title: context.s('updateInterval'),
                  current: '${settings.updateIntervalHours}',
                  values: {
                    '6': context.s('hours6'),
                    '12': context.s('hours12'),
                    '24': context.s('hours24'),
                  },
                  onSelected: (value) => controller.updateSettings({
                    'updateIntervalHours': int.parse(value),
                  }),
                ),
        ),
        const Divider(indent: 56),
        _Header(context.s('appearance')),
        ListTile(
          leading: const Icon(Icons.contrast_rounded),
          title: Text(context.s('theme')),
          subtitle: Text(context.s(settings.themeMode)),
          onTap: () => _chooseValue(
            context,
            title: context.s('theme'),
            current: settings.themeMode,
            values: {
              'system': context.s('system'),
              'light': context.s('light'),
              'dark': context.s('dark'),
            },
            onSelected: (value) =>
                controller.updateSettings({'themeMode': value}),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language_rounded),
          title: Text(context.s('language')),
          subtitle: Text(
            settings.language == 'fa'
                ? context.s('persian')
                : context.s('english'),
          ),
          onTap: () => _chooseValue(
            context,
            title: context.s('language'),
            current: settings.language,
            values: {'en': context.s('english'), 'fa': context.s('persian')},
            onSelected: (value) =>
                controller.updateSettings({'language': value}),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bolt_rounded),
          title: Text(context.s('performanceMode')),
          subtitle: Text(context.s('performanceModeSummary')),
          value: settings.performanceMode,
          onChanged: (value) => _perform(
            context,
            () => controller.updateSettings({
              'performanceMode': value,
              'performanceModePrompted': true,
            }),
          ),
        ),
        const Divider(indent: 56),
        _Header(context.s('updates')),
        ListTile(
          leading: const Icon(Icons.system_update_alt_rounded),
          title: Text(context.s('checkForUpdates')),
          subtitle: Text('${context.s('currentVersion')}: ${app.appVersion}'),
          trailing: _checkingUpdates
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right_rounded),
          onTap: _checkingUpdates
              ? null
              : () => _checkForUpdates(context, controller, app.appVersion),
        ),
        const Divider(indent: 56),
        _Header(context.s('settings')),
        ListTile(
          leading: const Icon(Icons.public_rounded),
          title: Text(context.s('ipProvider')),
          subtitle: Text(
            settings.ipCheckUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _editSingleValue(
            context,
            title: context.s('ipProvider'),
            initial: settings.ipCheckUrl,
            validator: (value) => _validateHttps(context, value),
            onSave: (value) => controller.updateSettings({'ipCheckUrl': value}),
          ),
        ),
        ListTile(
          enabled: settings.telegramUrlConfigured,
          leading: const Icon(Icons.send_outlined),
          title: Text(context.s('telegram')),
          subtitle: Text(
            settings.telegramContact.isEmpty
                ? context.s('telegramSubtitle')
                : '${settings.telegramContact} · ${context.s('telegramSubtitle')}',
          ),
          trailing: const Icon(Icons.open_in_new_rounded, size: 19),
          onTap: () => _perform(context, controller.openTelegram),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: Text(context.s('about')),
          subtitle: Text('niraNG ${app.appVersion}'),
          onTap: () => _showAbout(context, app.coreVersion, app.appVersion),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            context.s('applyNextConnection'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _chooseRouting(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    await _chooseValue(
      context,
      title: context.s('routing'),
      current: settings.routingMode,
      values: {
        'global': context.s('global'),
        'bypassIran': context.s('bypassIran'),
        'custom': context.s('custom'),
      },
      descriptions: {
        'global': context.s('globalRoutingHint'),
        'bypassIran': context.s('bypassIranHint'),
        'custom': context.s('customRuleHint'),
      },
      onSelected: (value) => controller.updateSettings({'routingMode': value}),
    );
  }

  Future<void> _checkForUpdates(
    BuildContext context,
    AppController controller,
    String currentVersion,
  ) async {
    setState(() => _checkingUpdates = true);
    try {
      final release = await const GitHubUpdateChecker().check(currentVersion);
      if (!context.mounted) return;
      if (!release.updateAvailable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('upToDate'))));
        return;
      }
      final viewRelease = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.new_releases_outlined),
          title: Text(context.s('newVersionAvailable')),
          content: Text('${release.latestVersion}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.s('later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.s('viewRelease')),
            ),
          ],
        ),
      );
      if (viewRelease == true && context.mounted) {
        await _perform(
          context,
          () => controller.openExternalUrl(release.releaseUrl),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('updateCheckFailed'))));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _editCustomRules(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    final result = await showDialog<({String domains, String ips})>(
      context: context,
      builder: (_) => _CustomRulesDialog(
        domains: settings.customDomains,
        ips: settings.customIps,
      ),
    );
    if (context.mounted && result != null) {
      await _perform(
        context,
        () => controller.updateSettings({
          'customDomains': result.domains,
          'customIps': result.ips,
        }),
      );
    }
  }

  Future<void> _editSingleValue(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String value) onSave,
    String? Function(String value)? validator,
  }) async {
    final value = await _promptSingleValue(
      context,
      title: title,
      initial: initial,
      validator: validator,
    );
    if (value != null && context.mounted) {
      await _perform(context, () => onSave(value));
    }
  }

  Future<String?> _promptSingleValue(
    BuildContext context, {
    required String title,
    required String initial,
    TextInputType keyboardType = TextInputType.url,
    String? Function(String value)? validator,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextValueDialog(
        title: title,
        initial: initial,
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Future<void> _editMtu(
    BuildContext context,
    AppController controller,
    int current,
  ) async {
    final value = await _promptSingleValue(
      context,
      title: context.s('vpnMtu'),
      initial: '$current',
      keyboardType: TextInputType.number,
      validator: (value) {
        final mtu = int.tryParse(value);
        return mtu != null && mtu >= 1280 && mtu <= 9000
            ? null
            : context.s('vpnMtuSummary');
      },
    );
    if (!context.mounted || value == null) return;
    final mtu = int.parse(value);
    await _perform(context, () => controller.updateSettings({'vpnMtu': mtu}));
  }

  Future<void> _editPort(
    BuildContext context,
    AppController controller,
    int current,
  ) async {
    final value = await _promptSingleValue(
      context,
      title: context.s('localSocksPort'),
      initial: '$current',
      keyboardType: TextInputType.number,
      validator: (value) {
        final port = int.tryParse(value);
        return port != null && port >= 1024 && port <= 65535 && port != 10809
            ? null
            : context.s('invalidPort');
      },
    );
    if (!context.mounted || value == null) return;
    await _perform(
      context,
      () => controller.updateSettings({'localSocksPort': int.parse(value)}),
    );
  }

  Future<void> _chooseValue(
    BuildContext context, {
    required String title,
    required String current,
    required Map<String, String> values,
    required Future<void> Function(String value) onSelected,
    Map<String, String>? descriptions,
  }) async {
    final selected = await _pickValue(
      context,
      title: title,
      current: current,
      values: values,
      descriptions: descriptions,
    );
    if (selected != null && selected != current && context.mounted) {
      await _perform(context, () => onSelected(selected));
    }
  }

  Future<String?> _pickValue(
    BuildContext context, {
    required String title,
    required String current,
    required Map<String, String> values,
    Map<String, String>? descriptions,
  }) async {
    var temporary = current;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in values.entries)
                ListTile(
                  leading: Icon(
                    entry.key == temporary
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: entry.key == temporary
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(entry.value),
                  subtitle: descriptions?[entry.key] == null
                      ? null
                      : Text(descriptions![entry.key]!),
                  onTap: () => setDialogState(() => temporary = entry.key),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.s('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, temporary),
              child: Text(context.s('apply')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout(
    BuildContext context,
    String coreVersion,
    String appVersion,
  ) => showAboutDialog(
    context: context,
    applicationName: 'niraNG',
    applicationVersion: appVersion,
    applicationIcon: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/branding/nirang-logo-concept.png',
        width: 54,
        height: 54,
        cacheWidth: 108,
        cacheHeight: 108,
      ),
    ),
    children: [
      const SizedBox(height: 8),
      Text('${context.s('coreVersion')}: $coreVersion'),
      Text('${context.s('packageName')}: dev.nirang.client'),
    ],
  );
}

class _TextValueDialog extends StatefulWidget {
  const _TextValueDialog({
    required this.title,
    required this.initial,
    required this.keyboardType,
    this.validator,
  });

  final String title;
  final String initial;
  final TextInputType keyboardType;
  final String? Function(String value)? validator;

  @override
  State<_TextValueDialog> createState() => _TextValueDialogState();
}

class _TextValueDialogState extends State<_TextValueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (value.isEmpty) return context.s('requiredValue');
          return widget.validator?.call(value);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.s('cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() != true) return;
          Navigator.pop(context, _controller.text.trim());
        },
        child: Text(context.s('save')),
      ),
    ],
  );
}

class _CustomRulesDialog extends StatefulWidget {
  const _CustomRulesDialog({required this.domains, required this.ips});

  final String domains;
  final String ips;

  @override
  State<_CustomRulesDialog> createState() => _CustomRulesDialogState();
}

class _CustomRulesDialogState extends State<_CustomRulesDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _domains;
  late final TextEditingController _ips;

  @override
  void initState() {
    super.initState();
    _domains = TextEditingController(text: widget.domains);
    _ips = TextEditingController(text: widget.ips);
  }

  @override
  void dispose() {
    _domains.dispose();
    _ips.dispose();
    super.dispose();
  }

  String? _validateDomains(String? value) {
    final text = value ?? '';
    if (!_validRuleText(text)) return context.s('invalidRules');
    return _splitDomainRules(text).every(_isValidDomainRule)
        ? null
        : context.s('invalidRules');
  }

  String? _validateIps(String? value) {
    final text = value ?? '';
    if (!_validRuleText(text)) return context.s('invalidRules');
    return _splitRules(text).every(_isValidIpRule)
        ? null
        : context.s('invalidRules');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.s('custom')),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _domains,
              maxLines: 4,
              validator: _validateDomains,
              decoration: InputDecoration(
                labelText: context.s('customDomains'),
                hintText: 'domain:example.com, full:api.example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ips,
              maxLines: 4,
              validator: _validateIps,
              decoration: InputDecoration(
                labelText: context.s('customIps'),
                hintText: '1.2.3.4, 10.0.0.0/8, 2001:db8::/32',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.s('cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() != true) return;
          Navigator.pop(context, (
            domains: _domains.text.trim(),
            ips: _ips.text.trim(),
          ));
        },
        child: Text(context.s('save')),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: .8,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

String _routingLabel(BuildContext context, String value) => switch (value) {
  'bypassIran' => context.s('bypassIran'),
  'custom' => context.s('custom'),
  _ => context.s('global'),
};

List<String> _splitRules(String value) => value
    .split(RegExp(r'[,\n]'))
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toList(growable: false);

List<String> _splitDomainRules(String value) => value
    .split('\n')
    .expand((line) {
      final trimmed = line.trim();
      return trimmed.toLowerCase().startsWith('regexp:')
          ? [trimmed]
          : trimmed.split(',');
    })
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toList(growable: false);

bool _validRuleText(String value) =>
    value.length <= 16384 &&
    !value.contains('\u0000') &&
    !value.runes.any(
      (code) => code < 32 && code != 9 && code != 10 && code != 13,
    );

final _hostnameRule = RegExp(
  r'^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
);

bool _isValidDomainRule(String rule) {
  if (rule.length > 512) return false;
  final separator = rule.indexOf(':');
  if (separator < 0) {
    return !rule.contains(RegExp(r'\s')) && _hostnameRule.hasMatch(rule);
  }
  final prefix = rule.substring(0, separator).toLowerCase();
  final body = rule.substring(separator + 1);
  if (prefix == 'regexp') return body.isNotEmpty;
  return !body.contains(RegExp(r'\s')) &&
      (prefix == 'domain' || prefix == 'full') &&
      _hostnameRule.hasMatch(body);
}

bool _isValidIpRule(String rule) {
  final parts = rule.split('/');
  if (parts.length > 2 || !_isIpAddress(parts.first)) return false;
  if (parts.length == 1) return true;
  final prefix = int.tryParse(parts.last);
  final maxPrefix = parts.first.contains(':') ? 128 : 32;
  return prefix != null && prefix >= 0 && prefix <= maxPrefix;
}

bool _isIpAddress(String value) {
  if (value.length > 253 || value.contains(RegExp(r'\s'))) {
    return false;
  }
  final ipv4Parts = value.split('.');
  final isIpv4 =
      ipv4Parts.length == 4 &&
      ipv4Parts.every((part) {
        final number = int.tryParse(part);
        return number != null && number >= 0 && number <= 255;
      });
  final isIpv6 =
      value.contains(':') &&
      RegExp(r'^[0-9a-fA-F:]+$').hasMatch(value) &&
      value.split(':').length >= 3;
  return isIpv4 || isIpv6;
}

String? _validateIpAddress(BuildContext context, String value) =>
    _isIpAddress(value) ? null : context.s('invalidDns');

String? _validateVpnAddress(BuildContext context, String value) {
  final parts = value.split('/');
  if (parts.length != 2 || !_isIpAddress(parts.first)) {
    return context.s('invalidVpnAddress');
  }
  final octets = parts.first.split('.').map(int.tryParse).toList();
  final prefix = int.tryParse(parts.last);
  if (octets.length != 4 || octets.any((value) => value == null)) {
    return context.s('invalidVpnAddress');
  }
  final first = octets[0]!;
  final second = octets[1]!;
  final isPrivate =
      first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
  return isPrivate && prefix != null && prefix >= 16 && prefix <= 30
      ? null
      : context.s('invalidVpnAddress');
}

String? _validateDnsResolvers(BuildContext context, String value) {
  final resolvers = value
      .split(RegExp(r'[,\n]'))
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
  if (resolvers.isEmpty || resolvers.length > 8) return context.s('invalidDns');
  const schemes = {'https', 'https+local', 'quic+local', 'tcp', 'tcp+local'};
  final hostname = RegExp(
    r'^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  );
  for (final resolver in resolvers) {
    if (_isIpAddress(resolver) || hostname.hasMatch(resolver)) continue;
    final uri = Uri.tryParse(resolver);
    if (uri == null || !schemes.contains(uri.scheme) || uri.host.isEmpty) {
      return context.s('invalidDns');
    }
  }
  return null;
}

String? _validateHttps(BuildContext context, String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? null
      : context.s('invalidHttps');
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
