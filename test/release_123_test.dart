import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/update_checker.dart';

void main() {
  testWidgets('1.2.3 release notes are bilingual and available offline', (
    tester,
  ) async {
    final notes = await HttpOverrides.runZoned(
      () => const GitHubUpdateChecker().releaseNotes('1.2.3'),
      createHttpClient: (_) => throw StateError('Notes must be bundled'),
    );
    expect(notes.english, contains('1.2.3'));
    expect(notes.english, contains('4054'));
    expect(notes.english, contains('echSockopt.dialerProxy'));
    expect(notes.persian, contains('ترافیک'));
    expect(notes.persian, contains('4054'));
    expect(notes.english, isNot(contains('## فارسی')));
    expect(notes.persian, isNot(contains('## English')));
  });
}
