import 'dart:async';

/// Coalesces duplicate UI commands while allowing unrelated operations to run.
class AsyncOperationGuard {
  AsyncOperationGuard({this.cooldown = const Duration(milliseconds: 450)});

  final Duration cooldown;
  final Map<String, Future<void>> _running = {};
  final Map<String, DateTime> _completedAt = {};

  bool isRunning(String key) => _running.containsKey(key);

  Future<void> run(String key, Future<void> Function() operation) {
    final active = _running[key];
    if (active != null) return active;

    final lastCompleted = _completedAt[key];
    if (lastCompleted != null &&
        DateTime.now().difference(lastCompleted) < cooldown) {
      return Future<void>.value();
    }

    late final Future<void> request;
    request = Future<void>.sync(operation).whenComplete(() {
      if (identical(_running[key], request)) {
        _running.remove(key);
        _completedAt[key] = DateTime.now();
      }
    });
    _running[key] = request;
    return request;
  }
}
