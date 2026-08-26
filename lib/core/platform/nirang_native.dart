import 'dart:async';

import 'package:flutter/services.dart';

class NirangNative {
  NirangNative._();

  static const _methods = MethodChannel('dev.nirang.client/control');
  static const _events = EventChannel('dev.nirang.client/events');

  static Stream<Map<dynamic, dynamic>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<dynamic, dynamic>>();

  static Future<Map<dynamic, dynamic>> initialize() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>('initialize')) ?? {};

  static Future<Map<dynamic, dynamic>> refreshSubscription() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'refreshSubscription',
      )) ??
      {};

  static Future<List<dynamic>> selectServer(String id) async =>
      (await _methods.invokeMethod<List<dynamic>>('selectServer', {
        'id': id,
      })) ??
      const [];
  static Future<Map<dynamic, dynamic>> deleteServer(String id) async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>('deleteServer', {
        'id': id,
      })) ??
      {};
  static Future<Map<dynamic, dynamic>> restoreDeletedServers() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'restoreDeletedServers',
      )) ??
      {};
  static Future<void> connect(String? id) =>
      _methods.invokeMethod('connect', {'id': id});
  static Future<void> disconnect() => _methods.invokeMethod('disconnect');
  static Future<void> restartService() =>
      _methods.invokeMethod('restartService');
  static Future<void> pingServer(String id) =>
      _methods.invokeMethod('pingServer', {'id': id});
  static Future<void> pingAll() => _methods.invokeMethod('pingAll');
  static Future<void> cancelPing() => _methods.invokeMethod('cancelPing');

  static Future<Map<dynamic, dynamic>> updateSettings(
    Map<String, Object?> values,
  ) async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'updateSettings',
        values,
      )) ??
      {};

  static Future<List<dynamic>> getLogs() async =>
      (await _methods.invokeMethod<List<dynamic>>('getLogs')) ?? const [];
  static Future<void> clearLogs() => _methods.invokeMethod('clearLogs');
  static Future<void> openTelegram() => _methods.invokeMethod('openTelegram');
  static Future<void> openExternalUrl(String url) =>
      _methods.invokeMethod('openExternalUrl', {'url': url});
  static Future<void> recordTelegramDecision(String decision) =>
      _methods.invokeMethod('recordTelegramDecision', {'decision': decision});
  static Future<void> recordFlutterError(String message) =>
      _methods.invokeMethod('recordFlutterError', {'message': message});
}
