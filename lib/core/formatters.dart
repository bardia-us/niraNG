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

/// Moves the first country flag into the dedicated badge, wherever it occurs.
/// Other flags remain in the presentation text. The stored
/// subscription remark remains untouched.
String displayServerName(String value) {
  final trimmed = value.trimLeft();
  final match = countryFlagPattern.firstMatch(trimmed);
  if (match == null) return trimmed;
  final result = trimmed.replaceRange(match.start, match.end, '');
  return (match.start == 0
          ? result.replaceFirst(RegExp(r'^[\s\-–—:|·]+'), '')
          : result)
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

final countryFlagPattern = RegExp(
  r'[\u{1F1E6}-\u{1F1FF}]{2}\u{FE0F}?',
  unicode: true,
);

String countryCodeFromFlag(String flag) =>
    String.fromCharCodes(flag.runes.take(2).map((point) => point - 127397));
