import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/vpn/app_controller.dart';

const _control = MethodChannel('dev.nirang.client/control');
const _events = MethodChannel('dev.nirang.client/events');
const _feedback = MethodChannel('dev.nirang.client/feedback');

Map<String, Object?> _server(String id, int ping, {bool selected = false}) => {
  'id': id,
  'name': 'Server $id',
  'country': 'DE',
  'protocol': 'VLESS',
  'transport': 'TCP',
  'security': 'TLS',
  'port': 443,
  'sni': '',
  'credentialLabel': '',
  'credentialMasked': '',
  'realityPublicKeyMasked': '',
  'shortIdMasked': '',
  'ping': ping,
  'selected': selected,
  'status': 'success',
};

// The channel is the external boundary: controller/provider/model code is real.
class _NativeFixture {
  List<Map<String, Object?>> servers = [
    _server('a', 120, selected: true),
    _server('b', 30),
    _server('c', 70),
  ];
  final List<String> mutations = [];
  final List<MethodCall> feedback = [];
  final List<MethodCall> haptics = [];
  String? feedbackMode;
  Future<void> Function()? beforeReorder;
  Future<void> Function()? beforeSelect;
  Future<void> Function()? beforeConnect;
  Future<void> Function()? beforeDisconnect;
  bool feedbackFails = false;

  List<Map<String, Object?>> snapshot() => [
    for (final server in servers) Map<String, Object?>.of(server),
  ];

  Future<ProviderContainer> initialize(WidgetTester tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(_feedback, (call) async {
      feedback.add(call);
      if (feedbackFails) throw MissingPluginException();
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      haptics.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(_control, (call) async {
      switch (call.method) {
        case 'initialize':
          return {
            'servers': snapshot(),
            'settings': {
              if (feedbackMode != null) 'feedbackMode': feedbackMode,
            },
            'connection': {'state': 'disconnected'},
            'usage': <String, Object?>{},
            'logs': <Object?>[],
            'subscriptionConfigured': true,
          };
        case 'reorderServers':
          mutations.add('reorder');
          final ids = List<String>.from((call.arguments as Map)['ids'] as List);
          final byId = {for (final server in servers) server['id']: server};
          final response = [
            for (final id in ids) Map<String, Object?>.of(byId[id]!),
          ];
          await beforeReorder?.call();
          final latest = {for (final server in servers) server['id']: server};
          servers = [for (final id in ids) latest[id]!];
          return response;
        case 'selectServer':
          mutations.add('select');
          final id = (call.arguments as Map)['id'];
          final response = [
            for (final server in servers)
              {...server, 'selected': server['id'] == id},
          ];
          await beforeSelect?.call();
          servers = [
            for (final server in servers)
              {...server, 'selected': server['id'] == id},
          ];
          return response;
        case 'connect':
          mutations.add('connect');
          await beforeConnect?.call();
          return null;
        case 'disconnect':
          mutations.add('disconnect');
          await beforeDisconnect?.call();
          return null;
        default:
          throw StateError('Unexpected native call ${call.method}');
      }
    });
    final container = ProviderContainer();
    container.listen(appControllerProvider, (_, _) {});
    addTearDown(() async {
      container.dispose();
      await tester.pump();
      for (final channel in [
        _control,
        _events,
        _feedback,
        SystemChannels.platform,
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    await container.read(appControllerProvider.future);
    return container;
  }

  Future<void> ping(WidgetTester tester, String id, int ping) async {
    servers = [
      for (final server in servers)
        if (server['id'] == id)
          {...server, 'ping': ping, 'status': 'success'}
        else
          server,
    ];
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _events.name,
      const StandardMethodCodec().encodeSuccessEnvelope({
        'type': 'serverPing',
        'data': {'id': id, 'ping': ping, 'status': 'success'},
      }),
      (_) {},
    );
    await tester.pump();
  }
}

AppSnapshot _state(ProviderContainer container) =>
    container.read(appControllerProvider).requireValue;
List<String> _ids(ProviderContainer container) =>
    _state(container).servers.map((server) => server.id).toList();

void main() {
  testWidgets('latency sorting survives selecting another server', (
    tester,
  ) async {
    final native = _NativeFixture();
    final container = await native.initialize(tester);
    final controller = container.read(appControllerProvider.notifier);

    await controller.sortServersByLatency();
    expect(_ids(container), ['b', 'c', 'a']);
    await controller.selectServer('c');

    expect(_ids(container), ['b', 'c', 'a']);
    expect(_state(container).selectedServer!.id, 'c');
    expect(_state(container).servers.map((server) => server.ping), [
      30,
      70,
      120,
    ]);
    // Rebuilding the provider reloads the native order, as after a restart.
    container.invalidate(appControllerProvider);
    await container.read(appControllerProvider.future);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_ids(container), ['b', 'c', 'a']);
  });

  testWidgets('failed sort rolls order back without losing a newer ping', (
    tester,
  ) async {
    final native = _NativeFixture();
    final pending = Completer<void>();
    native.beforeReorder = () => pending.future;
    final container = await native.initialize(tester);
    final controller = container.read(appControllerProvider.notifier);
    final sort = controller.sortServersByLatency();
    final failure = expectLater(sort, throwsA(isA<PlatformException>()));
    await tester.pump();
    expect(_ids(container), ['b', 'c', 'a']);
    await native.ping(tester, 'a', 12);
    pending.completeError(PlatformException(code: 'persist_failed'));
    await failure;

    expect(_ids(container), ['a', 'b', 'c']);
    expect(_state(container).servers.first.ping, 12);
    expect(_state(container).selectedServer!.id, 'a');
  });

  testWidgets(
    'sort, manual reorder and selection preserve their invocation order',
    (tester) async {
      final native = _NativeFixture();
      final pending = Completer<void>();
      native.beforeReorder = () => pending.future;
      final container = await native.initialize(tester);
      final controller = container.read(appControllerProvider.notifier);
      final sort = controller.sortServersByLatency();
      await tester.pump();
      final reorder = controller.reorderServers(0, 3);
      final select = controller.selectServer('c');
      await tester.pump();
      expect(native.mutations, ['reorder']);
      await native.ping(tester, 'a', 15);
      pending.complete();
      await Future.wait([sort, reorder, select]);

      expect(_ids(container), ['c', 'a', 'b']);
      expect(_state(container).selectedServer!.id, 'c');
      expect(
        _state(
          container,
        ).servers.singleWhere((server) => server.id == 'a').ping,
        15,
      );
      expect(native.mutations, ['reorder', 'reorder', 'select']);
    },
  );

  testWidgets('a delayed selection reply does not erase a newer ping', (
    tester,
  ) async {
    final native = _NativeFixture();
    final pending = Completer<void>();
    native.beforeSelect = () => pending.future;
    final container = await native.initialize(tester);
    final controller = container.read(appControllerProvider.notifier);
    final select = controller.selectServer('b');
    await tester.pump();
    await native.ping(tester, 'b', 9);
    pending.complete();
    await select;

    expect(_state(container).selectedServer!.id, 'b');
    expect(
      _state(container).servers.singleWhere((server) => server.id == 'b').ping,
      9,
    );
  });

  testWidgets(
    'manual move queued after a failed sort still moves the intended server',
    (tester) async {
      final native = _NativeFixture();
      final pending = Completer<void>();
      var attempt = 0;
      native.beforeReorder = () =>
          ++attempt == 1 ? pending.future : Future<void>.value();
      final container = await native.initialize(tester);
      final controller = container.read(appControllerProvider.notifier);
      final sort = controller.sortServersByLatency();
      final failure = expectLater(sort, throwsA(isA<PlatformException>()));
      await tester.pump();
      // The user sees b,c,a and drags b to the end.
      expect(_ids(container), ['b', 'c', 'a']);
      final manual = controller.reorderServers(0, 3);
      final selection = controller.selectServer('c');
      pending.completeError(PlatformException(code: 'persist_failed'));
      await failure;
      await Future.wait([manual, selection]);

      expect(_ids(container), ['a', 'c', 'b']);
      expect(_state(container).selectedServer!.id, 'c');
    },
  );

  for (final action in ['select', 'connect', 'disconnect']) {
    testWidgets('$action triggers default haptic before native completion', (
      tester,
    ) async {
      final native = _NativeFixture();
      final pending = Completer<void>();
      native.beforeSelect = () => pending.future;
      native.beforeConnect = () => pending.future;
      native.beforeDisconnect = () => pending.future;
      final container = await native.initialize(tester);
      final controller = container.read(appControllerProvider.notifier);
      final request = switch (action) {
        'select' => controller.selectServer('b'),
        'connect' => controller.connect(),
        _ => controller.disconnect(),
      };
      await tester.pump();
      final haptics = native.haptics.where(
        (call) => call.method == 'HapticFeedback.vibrate',
      );
      expect(haptics, hasLength(1));
      expect(haptics.single.arguments, 'HapticFeedbackType.selectionClick');
      pending.complete();
      await request;
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('sound feedback uses its native channel even if unavailable', (
    tester,
  ) async {
    final native = _NativeFixture()
      ..feedbackMode = 'sound'
      ..feedbackFails = true;
    final container = await native.initialize(tester);
    await container.read(appControllerProvider.notifier).selectServer('b');
    await tester.pump();

    expect(native.feedback.map((call) => call.method), ['play']);
    expect(_state(container).selectedServer!.id, 'b');
    expect(native.haptics, isEmpty);
  });

  testWidgets('off mode performs the command without feedback', (tester) async {
    final native = _NativeFixture()..feedbackMode = 'off';
    final container = await native.initialize(tester);
    await container.read(appControllerProvider.notifier).selectServer('b');
    expect(_state(container).selectedServer!.id, 'b');
    expect(native.feedback, isEmpty);
    expect(native.haptics, isEmpty);
  });
}
