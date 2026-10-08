import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/registration/device_registration.dart';
import '../../core/async_operation_guard.dart';
import '../../core/interaction_feedback.dart';
import '../../core/user_facing_error.dart';
import '../servers/server_sorting.dart';

final appControllerProvider = AsyncNotifierProvider<AppController, AppSnapshot>(
  AppController.new,
);

final performanceModeProvider = Provider<bool>(
  (ref) => ref.watch(
    appControllerProvider.select(
      (value) => value.asData?.value.settings.performanceMode ?? true,
    ),
  ),
);

class AppController extends AsyncNotifier<AppSnapshot> {
  StreamSubscription<Map<dynamic, dynamic>>? _events;
  Future<void>? _logsRefresh;
  int _settingsRevision = 0;
  Timer? _noticeTimer;
  int _noticeRevision = 0;
  final _operationGuard = AsyncOperationGuard();
  Future<void> _serverMutationTail = Future<void>.value();
  final Map<String, int> _pingRevisions = {};
  Map<String, int>? _activeServerPingRevisions;
  final _ipClock = Stopwatch()..start();
  int? _lastIpRequest;
  int _connectionRevision = 0;
  String? _connectedProbeId;

  @override
  Future<AppSnapshot> build() async {
    _events = NirangNative.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        _set(
          (value) => value.copyWith(subscriptionError: _friendlyError(error)),
        );
      },
    );
    ref.onDispose(() {
      _events?.cancel();
      _noticeTimer?.cancel();
    });
    return _parseBootstrap(await NirangNative.initialize());
  }

  AppSnapshot? get _current => state.asData?.value;

  Future<void> refreshPublicIp() =>
      _operationGuard.run('refreshPublicIp', () async {
        final previous = _current?.connection;
        final now = _ipClock.elapsedMilliseconds;
        if (previous == null ||
            !previous.isConnected ||
            !previous.publicIpChecked ||
            (_lastIpRequest != null && now - _lastIpRequest! < 5000)) {
          return;
        }
        _lastIpRequest = now;
        final revision = _connectionRevision;
        _set(
          (value) => value.copyWith(
            connection: ConnectionInfo(
              state: previous.state,
              serverId: previous.serverId,
              serverName: previous.serverName,
              error: previous.error,
            ),
          ),
        );
        try {
          final accepted = await NirangNative.refreshPublicIp();
          if (!accepted) _restoreIp(previous, revision);
        } catch (_) {
          _restoreIp(previous, revision);
          rethrow;
        }
      });

  void _restoreIp(ConnectionInfo previous, int revision) => _set(
    (value) =>
        revision == _connectionRevision &&
            value.connection.isConnected &&
            value.connection.serverId == previous.serverId &&
            !value.connection.publicIpChecked
        ? value.copyWith(connection: previous)
        : value,
  );

  void _set(AppSnapshot Function(AppSnapshot value) update) {
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }

  Future<void> refreshSubscription() =>
      _operationGuard.run('refreshSubscription', _refreshSubscription);

  Future<void> _refreshSubscription() async {
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
      if (error is PlatformException && error.code == 'blocked') {
        markDeviceAccessBlocked(error.message);
      }
      if (error is PlatformException && error.code == 'outdated') {
        markDeviceUpdateRequired();
      }
      _set((value) => value.copyWith(subscriptionError: _friendlyError(error)));
      _showNotice('Subscription update failed', NoticeTone.error);
      rethrow;
    } finally {
      _set((value) => value.copyWith(isRefreshing: false));
    }
  }

  Future<void> selectServer(String id) {
    _playInteractionFeedback();
    return _queueServerMutation(() async {
      final servers = await NirangNative.selectServer(id);
      _applyNativeServers(servers);
    });
  }

  Future<void> updateServerProfile(String id, Map<String, Object?> values) =>
      _queueServerMutation(() async {
        _applyNativeServers(await NirangNative.updateServerProfile(id, values));
      });

  Future<void> reorderServers(int oldIndex, int requestedNewIndex) {
    final current = _current;
    if (current == null || oldIndex < 0 || oldIndex >= current.servers.length) {
      return Future<void>.value();
    }
    final reordered = current.servers.toList();
    final server = reordered.removeAt(oldIndex);
    final newIndex = requestedNewIndex > oldIndex
        ? requestedNewIndex - 1
        : requestedNewIndex;
    final insertion = newIndex.clamp(0, reordered.length).toInt();
    final beforeId = insertion < reordered.length
        ? reordered[insertion].id
        : null;
    // Capture the drag's server/anchor from the visible order. A preceding
    // failed write may roll back that order before this queued move executes.
    return _queueServerMutation(() async {
      final latest = _current?.servers.toList();
      if (latest == null) return;
      final source = latest.indexWhere((item) => item.id == server.id);
      if (source < 0) return;
      final moved = latest.removeAt(source);
      final target = latest.indexWhere((item) => item.id == beforeId);
      latest.insert(target < 0 ? latest.length : target, moved);
      await _persistServerOrder(latest);
    });
  }

  Future<void> sortServersByLatency() => _operationGuard.run(
    'serverOrder',
    () => _queueServerMutation(() async {
      final current = _current;
      if (current == null || current.servers.length < 2) return;
      final sorted = sortServersByTestResults(current.servers);
      if (sorted.indexed.every(
        (entry) => entry.$2.id == current.servers[entry.$1].id,
      )) {
        return;
      }
      await _persistServerOrder(sorted);
    }),
  );

  // Native selection replies include the stored server order. Keep these writes
  // sequential so an older reply cannot reset a later order or selection.
  Future<void> _queueServerMutation(Future<void> Function() operation) {
    final request = _serverMutationTail.then((_) async {
      _activeServerPingRevisions = Map.of(_pingRevisions);
      try {
        await operation();
      } finally {
        _activeServerPingRevisions = null;
      }
    });
    _serverMutationTail = request.then<void>((_) {}, onError: (Object _) {});
    return request;
  }

  Future<void> _persistServerOrder(List<ServerInfo> servers) async {
    final previousIds = _current!.servers.map((server) => server.id).toList();
    _set((value) => value.copyWith(servers: List.unmodifiable(servers)));
    try {
      _applyNativeServers(
        await NirangNative.reorderServers(
          servers.map((server) => server.id).toList(growable: false),
        ),
      );
    } catch (_) {
      // Restore only order: newer ping/selection events still belong to the UI.
      _set((value) {
        final byId = {for (final server in value.servers) server.id: server};
        return value.copyWith(
          servers: [
            for (final id in previousIds) ?byId.remove(id),
            ...byId.values,
          ],
        );
      });
      rethrow;
    }
  }

  void _applyNativeServers(dynamic data) {
    final requestedRevisions = _activeServerPingRevisions;
    _set((value) {
      final current = {for (final server in value.servers) server.id: server};
      return value.copyWith(
        servers: [
          for (final server in _servers(data))
            if (requestedRevisions != null &&
                (_pingRevisions[server.id] ?? 0) !=
                    (requestedRevisions[server.id] ?? 0) &&
                current.containsKey(server.id))
              server.copyWith(
                ping: current[server.id]!.ping,
                clearPing: current[server.id]!.ping == null,
                status: current[server.id]!.status,
              )
            else
              server,
        ],
      );
    });
  }

  void _playInteractionFeedback() => unawaited(
    InteractionFeedback.play(_current?.settings.feedbackMode ?? 'haptic'),
  );

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

  Future<void> connect() {
    return _operationGuard.run(
      'connect',
      _connect,
      cooldownGroup: 'connection',
    );
  }

  Future<void> _connect() async {
    _playInteractionFeedback();
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

  Future<void> disconnect() {
    return _operationGuard.run('disconnect', () async {
      _playInteractionFeedback();
      await NirangNative.disconnect();
    }, cooldownGroup: 'connection');
  }

  Future<void> restartService() => _operationGuard.run(
    'restartService',
    NirangNative.restartService,
    cooldownGroup: 'connection',
  );

  Future<String> requestQuickSettingsTile() =>
      NirangNative.requestQuickSettingsTile();

  Future<void> pingServer(String id) => _current?.isPinging == true
      ? Future<void>.value()
      : _operationGuard.run('ping', () => _pingServer(id));

  Future<void> _pingServer(String id) async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingServer(id);
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<void> pingAll() => _current?.isPinging == true
      ? Future<void>.value()
      : _operationGuard.run('ping', _pingAll);

  Future<void> _pingAll() async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingAll();
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<void> tcpPingAll() => _current?.isPinging == true
      ? Future<void>.value()
      : _operationGuard.run('ping', () async {
          _set((value) => value.copyWith(isPinging: true));
          try {
            await NirangNative.tcpPingAll();
          } catch (_) {
            _set((value) => value.copyWith(isPinging: false));
            rethrow;
          }
        });

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

  Future<void> resetSettings() =>
      _operationGuard.run('resetSettings', () async {
        final map = await NirangNative.resetSettings();
        _set((value) => value.copyWith(settings: NativeSettings.fromMap(map)));
      });

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

  Future<void> recordWhatsNewSeen() async {
    await NirangNative.recordWhatsNewSeen();
    _set((value) => value.copyWith(whatsNewSeenBuild: value.appBuild));
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    final type = '${event['type'] ?? ''}';
    final data = event['data'];
    switch (type) {
      case 'connectionState':
        _connectionRevision++;
        final previousState = _current?.connection.state;
        var connection = ConnectionInfo.fromMap(_map(data));
        if (connection.state != previousState ||
            connection.serverId != _current?.connection.serverId) {
          _connectedProbeId = null;
        }
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
        _set(
          (value) => value.copyWith(
            connection: connection,
            hasCompletedPing:
                connection.isConnected &&
                    previousState == 'connected' &&
                    connection.serverId == value.connection.serverId
                ? value.hasCompletedPing
                : false,
          ),
        );
        if (connection.state == 'connected' && previousState != 'connected') {
          _showNotice('Service started successfully', NoticeTone.success);
        } else if (connection.state == 'error') {
          _showNotice(
            connection.error ?? 'Connection failed',
            NoticeTone.error,
          );
        }
      case 'servers':
        _applyNativeServers(data);
      case 'serverPing':
        final update = _map(data);
        final id = '${update['id'] ?? ''}';
        final probeId = update['probeId']?.toString();
        final status = '${update['status'] ?? 'idle'}';
        final connection = _current?.connection;
        final matchesConnection =
            connection?.isConnected == true && connection?.serverId == id;
        if (status == 'testing' && matchesConnection && probeId != null) {
          _connectedProbeId = probeId;
        }
        final completedConnectedProbe =
            matchesConnection &&
            probeId != null &&
            probeId == _connectedProbeId &&
            (status == 'success' || status == 'timeout');
        if (completedConnectedProbe) _connectedProbeId = null;
        _pingRevisions[id] = (_pingRevisions[id] ?? 0) + 1;
        _set(
          (value) => value.copyWith(
            hasCompletedPing: value.hasCompletedPing || completedConnectedProbe,
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
      case 'accessAllowed':
        clearDeviceAccessBlocked();
        clearDeviceUpdateRequired();
      case 'updateRequired':
        markDeviceUpdateRequired();
      case 'pingCompleted':
        _set((value) => value.copyWith(isPinging: false));
      case 'pingCancelled':
        _connectedProbeId = null;
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
    appBuild: _number(map['appBuild']),
    whatsNewSeenBuild: _number(map['whatsNewSeenBuild']),
    whatsNewUpgradeFromBuild: _number(map['whatsNewUpgradeFromBuild']),
    subscriptionConfigured: map['subscriptionConfigured'] == true,
    telegramEligible: map['telegramEligible'] == true,
    telegramStage: '${map['telegramStage'] ?? 'first'}',
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

  String _friendlyError(Object error) => userFacingError(
    error,
    persian: _current?.settings.language == 'fa',
  ).combined;
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
