List<T> orderSelectedFirst<T>(
  Iterable<T> values, {
  required bool Function(T value) isSelected,
  required String Function(T value) label,
}) {
  final result = values.toList(growable: false);
  result.sort((first, second) {
    final selectedComparison = (isSelected(second) ? 1 : 0).compareTo(
      isSelected(first) ? 1 : 0,
    );
    if (selectedComparison != 0) return selectedComparison;
    return label(first).toLowerCase().compareTo(label(second).toLowerCase());
  });
  return result;
}
