import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/update_checker.dart';

void main() {
  testWidgets('1.3.1 fixes are described offline without a network request', (
    tester,
  ) async {
    final notes = await HttpOverrides.runZoned(
      () => const GitHubUpdateChecker().releaseNotes('1.3.1'),
      createHttpClient: (_) => throw StateError('Notes must be bundled'),
    );
    expect(notes.english, contains('4056'));
    expect(notes.english, contains('isolated'));
    expect(notes.persian, contains('4056'));
    expect(notes.persian, contains('پینگ واقعی'));
  });
  testWidgets('1.3.0 multicore notes are bundled with real limitations', (
    tester,
  ) async {
    final notes = await HttpOverrides.runZoned(
      () => const GitHubUpdateChecker().releaseNotes('1.3.0'),
      createHttpClient: (_) => throw StateError('Notes must be bundled'),
    );
    expect(notes.english, contains('4055'));
    expect(notes.english, contains('disconnect'));
    expect(notes.english, contains('partial'));
    expect(notes.persian, contains('سایفون'));
    expect(notes.persian, contains('4055'));
  });
}
