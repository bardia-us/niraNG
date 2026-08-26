String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = value >= 100 || index == 0
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}

String formatDateTime(int epochMillis, {bool dateOnly = false}) {
  if (epochMillis <= 0) return '—';
  final value = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  final date = '${value.year}-${two(value.month)}-${two(value.day)}';
  return dateOnly ? date : '$date ${two(value.hour)}:${two(value.minute)}';
}

String countryFlag(String code) {
  final normalized = code.trim().toUpperCase();
  if (normalized.length != 2) return '🌐';
  return String.fromCharCodes(
    normalized.codeUnits.map((unit) => unit + 127397),
  );
}
