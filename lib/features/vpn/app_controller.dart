import 'dart:async';

import 'package:flutter/services.dart';
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
  Timer? _noticeTimer;
  int _noticeRevision = 0;

  @override
  Future<AppSnapshot> build() async {
    _events = NirangNative.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      },
    );
    ref.onDispose(() {
      _events?.cancel();
      _noticeTimer?.cancel();
    });
    return _parseBootstrap(await NirangNative.initialize());
  }

  AppSnapshot? get _current => state.asData?.value;

  void _set(AppSnapshot Function(AppSnapshot value) update) {
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }

  Future<void> refreshSubscription() async {
    _showNotice('Updating subscription…', NoticeTone.processing);
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
      _showNotice('Subscription updated successfully', NoticeTone.success);
    } catch (error) {
      _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      _showNotice('Subscription update failed', NoticeTone.error);
      rethrow;
    } finally {
      _set((value) => value.copyWith(isRefreshing: false));
    }
  }

  Future<void> selectServer(String id) async {
    final servers = await NirangNative.selectServer(id);
    _set((value) => value.copyWith(servers: _servers(servers)));
  }

  Future<void> reorderServers(int oldIndex, int requestedNewIndex) async {
    final current = _current;
    if (current == null || oldIndex < 0 || oldIndex >= current.servers.length) {
      return;
    }
    final reordered = current.servers.toList();
    final server = reordered.removeAt(oldIndex);
    final newIndex = requestedNewIndex > oldIndex
        ? requestedNewIndex - 1
        : requestedNewIndex;
    reordered.insert(newIndex.clamp(0, reordered.length).toInt(), server);
    _set((value) => value.copyWith(servers: List.unmodifiable(reordered)));
    try {
      final servers = await NirangNative.reorderServers(
        reordered.map((item) => item.id).toList(growable: false),
      );
      _set((value) => value.copyWith(servers: _servers(servers)));
    } catch (_) {
      _set((value) => value.copyWith(servers: current.servers));
      rethrow;
    }
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

  Future<void> connect() async {
    final selected = _current?.selectedServer;
    if (selected == null) {
      _showNotice(
        _message(
          'Please select a server first.',
          'لطفاً ابتدا یک سرور انتخاب کنید.',
        ),
        NoticeTone.error,
      );
      return;
    }
    if (isSubscriptionNoticeName(selected.name)) {
      _showNotice(
        _message(
          'This server is not for connection. Please select another server.',
          'این سرور برای اتصال نیست. لطفاً سرور دیگری انتخاب کنید.',
        ),
        NoticeTone.error,
      );
      return;
    }
    _showNotice('Starting service…', NoticeTone.processing);
    try {
      await NirangNative.connect(selected.id);
    } on PlatformException catch (error) {
      final message = switch (error.code) {
        'no_server' => _message(
          'Please select a server first.',
          'لطفاً ابتدا یک سرور انتخاب کنید.',
        ),
        'not_connectable' => _message(
          'This server is not for connection. Please select another server.',
          'این سرور برای اتصال نیست. لطفاً سرور دیگری انتخاب کنید.',
        ),
        _ => _message('Connection could not be started.', 'اتصال شروع نشد.'),
      };
      _showNotice(message, NoticeTone.error);
    } catch (_) {
      _showNotice(
        _message('Connection could not be started.', 'اتصال شروع نشد.'),
        NoticeTone.error,
      );
    }
  }

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
        var connection = ConnectionInfo.fromMap(_map(data));
        final selected = _current?.selectedServer;
        if (connection.state == 'error' &&
            selected != null &&
            isSubscriptionNoticeName(selected.name)) {
          connection = ConnectionInfo(
            state: connection.state,
            serverId: connection.serverId,
            serverName: connection.serverName,
            publicIp: connection.publicIp,
            publicCountry: connection.publicCountry,
            publicCity: connection.publicCity,
            publicIpChecked: connection.publicIpChecked,
            error: _message(
              'This server is not for connection. Please select another server.',
              'این سرور برای اتصال نیست. لطفاً سرور دیگری انتخاب کنید.',
            ),
          );
        }
        _set((value) => value.copyWith(connection: connection));
        if (connection.state == 'connected') {
          _showNotice('Service started successfully', NoticeTone.success);
        } else if (connection.state == 'error') {
          _showNotice(
            connection.error ?? 'Connection failed',
            NoticeTone.error,
          );
        }
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

  void _showNotice(String message, NoticeTone tone) {
    final id = ++_noticeRevision;
    _noticeTimer?.cancel();
    _set((value) => value.copyWith(notice: TransientNotice(message, tone, id)));
    _noticeTimer = Timer(
      Duration(seconds: tone == NoticeTone.processing ? 5 : 3),
      () => _set(
        (value) =>
            value.notice?.id == id ? value.copyWith(clearNotice: true) : value,
      ),
    );
  }

  String _message(String english, String persian) =>
      _current?.settings.language == 'fa' ? persian : english;
}

bool isSubscriptionNoticeName(String name) {
  final normalized = name.trim().toLowerCase();
  final hasMarker =
      normalized.contains('هر دفعه آپدیت کنید') ||
      normalized.contains('هر دفعه به روز کنید') ||
      normalized.contains('هر بار آپدیت کنید') ||
      normalized.contains('update every time');
  return hasMarker &&
      RegExp(
        r'(?:^|[\s-])v\d+(?:\.\d+){1,3}(?:$|[\s-])',
        caseSensitive: false,
      ).hasMatch(normalized);
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
