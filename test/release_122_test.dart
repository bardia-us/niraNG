import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/update_checker.dart';

void main() {
  testWidgets('1.2.2 release notes are bilingual and require no network', (
    tester,
  ) async {
    final notes = await HttpOverrides.runZoned(
      () => const GitHubUpdateChecker().releaseNotes('1.2.2'),
      createHttpClient: (_) =>
          throw StateError('Release notes must be bundled'),
    );
    expect(notes.english, contains('1.2.2'));
    expect(notes.english, contains('Local DNS'));
    expect(notes.persian, contains('شبکهٔ محلی'));
    expect(notes.persian, contains('4024'));
    expect(notes.english, isNot(contains('## فارسی')));
  });
}
