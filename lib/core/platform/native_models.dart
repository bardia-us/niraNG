import 'package:flutter/material.dart';

int? _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value');

class ServerInfo {
  const ServerInfo({
    required this.id,
    required this.name,
    required this.country,
    required this.protocol,
    required this.transport,
    required this.security,
    required this.port,
    required this.selected,
    required this.status,
    this.sni = '',
    this.credentialLabel = '',
    this.credentialMasked = '',
    this.realityPublicKeyMasked = '',
    this.shortIdMasked = '',
    this.ping,
  });

  factory ServerInfo.fromMap(Map<dynamic, dynamic> map) => ServerInfo(
    id: '${map['id'] ?? ''}',
    name: '${map['name'] ?? 'Server'}',
    country: '${map['country'] ?? ''}',
    protocol: '${map['protocol'] ?? ''}',
    transport: '${map['transport'] ?? ''}',
    security: '${map['security'] ?? ''}',
    port: _int(map['port']) ?? 0,
    sni: '${map['sni'] ?? ''}',
    credentialLabel: '${map['credentialLabel'] ?? ''}',
    credentialMasked: '${map['credentialMasked'] ?? ''}',
    realityPublicKeyMasked: '${map['realityPublicKeyMasked'] ?? ''}',
    shortIdMasked: '${map['shortIdMasked'] ?? ''}',
    ping: _int(map['ping']),
    selected: map['selected'] == true,
    status: '${map['status'] ?? 'idle'}',
  );

  final String id;
  final String name;
  final String country;
  final String protocol;
  final String transport;
  final String security;
  final int port;
  final String sni;
  final String credentialLabel;
  final String credentialMasked;
  final String realityPublicKeyMasked;
  final String shortIdMasked;
  final int? ping;
  final bool selected;
  final String status;

  ServerInfo copyWith({
    int? ping,
    bool? selected,
    String? status,
    bool clearPing = false,
  }) => ServerInfo(
    id: id,
    name: name,
    country: country,
    protocol: protocol,
    transport: transport,
    security: security,
    port: port,
    sni: sni,
    credentialLabel: credentialLabel,
    credentialMasked: credentialMasked,
    realityPublicKeyMasked: realityPublicKeyMasked,
    shortIdMasked: shortIdMasked,
    ping: clearPing ? null : ping ?? this.ping,
    selected: selected ?? this.selected,
    status: status ?? this.status,
  );
}

class ConnectionInfo {
  const ConnectionInfo({
    this.state = 'disconnected',
    this.serverId,
    this.serverName,
    this.publicIp,
    this.publicCountry,
    this.publicCity,
    this.publicIpChecked = false,
    this.error,
  });

  factory ConnectionInfo.fromMap(Map<dynamic, dynamic> map) => ConnectionInfo(
    state: '${map['state'] ?? 'disconnected'}',
    serverId: map['serverId']?.toString(),
    serverName: map['serverName']?.toString(),
    publicIp: map['publicIp']?.toString(),
    publicCountry: map['publicCountry']?.toString(),
    publicCity: map['publicCity']?.toString(),
    publicIpChecked: map['publicIpChecked'] == true,
    error: map['error']?.toString(),
  );

  final String state;
  final String? serverId;
  final String? serverName;
  final String? publicIp;
  final String? publicCountry;
  final String? publicCity;
  final bool publicIpChecked;
  final String? error;

  bool get isConnected => state == 'connected';
  bool get isBusy => const {
    'preparing',
    'connecting',
    'restarting',
    'switching',
    'reconnecting',
    'stopping',
  }.contains(state);
  bool get canConnect => !isConnected && !isBusy;
}

class SubscriptionUsage {
  const SubscriptionUsage({
    this.upload,
    this.download,
    this.used,
    this.total,
    this.remaining,
    this.expire,
    this.unlimited = false,
    this.expired = false,
  });

  factory SubscriptionUsage.fromMap(Map<dynamic, dynamic> map) =>
      SubscriptionUsage(
        upload: _int(map['upload']),
        download: _int(map['download']),
        used: _int(map['used']),
        total: _int(map['total']),
        remaining: _int(map['remaining']),
        expire: _int(map['expire']),
        unlimited: map['unlimited'] == true,
        expired: map['expired'] == true,
      );

  final int? upload;
  final int? download;
  final int? used;
  final int? total;
  final int? remaining;
  final int? expire;
  final bool unlimited;
  final bool expired;
}

class NativeSettings {
  const NativeSettings({
    this.connectionMode = 'vpn',
    this.routingMode = 'bypassIran',
    this.customDomains = '',
    this.customIps = '',
    this.enableLocalDns = true,
    this.enableFakeDns = false,
    this.remoteDns = 'https://dns.google/dns-query',
    this.vpnDns = '1.1.1.1',
    this.vpnInterfaceAddress = '10.10.14.1/30',
    this.localSocksPort = 10808,
    this.realPingConcurrency = 16,
    this.domainStrategy = 'AsIs',
    this.sniffingEnabled = true,
    this.routeOnly = false,
    this.fragmentEnabled = false,
    this.fragmentPackets = 'tlshello',
    this.fragmentLength = '50-100',
    this.fragmentInterval = '10-20',
    this.fragmentMaxSplit = 10,
    this.enableIpv6 = true,
    this.preferIpv6 = false,
    this.vpnMtu = 1500,
    this.autoUpdate = true,
    this.updateIntervalHours = 12,
    this.themeMode = 'system',
    this.language = 'en',
    this.performanceMode = false,
    this.performanceModePrompted = false,
    this.ipCheckUrl = 'https://api.ip.sb/geoip',
    this.telegramUrlConfigured = true,
    this.telegramContact = '',
  });

  factory NativeSettings.fromMap(Map<dynamic, dynamic> map) => NativeSettings(
    connectionMode: '${map['connectionMode'] ?? 'vpn'}',
    routingMode: '${map['routingMode'] ?? 'bypassIran'}',
    customDomains: '${map['customDomains'] ?? ''}',
    customIps: '${map['customIps'] ?? ''}',
    enableLocalDns: map['enableLocalDns'] != false,
    enableFakeDns: map['enableFakeDns'] == true,
    remoteDns: '${map['remoteDns'] ?? 'https://dns.google/dns-query'}',
    vpnDns: '${map['vpnDns'] ?? '1.1.1.1'}',
    vpnInterfaceAddress: '${map['vpnInterfaceAddress'] ?? '10.10.14.1/30'}',
    localSocksPort: _int(map['localSocksPort']) ?? 10808,
    realPingConcurrency: _int(map['realPingConcurrency']) ?? 16,
    domainStrategy: '${map['domainStrategy'] ?? 'AsIs'}',
    sniffingEnabled: map['sniffingEnabled'] != false,
    routeOnly: map['routeOnly'] == true,
    fragmentEnabled: map['fragmentEnabled'] == true,
    fragmentPackets: '${map['fragmentPackets'] ?? 'tlshello'}',
    fragmentLength: '${map['fragmentLength'] ?? '50-100'}',
    fragmentInterval: '${map['fragmentInterval'] ?? '10-20'}',
    fragmentMaxSplit: _int(map['fragmentMaxSplit']) ?? 10,
    enableIpv6: map['enableIpv6'] != false,
    preferIpv6: map['preferIpv6'] == true,
    vpnMtu: _int(map['vpnMtu']) ?? 1500,
    autoUpdate: map['autoUpdate'] != false,
    updateIntervalHours: _int(map['updateIntervalHours']) ?? 12,
    themeMode: '${map['themeMode'] ?? 'system'}',
    language: '${map['language'] ?? 'en'}',
    performanceMode: map['performanceMode'] == true,
    performanceModePrompted: map['performanceModePrompted'] == true,
    ipCheckUrl: '${map['ipCheckUrl'] ?? 'https://api.ip.sb/geoip'}',
    telegramUrlConfigured: map['telegramUrlConfigured'] != false,
    telegramContact: '${map['telegramContact'] ?? ''}',
  );

  final String connectionMode;
  final String routingMode;
  final String customDomains;
  final String customIps;
  final bool enableLocalDns;
  final bool enableFakeDns;
  final String remoteDns;
  final String vpnDns;
  final String vpnInterfaceAddress;
  final int localSocksPort;
  final int realPingConcurrency;
  final String domainStrategy;
  final bool sniffingEnabled;
  final bool routeOnly;
  final bool fragmentEnabled;
  final String fragmentPackets;
  final String fragmentLength;
  final String fragmentInterval;
  final int fragmentMaxSplit;
  final bool enableIpv6;
  final bool preferIpv6;
  final int vpnMtu;
  final bool autoUpdate;
  final int updateIntervalHours;
  final String themeMode;
  final String language;
  final bool performanceMode;
  final bool performanceModePrompted;
  final String ipCheckUrl;
  final bool telegramUrlConfigured;
  final String telegramContact;

  NativeSettings withUpdates(Map<String, Object?> values) {
    String stringValue(String key, String current) =>
        values.containsKey(key) ? '${values[key]}' : current;
    bool boolValue(String key, bool current) =>
        values[key] is bool ? values[key]! as bool : current;
    int intValue(String key, int current) =>
        values[key] is num ? (values[key]! as num).toInt() : current;

    return NativeSettings(
      connectionMode: stringValue('connectionMode', connectionMode),
      routingMode: stringValue('routingMode', routingMode),
      customDomains: stringValue('customDomains', customDomains),
      customIps: stringValue('customIps', customIps),
      enableLocalDns: boolValue('enableLocalDns', enableLocalDns),
      enableFakeDns: boolValue('enableFakeDns', enableFakeDns),
      remoteDns: stringValue('remoteDns', remoteDns),
      vpnDns: stringValue('vpnDns', vpnDns),
      vpnInterfaceAddress: stringValue(
        'vpnInterfaceAddress',
        vpnInterfaceAddress,
      ),
      localSocksPort: intValue('localSocksPort', localSocksPort),
      realPingConcurrency: intValue('realPingConcurrency', realPingConcurrency),
      domainStrategy: stringValue('domainStrategy', domainStrategy),
      sniffingEnabled: boolValue('sniffingEnabled', sniffingEnabled),
      routeOnly: boolValue('routeOnly', routeOnly),
      fragmentEnabled: boolValue('fragmentEnabled', fragmentEnabled),
      fragmentPackets: stringValue('fragmentPackets', fragmentPackets),
      fragmentLength: stringValue('fragmentLength', fragmentLength),
      fragmentInterval: stringValue('fragmentInterval', fragmentInterval),
      fragmentMaxSplit: intValue('fragmentMaxSplit', fragmentMaxSplit),
      enableIpv6: boolValue('enableIpv6', enableIpv6),
      preferIpv6: boolValue('preferIpv6', preferIpv6),
      vpnMtu: intValue('vpnMtu', vpnMtu),
      autoUpdate: boolValue('autoUpdate', autoUpdate),
      updateIntervalHours: intValue('updateIntervalHours', updateIntervalHours),
      themeMode: stringValue('themeMode', themeMode),
      language: stringValue('language', language),
      performanceMode: boolValue('performanceMode', performanceMode),
      performanceModePrompted: boolValue(
        'performanceModePrompted',
        performanceModePrompted,
      ),
      ipCheckUrl: stringValue('ipCheckUrl', ipCheckUrl),
      telegramUrlConfigured: telegramUrlConfigured,
      telegramContact: telegramContact,
    );
  }

  ThemeMode get themeModeValue => switch (themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

class LogEntry {
  const LogEntry(this.time, this.level, this.message);

  factory LogEntry.fromMap(Map<dynamic, dynamic> map) {
    final now = DateTime.now();
    final rawTime = _int(map['time']);
    final maximum = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
    final safeTime = rawTime != null && rawTime >= 0 && rawTime <= maximum
        ? rawTime
        : now.millisecondsSinceEpoch;
    final rawLevel = '${map['level'] ?? 'info'}';
    final level = const {'info', 'warning', 'error'}.contains(rawLevel)
        ? rawLevel
        : 'info';
    final rawMessage = '${map['message'] ?? ''}';
    final message = rawMessage.length <= 1200
        ? rawMessage
        : rawMessage.substring(0, 1200);
    return LogEntry(
      DateTime.fromMillisecondsSinceEpoch(safeTime),
      level,
      message,
    );
  }

  final DateTime time;
  final String level;
  final String message;
}

class AppSnapshot {
  const AppSnapshot({
    this.servers = const [],
    this.connection = const ConnectionInfo(),
    this.usage = const SubscriptionUsage(),
    this.settings = const NativeSettings(),
    this.logs = const [],
    this.lastUpdated = 0,
    this.coreVersion = 'Unavailable',
    this.appVersion = '1.1.1',
    this.subscriptionConfigured = false,
    this.telegramEligible = false,
    this.subscriptionError,
    this.isRefreshing = false,
    this.isPinging = false,
    this.deletedServerCount = 0,
  });

  final List<ServerInfo> servers;
  final ConnectionInfo connection;
  final SubscriptionUsage usage;
  final NativeSettings settings;
  final List<LogEntry> logs;
  final int lastUpdated;
  final String coreVersion;
  final String appVersion;
  final bool subscriptionConfigured;
  final bool telegramEligible;
  final String? subscriptionError;
  final bool isRefreshing;
  final bool isPinging;
  final int deletedServerCount;

  ServerInfo? get selectedServer {
    for (final server in servers) {
      if (server.selected) return server;
    }
    return servers.isEmpty ? null : servers.first;
  }

  AppSnapshot copyWith({
    List<ServerInfo>? servers,
    ConnectionInfo? connection,
    SubscriptionUsage? usage,
    NativeSettings? settings,
    List<LogEntry>? logs,
    int? lastUpdated,
    String? coreVersion,
    String? appVersion,
    bool? subscriptionConfigured,
    bool? telegramEligible,
    String? subscriptionError,
    bool clearSubscriptionError = false,
    bool? isRefreshing,
    bool? isPinging,
    int? deletedServerCount,
  }) => AppSnapshot(
    servers: servers ?? this.servers,
    connection: connection ?? this.connection,
    usage: usage ?? this.usage,
    settings: settings ?? this.settings,
    logs: logs ?? this.logs,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    coreVersion: coreVersion ?? this.coreVersion,
    appVersion: appVersion ?? this.appVersion,
    subscriptionConfigured:
        subscriptionConfigured ?? this.subscriptionConfigured,
    telegramEligible: telegramEligible ?? this.telegramEligible,
    subscriptionError: clearSubscriptionError
        ? null
        : subscriptionError ?? this.subscriptionError,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isPinging: isPinging ?? this.isPinging,
    deletedServerCount: deletedServerCount ?? this.deletedServerCount,
  );
}
