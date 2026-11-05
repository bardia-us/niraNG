import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/update_checker.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/whats_new_dialog.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: true));
}

Future<void> mount(
  WidgetTester tester,
  Future<BilingualReleaseNotes> Function() load,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(_Controller.new)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNirangDialog<bool>(
                context: context,
                builder: (_) => WhatsNewDialog(persian: false, loadNotes: load),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'pending notes show progress and can close without marking seen',
    (tester) async {
      final pending = Completer<BilingualReleaseNotes>();
      await mount(tester, () => pending.future);
      expect(find.text('Loading release notes…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Got it'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewDialog), findsNothing);
      pending.complete(
        const BilingualReleaseNotes(english: 'Late content', persian: ''),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failure remains closable and retry loads notes', (tester) async {
    var tries = 0;
    await mount(tester, () async {
      if (++tries == 1) throw StateError('offline');
      return const BilingualReleaseNotes(
        english: 'Loaded changes',
        persian: '',
      );
    });
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded changes'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  });
  testWidgets('stalled loading has a bounded timeout', (tester) async {
    final pending = Completer<BilingualReleaseNotes>();
    await mount(tester, () => pending.future);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    pending.complete(const BilingualReleaseNotes(english: '', persian: ''));
  });
}
