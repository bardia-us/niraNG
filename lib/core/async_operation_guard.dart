import 'dart:async';

/// Coalesces duplicate UI commands while allowing unrelated operations to run.
class AsyncOperationGuard {
  AsyncOperationGuard({
    this.cooldown = const Duration(milliseconds: 500),
    Duration Function()? elapsed,
  }) {
    final clock = Stopwatch()..start();
    _elapsed = elapsed ?? (() => clock.elapsed);
  }

  final Duration cooldown;
  final Map<String, Future<void>> _running = {};
  late final Duration Function() _elapsed;
  final Map<String, Duration> _completedAt = {};
  final Map<String, Duration> _groupStartedAt = {};

  bool isRunning(String key) => _running.containsKey(key);

  Future<void> run(
    String key,
    Future<void> Function() operation, {
    String? cooldownGroup,
  }) {
    final active = _running[key];
    if (active != null) return active;

    final completed = _completedAt[key];
    if (completed != null && _elapsed() - completed < cooldown) {
      return Future<void>.value();
    }

    // Related commands share a tap interval, not a running-operation lock:
    // Disconnect can still cancel a slow Connect once the interval has passed.
    if (cooldownGroup != null) {
      final now = _elapsed();
      final started = _groupStartedAt[cooldownGroup];
      if (started != null && now - started < cooldown) {
        return Future<void>.value();
      }
      _groupStartedAt[cooldownGroup] = now;
    }

    late final Future<void> request;
    request = Future<void>.sync(operation).whenComplete(() {
      if (identical(_running[key], request)) {
        _running.remove(key);
        _completedAt[key] = _elapsed();
      }
    });
    _running[key] = request;
    return request;
  }
}
