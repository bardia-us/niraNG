import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/update_checker.dart';

void main() {
  testWidgets('1.2.4 cumulative notes since 1.2.3 are available offline', (
    tester,
  ) async {
    final notes = await HttpOverrides.runZoned(
      () => const GitHubUpdateChecker().releaseNotes('1.2.4'),
      createHttpClient: (_) =>
          throw StateError('Current notes must be bundled'),
    );
    expect(notes.english, contains('1.2.3'));
    expect(notes.english, contains('4058'));
    expect(notes.english, contains('sing-box'));
    expect(notes.english, contains('cancelled'));
    expect(notes.persian, contains('سایفون'));
    expect(notes.persian, contains('4058'));
  });
}
