import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/registration/device_registration.dart';

final appControllerProvider = AsyncNotifierProvider<AppController, AppSnapshot>(
  AppController.new,
);

final performanceModeProvider = Provider<bool>(
  (ref) => ref.watch(
    appControllerProvider.select(
      (value) => value.asData?.value.settings.performanceMode ?? false,
    ),
  ),
);

class AppController extends AsyncNotifier<AppSnapshot> {
  StreamSubscription<Map<dynamic, dynamic>>? _events;
  Future<void>? _logsRefresh;
  int _settingsRevision = 0;

  @override
  Future<AppSnapshot> build() async {
    _events = NirangNative.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      },
    );
    ref.onDispose(() => _events?.cancel());
    return _parseBootstrap(await NirangNative.initialize());
  }

  AppSnapshot? get _current => state.asData?.value;

  void _set(AppSnapshot Function(AppSnapshot value) update) {
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }

  Future<void> refreshSubscription() async {
    _set(
      (value) =>
          value.copyWith(isRefreshing: true, clearSubscriptionError: true),
    );
    try {
      final data = await NirangNative.refreshSubscription();
      _set(
        (value) => value.copyWith(
          servers: _servers(data['servers']),
          usage: SubscriptionUsage.fromMap(_map(data['usage'])),
          lastUpdated: _number(data['lastUpdated']),
          deletedServerCount: _number(data['deletedServerCount']),
        ),
      );
    } catch (error) {
      _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      rethrow;
    } finally {
      _set((value) => value.copyWith(isRefreshing: false));
    }
  }

  Future<void> selectServer(String id) async {
    final servers = await NirangNative.selectServer(id);
    _set((value) => value.copyWith(servers: _servers(servers)));
  }

  Future<void> deleteServer(String id) async {
    final data = await NirangNative.deleteServer(id);
    _set(
      (value) => value.copyWith(
        servers: _servers(data['servers']),
        deletedServerCount: _number(data['deletedServerCount']),
      ),
    );
  }

  Future<int> restoreDeletedServers() async {
    final data = await NirangNative.restoreDeletedServers();
    _set(
      (value) => value.copyWith(
        servers: _servers(data['servers']),
        deletedServerCount: _number(data['deletedServerCount']),
      ),
    );
    return _number(data['restored']);
  }

  Future<void> connect() => NirangNative.connect(_current?.selectedServer?.id);
  Future<void> disconnect() => NirangNative.disconnect();
  Future<void> restartService() => NirangNative.restartService();

  Future<String> requestQuickSettingsTile() =>
      NirangNative.requestQuickSettingsTile();

  Future<void> pingServer(String id) async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingServer(id);
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<void> pingAll() async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingAll();
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<void> cancelPing() async {
    await NirangNative.cancelPing();
    _set((value) => value.copyWith(isPinging: false));
  }

  Future<void> updateSettings(Map<String, Object?> values) async {
    final previous = _current?.settings ?? const NativeSettings();
    final revision = ++_settingsRevision;
    _set((value) => value.copyWith(settings: previous.withUpdates(values)));
    try {
      final map = await NirangNative.updateSettings(values);
      if (revision == _settingsRevision) {
        _set((value) => value.copyWith(settings: NativeSettings.fromMap(map)));
      }
    } catch (_) {
      if (revision == _settingsRevision) {
        _set((value) => value.copyWith(settings: previous));
      }
      rethrow;
    }
  }

  Future<void> refreshLogs() {
    final running = _logsRefresh;
    if (running != null) return running;
    late final Future<void> request;
    request =
        (() async {
          try {
            final logs = await NirangNative.getLogs();
            _set((value) => value.copyWith(logs: _logs(logs)));
          } catch (_) {
            // Keep the last valid log snapshot if the activity is being recreated.
          }
        })().whenComplete(() {
          if (identical(_logsRefresh, request)) _logsRefresh = null;
        });
    _logsRefresh = request;
    return request;
  }

  Future<void> clearLogs() async {
    await NirangNative.clearLogs();
    _set((value) => value.copyWith(logs: const []));
  }

  Future<void> openTelegram() => NirangNative.openTelegram();
  Future<void> openExternalUrl(Uri url) =>
      NirangNative.openExternalUrl(url.toString());

  Future<void> recordTelegramDecision(String decision) async {
    await NirangNative.recordTelegramDecision(decision);
    _set((value) => value.copyWith(telegramEligible: false));
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    final type = '${event['type'] ?? ''}';
    final data = event['data'];
    switch (type) {
      case 'connectionState':
        _set(
          (value) =>
              value.copyWith(connection: ConnectionInfo.fromMap(_map(data))),
        );
      case 'servers':
        _set((value) => value.copyWith(servers: _servers(data)));
      case 'serverPing':
        final update = _map(data);
        final id = '${update['id'] ?? ''}';
        _set(
          (value) => value.copyWith(
            servers: [
              for (final server in value.servers)
                if (server.id == id)
                  server.copyWith(
                    ping: _nullableNumber(update['ping']),
                    status: '${update['status'] ?? 'idle'}',
                  )
                else
                  server,
            ],
          ),
        );
      case 'subscription':
        final update = _map(data);
        _set(
          (value) => value.copyWith(
            servers: _servers(update['servers']),
            usage: SubscriptionUsage.fromMap(_map(update['usage'])),
            lastUpdated: _number(update['lastUpdated']),
            deletedServerCount: _number(update['deletedServerCount']),
          ),
        );
      case 'settings':
        _set(
          (value) =>
              value.copyWith(settings: NativeSettings.fromMap(_map(data))),
        );
      case 'coreVersion':
        _set((value) => value.copyWith(coreVersion: '$data'));
      case 'subscriptionError':
        _set((value) => value.copyWith(subscriptionError: '$data'));
      case 'accessBlocked':
        final details = _map(data);
        markDeviceAccessBlocked('${details['message'] ?? ''}');
      case 'pingCompleted':
      case 'pingCancelled':
        _set((value) => value.copyWith(isPinging: false));
    }
  }

  AppSnapshot _parseBootstrap(Map<dynamic, dynamic> map) => AppSnapshot(
    servers: _servers(map['servers']),
    connection: ConnectionInfo.fromMap(_map(map['connection'])),
    usage: SubscriptionUsage.fromMap(_map(map['usage'])),
    settings: NativeSettings.fromMap(_map(map['settings'])),
    logs: _logs(map['logs'] as List<dynamic>? ?? const []),
    lastUpdated: _number(map['lastUpdated']),
    coreVersion: '${map['coreVersion'] ?? 'Unavailable'}',
    appVersion: '${map['appVersion'] ?? '1.1.1'}',
    subscriptionConfigured: map['subscriptionConfigured'] == true,
    telegramEligible: map['telegramEligible'] == true,
    subscriptionError: map['subscriptionError']?.toString(),
    deletedServerCount: _number(map['deletedServerCount']),
  );
}

Map<dynamic, dynamic> _map(dynamic value) => value is Map ? value : const {};
int _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
int? _nullableNumber(dynamic value) => value == null ? null : _number(value);
List<ServerInfo> _servers(dynamic value) => value is List
    ? value.whereType<Map>().map(ServerInfo.fromMap).toList(growable: false)
    : const [];
List<LogEntry> _logs(List<dynamic> value) {
  final result = <LogEntry>[];
  for (final item in value.whereType<Map>().take(250)) {
    try {
      result.add(LogEntry.fromMap(item));
    } catch (_) {
      // A malformed native entry must not take down the entire log viewer.
    }
  }
  return List.unmodifiable(result);
}

String _errorText(Object error) => error
    .toString()
    .replaceFirst(RegExp(r'^PlatformException\([^,]+,\s*'), '')
    .split(',')
    .first;
