import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/update_checker.dart';
import 'package:nirang/core/widgets/update_dialog.dart';

void main() {
  test('recovery never opens arbitrary persisted URLs', () {
    const official = 'https://github.com/bardia-us/niraNG/releases/latest';
    for (final url in [
      'https://evil.example/update.apk',
      'https://github.com/other/repo/releases/download/v1/a.apk',
      'http://github.com/bardia-us/niraNG/releases/download/v1/a.apk',
      'https://user@github.com/bardia-us/niraNG/releases/download/v1/a.apk',
      'https://github.com:8443/bardia-us/niraNG/releases/download/v1/a.apk',
      'https://github.com/bardia-us/niraNG/releases/download/%2e%2e/%2e%2e/other',
      'https://github.com/bardia-us/niraNG/releases/download/a%2F..%2Fother',
    ]) {
      expect(
        officialUpdateBrowserDestination(Uri.parse(url)).toString(),
        official,
      );
    }
  });
  for (final mandatory in [true, false]) {
    testWidgets(
      '${mandatory ? 'mandatory' : 'optional'} download failure offers explicit retry and browser without bypassing gate',
      (tester) async {
        const control = MethodChannel('dev.nirang.client/control');
        const events = MethodChannel('dev.nirang.client/update_download');
        final calls = <MethodCall>[];
        var attempts = 0;
        final assetUrl = Uri.parse(
          'https://github.com/bardia-us/niraNG/releases/download/v9.0.0/niraNG-arm64-v8a.apk',
        );
        final release = ReleaseCheckResult(
          latestVersion: const SemanticVersion(9, 0, 0),
          releaseUrl: Uri.parse(
            'https://github.com/bardia-us/niraNG/releases/tag/v9.0.0',
          ),
          updateAvailable: true,
          mandatory: mandatory,
          assets: [
            ReleaseAsset(
              name: 'niraNG-arm64-v8a.apk',
              downloadUrl: assetUrl,
              size: 4096,
              sha256: 'a' * 64,
            ),
          ],
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          control,
          (call) async {
            calls.add(call);
            return switch (call.method) {
              'supportedAbis' => ['arm64-v8a'],
              'startUpdateDownload' => {
                'state': ++attempts == 1 ? 'failed' : 'downloading',
              },
              'getUpdateDownload' => {
                'state': attempts < 2 ? 'failed' : 'downloading',
              },
              _ => null,
            };
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          events,
          (_) async => null,
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppStrings.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showUpdateOptionsDialog(context, release),
                    child: const Text('START'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('START'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (!mandatory) {
          await tester.tap(find.text('Download and install'));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.text('Retry download'), findsOneWidget);
        expect(find.textContaining('another network or a VPN'), findsOneWidget);
        expect(find.text('Download with browser'), findsOneWidget);
        expect(find.textContaining('download continues'), findsNothing);
        expect(
          calls.where((call) => call.method == 'openExternalUrl'),
          isEmpty,
        );
        expect(
          tester.widget<PopScope>(find.byType(PopScope)).canPop,
          !mandatory,
        );
        await tester.tap(find.text('Download with browser'));
        await tester.pump();
        expect(calls.last.arguments, {'url': assetUrl.toString()});
        expect(find.text('Retry download'), findsOneWidget);
        await tester.tap(find.text('Retry download'));
        await tester.pump();
        expect(attempts, 2);
        final starts = calls
            .where((call) => call.method == 'startUpdateDownload')
            .toList();
        expect(starts.last.arguments, starts.first.arguments);
        expect(find.text('Retry download'), findsNothing);
        expect(find.text('Downloading update…'), findsOneWidget);
        // Retry must restore polling after the first terminal event canceled it.
        await tester.pump(const Duration(milliseconds: 800));
        expect(
          calls.where((call) => call.method == 'getUpdateDownload'),
          isNotEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          control,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          events,
          null,
        );
      },
    );
  }
}
