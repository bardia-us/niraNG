import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/update_dialog.dart';
import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/update_checker.dart';
import '../vpn/app_controller.dart';
import 'per_app_proxy_screen.dart';
import '../logs/logs_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final GlobalKey _backdropKey = GlobalKey();
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
          appVersion: app?.appVersion ?? '1.1.1',
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
    return RepaintBoundary(
      key: _backdropKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SettingsExpansion(
            title: context.s('connection'),
            icon: Icons.vpn_lock_outlined,
            initiallyExpanded: true,
            children: [
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(context.s('connectionMode')),
                subtitle: Text(context.s(settings.connectionMode)),
                onTap: () => _chooseValue(
                  context,
                  title: context.s('connectionMode'),
                  current: settings.connectionMode,
                  values: {
                    'vpn': context.s('vpn'),
                    'proxy': context.s('proxy'),
                  },
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
                        () =>
                            controller.updateSettings({'enableFakeDns': value}),
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
                enabled:
                    !settings.enableLocalDns &&
                    settings.connectionMode == 'vpn',
                leading: const Icon(Icons.router_outlined),
                title: Text(context.s('vpnDns')),
                subtitle: Text(settings.vpnDns),
                onTap:
                    settings.enableLocalDns || settings.connectionMode != 'vpn'
                    ? null
                    : () => _editSingleValue(
                        context,
                        title: context.s('vpnDns'),
                        initial: settings.vpnDns,
                        validator: (value) =>
                            _validateIpAddress(context, value),
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
                        validator: (value) =>
                            _validateVpnAddress(context, value),
                        onSave: (value) => controller.updateSettings({
                          'vpnInterfaceAddress': value,
                        }),
                      ),
              ),
              ListTile(
                enabled: settings.connectionMode == 'vpn',
                leading: const Icon(Icons.straighten_rounded),
                title: Text(context.s('vpnMtu')),
                subtitle: Text(
                  '${settings.vpnMtu} · ${context.s('vpnMtuSummary')}',
                ),
                onTap: settings.connectionMode == 'vpn'
                    ? () => _editMtu(context, controller, settings.vpnMtu)
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.electrical_services_outlined),
                title: Text(context.s('localSocksPort')),
                subtitle: Text('${settings.localSocksPort}'),
                onTap: () =>
                    _editPort(context, controller, settings.localSocksPort),
              ),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: Text(context.s('perAppProxy')),
                subtitle: Text(
                  settings.perAppMode == 'all'
                      ? context.s('allApps')
                      : '${settings.perAppPackages.length} ${context.s('appsCount')} · ${context.s(settings.perAppMode == 'selected' ? 'selectedOnly' : 'excluded')}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PerAppProxyScreen(settings: settings),
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.http_rounded),
                title: Text(context.s('addHttpProxyToVpn')),
                subtitle: Text(context.s('addHttpProxyToVpnSummary')),
                value: settings.addHttpProxyToVpn,
                onChanged:
                    settings.connectionMode == 'vpn' &&
                        settings.httpProxyToVpnSupported
                    ? (value) => _perform(
                        context,
                        () => controller.updateSettings({
                          'addHttpProxyToVpn': value,
                        }),
                      )
                    : null,
              ),
            ],
          ),
          _SettingsExpansion(
            title: context.s('coreSettings'),
            icon: Icons.memory_rounded,
            children: [
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
              SwitchListTile(
                secondary: const Icon(Icons.block_rounded),
                title: Text(context.s('blockQuic')),
                subtitle: Text(context.s('blockQuicSummary')),
                value: settings.blockQuic,
                onChanged: (value) => _perform(
                  context,
                  () => controller.updateSettings({'blockQuic': value}),
                ),
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
              ListTile(
                leading: const Icon(Icons.call_split_rounded),
                title: Text(context.s('fragment')),
                subtitle: Text(
                  settings.fragmentEnabled
                      ? '${settings.fragmentPackets} · ${settings.fragmentLength} · ${settings.fragmentInterval} ms · ${settings.fragmentMaxSplit}'
                      : context.s('disabled'),
                ),
                trailing: Icon(
                  settings.fragmentEnabled
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  color: settings.fragmentEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onTap: () => _editFragment(context, controller, settings),
              ),
            ],
          ),
          _SettingsExpansion(
            title: context.s('mux'),
            icon: Icons.call_merge_rounded,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.call_merge_rounded),
                title: Text(context.s('enableMux')),
                subtitle: Text(context.s('muxSummary')),
                value: settings.muxEnabled,
                onChanged: (value) => _perform(
                  context,
                  () => controller.updateSettings({'muxEnabled': value}),
                ),
              ),
              ListTile(
                enabled: settings.muxEnabled,
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(context.s('muxTcpConcurrency')),
                subtitle: Text(
                  '${settings.muxConcurrency} · ${context.s('muxTcpConcurrencyHint')}',
                ),
                onTap: settings.muxEnabled
                    ? () => _editSingleValue(
                        context,
                        title: context.s('muxTcpConcurrency'),
                        initial: '${settings.muxConcurrency}',
                        validator: (value) => _validateIntegerRange(
                          context,
                          value,
                          minimum: 1,
                          maximum: 128,
                        ),
                        onSave: (value) => controller.updateSettings({
                          'muxConcurrency': int.parse(value),
                        }),
                      )
                    : null,
              ),
              ListTile(
                enabled: settings.muxEnabled,
                leading: const Icon(Icons.hub_outlined),
                title: Text(context.s('muxXudpConcurrency')),
                subtitle: Text(
                  '${settings.muxXudpConcurrency} · ${context.s('muxXudpConcurrencyHint')}',
                ),
                onTap: settings.muxEnabled
                    ? () => _editSingleValue(
                        context,
                        title: context.s('muxXudpConcurrency'),
                        initial: '${settings.muxXudpConcurrency}',
                        validator: (value) => _validateIntegerRange(
                          context,
                          value,
                          minimum: 1,
                          maximum: 1024,
                        ),
                        onSave: (value) => controller.updateSettings({
                          'muxXudpConcurrency': int.parse(value),
                        }),
                      )
                    : null,
              ),
              ListTile(
                enabled: settings.muxEnabled,
                leading: const Icon(Icons.speed_outlined),
                title: Text(context.s('muxQuicHandling')),
                subtitle: Text(context.s('muxQuic${settings.muxQuicHandling}')),
                onTap: settings.muxEnabled
                    ? () => _chooseValue(
                        context,
                        title: context.s('muxQuicHandling'),
                        current: settings.muxQuicHandling,
                        values: {
                          'reject': context.s('muxQuicReject'),
                          'allow': context.s('muxQuicAllow'),
                          'skip': context.s('muxQuicSkip'),
                        },
                        onSelected: (value) => controller.updateSettings({
                          'muxQuicHandling': value,
                        }),
                      )
                    : null,
              ),
            ],
          ),
          _SettingsExpansion(
            title: context.s('routing'),
            icon: Icons.route_outlined,
            children: [
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
            ],
          ),
          _SettingsExpansion(
            title: context.s('dns'),
            icon: Icons.dns_outlined,
            children: [
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: Text(context.s('remoteDns')),
                subtitle: Text(settings.remoteDns),
                onTap: () => _editSingleValue(
                  context,
                  title: context.s('remoteDns'),
                  initial: settings.remoteDns,
                  validator: (value) => _validateDnsResolvers(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'remoteDns': value}),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.alt_route_rounded),
                title: Text(context.s('directDns')),
                subtitle: Text(
                  settings.directDns.isEmpty
                      ? context.s('directDnsSummary')
                      : settings.directDns,
                ),
                value: settings.directDnsEnabled,
                onChanged: (value) => _perform(
                  context,
                  () => controller.updateSettings({'directDnsEnabled': value}),
                ),
              ),
              if (settings.directDnsEnabled)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: Text(context.s('directDnsResolver')),
                  subtitle: Text(
                    settings.directDns.isEmpty
                        ? 'Not configured'
                        : settings.directDns,
                  ),
                  onTap: () => _editSingleValue(
                    context,
                    title: context.s('directDnsResolver'),
                    initial: settings.directDns,
                    validator: (value) => _validateDnsResolvers(context, value),
                    onSave: (value) =>
                        controller.updateSettings({'directDns': value}),
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
            ],
          ),
          _SettingsExpansion(
            title: context.s('general'),
            icon: Icons.settings_outlined,
            children: [
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
                            SnackBar(
                              content: Text(context.s('serversRestored')),
                            ),
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
                subtitle: Text(
                  context.s('hours${settings.updateIntervalHours}'),
                ),
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
            ],
          ),
          _SettingsExpansion(
            title: context.s('performance'),
            icon: Icons.bolt_outlined,
            children: [
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
                  values: {
                    'en': context.s('english'),
                    'fa': context.s('persian'),
                  },
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
              SwitchListTile(
                secondary: const Icon(Icons.power_settings_new_rounded),
                title: Text(context.s('autoConnect')),
                subtitle: Text(context.s('autoConnectSummary')),
                value: settings.autoConnect,
                onChanged: (value) => _perform(
                  context,
                  () => controller.updateSettings({'autoConnect': value}),
                ),
              ),
            ],
          ),
          _SettingsExpansion(
            title: context.s('observatory'),
            icon: Icons.monitor_heart_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.monitor_heart_outlined),
                title: Text(context.s('enableObservatory')),
                subtitle: Text(
                  'leastPing ${settings.leastPingInterval} · leastLoad ${settings.leastLoadInterval}',
                ),
                value: settings.observatoryEnabled,
                onChanged: (value) => _perform(
                  context,
                  () =>
                      controller.updateSettings({'observatoryEnabled': value}),
                ),
              ),
              if (settings.observatoryEnabled) ...[
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: Text(context.s('leastPingInterval')),
                  subtitle: Text(settings.leastPingInterval),
                  onTap: () => _chooseValue(
                    context,
                    title: context.s('leastPingInterval'),
                    current: settings.leastPingInterval,
                    values: const {
                      '1m': '1m',
                      '3m': '3m',
                      '5m': '5m',
                      '10m': '10m',
                    },
                    onSelected: (value) =>
                        controller.updateSettings({'leastPingInterval': value}),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.query_stats_rounded),
                  title: Text(context.s('leastLoadInterval')),
                  subtitle: Text(settings.leastLoadInterval),
                  onTap: () => _chooseValue(
                    context,
                    title: context.s('leastLoadInterval'),
                    current: settings.leastLoadInterval,
                    values: const {
                      '1m': '1m',
                      '5m': '5m',
                      '10m': '10m',
                      '30m': '30m',
                    },
                    onSelected: (value) =>
                        controller.updateSettings({'leastLoadInterval': value}),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.http_rounded),
                  title: Text(context.s('leastLoadProbe')),
                  subtitle: Text(
                    '${settings.leastLoadHttpMethod} · sampling ${settings.leastLoadSampling} · timeout ${settings.leastLoadTimeout}',
                  ),
                  onTap: () => _chooseValue(
                    context,
                    title: 'HTTP method',
                    current: settings.leastLoadHttpMethod,
                    values: const {'HEAD': 'HEAD', 'GET': 'GET'},
                    onSelected: (value) => controller.updateSettings({
                      'leastLoadHttpMethod': value,
                    }),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.functions_rounded),
                  title: Text(context.s('sampling')),
                  subtitle: Text('${settings.leastLoadSampling}'),
                  onTap: () => _chooseValue(
                    context,
                    title: context.s('sampling'),
                    current: '${settings.leastLoadSampling}',
                    values: const {'1': '1', '2': '2', '3': '3', '5': '5'},
                    onSelected: (value) => controller.updateSettings({
                      'leastLoadSampling': int.parse(value),
                    }),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(context.s('timeout')),
                  subtitle: Text(settings.leastLoadTimeout),
                  onTap: () => _chooseValue(
                    context,
                    title: 'leastLoad timeout',
                    current: settings.leastLoadTimeout,
                    values: const {'10s': '10s', '30s': '30s', '60s': '60s'},
                    onSelected: (value) =>
                        controller.updateSettings({'leastLoadTimeout': value}),
                  ),
                ),
              ],
            ],
          ),
          _SettingsExpansion(
            title: context.s('updates'),
            icon: Icons.system_update_alt_rounded,
            children: [
              const UpdateDownloadSettingsTile(),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(context.s('quickSettingsTile')),
                subtitle: Text(context.s('quickSettingsTileSummary')),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => _addQuickSettingsTile(context, controller),
              ),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: Text(context.s('checkForUpdates')),
                subtitle: Text(
                  '${context.s('currentVersion')}: ${app.appVersion}',
                ),
                trailing: _checkingUpdates
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right_rounded),
                onTap: _checkingUpdates
                    ? null
                    : () => _checkForUpdates(context, app.appVersion),
              ),
            ],
          ),
          _SettingsExpansion(
            title: context.s('advanced'),
            icon: Icons.tune_rounded,
            children: [
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
                  onSave: (value) =>
                      controller.updateSettings({'ipCheckUrl': value}),
                ),
              ),
              FutureBuilder<bool>(
                future: NirangNative.batteryOptimizationStatus(),
                builder: (context, snapshot) => ListTile(
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: Text(context.s('batteryOptimization')),
                  subtitle: Text(
                    context.s(
                      snapshot.data == true
                          ? 'batteryOptimizationUnrestricted'
                          : 'batteryOptimizationSummary',
                    ),
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                  onTap: () => _perform(
                    context,
                    NirangNative.openBatteryOptimizationSettings,
                  ),
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
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(context.s('internalLogs')),
                subtitle: Text(context.s('internalLogsSummary')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  controller.refreshLogs();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LogsScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(context.s('about')),
                subtitle: Text('niraNG ${app.appVersion}'),
                onTap: () =>
                    _showAbout(context, app.coreVersion, app.appVersion),
              ),
              ListTile(
                leading: Icon(
                  Icons.restart_alt_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  context.s('resetSettings'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                subtitle: Text(context.s('resetSettingsSummary')),
                onTap: () => _resetSettings(context, controller),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  context.s('applyNextConnection'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
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

  Future<void> _resetSettings(
    BuildContext context,
    AppController controller,
  ) async {
    final confirmed = await _showSettingsDialog<bool>(
      context,
      builder: (dialogContext) => NirangAlertDialog(
        title: Text(context.s('resetSettingsConfirm')),
        content: Text(context.s('resetSettingsConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.s('reset')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _perform(context, controller.resetSettings);
    }
  }

  Future<void> _checkForUpdates(
    BuildContext context,
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
      await showUpdateOptionsDialog(context, release);
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

  Future<void> _addQuickSettingsTile(
    BuildContext context,
    AppController controller,
  ) async {
    try {
      final result = await controller.requestQuickSettingsTile();
      if (!context.mounted) return;
      final message = result == 'already_added'
          ? context.s('quickSettingsTileAlreadyAdded')
          : result == 'requested'
          ? context.s('quickSettingsTileRequested')
          : context.s('quickSettingsTileManual');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('operationFailed'))));
      }
    }
  }

  Future<void> _editCustomRules(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    final result = await _showSettingsDialog<({String domains, String ips})>(
      context,
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

  Future<void> _editFragment(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    final result = await _showSettingsDialog<Map<String, Object?>>(
      context,
      builder: (_) => _FragmentDialog(settings: settings),
    );
    if (result != null && context.mounted) {
      await _perform(context, () => controller.updateSettings(result));
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
    return _showSettingsDialog<String>(
      context,
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
    return _showSettingsDialog<String>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => NirangAlertDialog(
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

  Future<T?> _showSettingsDialog<T>(
    BuildContext context, {
    required Widget Function(BuildContext dialogContext) builder,
  }) => showDialog<T>(context: context, builder: builder);

  Future<void> _showAbout(
    BuildContext context,
    String coreVersion,
    String appVersion,
  ) async {
    await _showSettingsDialog<void>(
      context,
      builder: (dialogContext) => NirangAlertDialog(
        icon: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/branding/nirang-logo-concept.png',
            width: 54,
            height: 54,
            cacheWidth: 108,
            cacheHeight: 108,
          ),
        ),
        title: const Text('niraNG'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appVersion),
            const SizedBox(height: 8),
            Text('${context.s('coreVersion')}: $coreVersion'),
            Text('${context.s('packageName')}: dev.nirang.client'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }
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
  Widget build(BuildContext context) => NirangAlertDialog(
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

class _FragmentDialog extends StatefulWidget {
  const _FragmentDialog({required this.settings});

  final NativeSettings settings;

  @override
  State<_FragmentDialog> createState() => _FragmentDialogState();
}

class _FragmentDialogState extends State<_FragmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late bool _enabled;
  late String _packets;
  late final TextEditingController _length;
  late final TextEditingController _interval;
  late final TextEditingController _maxSplit;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.fragmentEnabled;
    _packets = widget.settings.fragmentPackets;
    _length = TextEditingController(text: widget.settings.fragmentLength);
    _interval = TextEditingController(text: widget.settings.fragmentInterval);
    _maxSplit = TextEditingController(
      text: '${widget.settings.fragmentMaxSplit}',
    );
  }

  @override
  void dispose() {
    _length.dispose();
    _interval.dispose();
    _maxSplit.dispose();
    super.dispose();
  }

  String? _range(String? raw, int maximum) {
    final parts = raw?.trim().split('-') ?? const <String>[];
    if (parts.length != 2) return context.s('invalidFragmentRange');
    final from = int.tryParse(parts.first.trim());
    final to = int.tryParse(parts.last.trim());
    return from != null &&
            to != null &&
            from >= 1 &&
            from <= to &&
            to <= maximum
        ? null
        : context.s('invalidFragmentRange');
  }

  @override
  Widget build(BuildContext context) => NirangAlertDialog(
    title: Text(context.s('fragmentSettings')),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.s('enableFragment')),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          _FragmentFieldLabel(context.s('fragmentPackets')),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _packets,
            decoration: const InputDecoration(),
            items: const ['tlshello', '1-1', '1-2', '1-3', '1-4', '1-5']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(growable: false),
            onChanged: (value) => _packets = value ?? _packets,
          ),
          const SizedBox(height: 14),
          _FragmentFieldLabel(context.s('fragmentLength')),
          const SizedBox(height: 6),
          TextFormField(
            controller: _length,
            decoration: const InputDecoration(hintText: '50-100'),
            validator: (value) => _range(value, 65535),
          ),
          const SizedBox(height: 14),
          _FragmentFieldLabel(context.s('fragmentInterval')),
          const SizedBox(height: 6),
          TextFormField(
            controller: _interval,
            decoration: const InputDecoration(hintText: '10-20'),
            validator: (value) => _range(value, 10000),
          ),
          const SizedBox(height: 14),
          _FragmentFieldLabel(context.s('fragmentMaxSplit')),
          const SizedBox(height: 6),
          TextFormField(
            controller: _maxSplit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number != null && number >= 0 && number <= 10000
                  ? null
                  : context.s('invalidFragmentMaxSplit');
            },
          ),
        ],
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
          Navigator.pop(context, <String, Object?>{
            'fragmentEnabled': _enabled,
            'fragmentPackets': _packets,
            'fragmentLength': _length.text.trim(),
            'fragmentInterval': _interval.text.trim(),
            'fragmentMaxSplit': int.parse(_maxSplit.text.trim()),
          });
        },
        child: Text(context.s('apply')),
      ),
    ],
  );
}

class _FragmentFieldLabel extends StatelessWidget {
  const _FragmentFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    ),
  );
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
  Widget build(BuildContext context) => NirangAlertDialog(
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

class _SettingsExpansion extends StatelessWidget {
  const _SettingsExpansion({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: initiallyExpanded,
    maintainState: true,
    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
    childrenPadding: const EdgeInsets.only(bottom: 4),
    leading: Icon(icon),
    title: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    children: children,
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

String? _validateIntegerRange(
  BuildContext context,
  String value, {
  required int minimum,
  required int maximum,
}) {
  final parsed = int.tryParse(value.trim());
  return parsed != null && parsed >= minimum && parsed <= maximum
      ? null
      : '${context.s('enterValueBetween')} $minimum–$maximum.';
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
