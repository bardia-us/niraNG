import '../../core/platform/native_models.dart';

List<ServerInfo> sortServersByTestResults(List<ServerInfo> servers) {
  final indexed = servers.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final leftPing = _successfulPing(left.$2);
    final rightPing = _successfulPing(right.$2);
    if (leftPing == null && rightPing == null) {
      return left.$1.compareTo(right.$1);
    }
    if (leftPing == null) return 1;
    if (rightPing == null) return -1;
    final latencyOrder = leftPing.compareTo(rightPing);
    return latencyOrder != 0 ? latencyOrder : left.$1.compareTo(right.$1);
  });
  return List<ServerInfo>.unmodifiable(indexed.map((entry) => entry.$2));
}

int? _successfulPing(ServerInfo server) =>
    server.status == 'success' && server.ping != null && server.ping! >= 0
    ? server.ping
    : null;
