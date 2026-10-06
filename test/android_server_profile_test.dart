import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/servers/server_information_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

const _control = MethodChannel('dev.nirang.client/control');
const _events = MethodChannel('dev.nirang.client/events');

Map<String, Object?> _profile({String security = 'TLS'}) => {
  'id': 'tls-server',
  'name': 'CDN profile',
  'protocol': 'VLESS',
  'transport': 'WebSocket',
  'security': security,
  'country': 'NL',
  'port': 443,
  'selected': true,
  'status': 'idle',
  'sni': 'origin.example.com',
  'fingerprint': 'chrome',
  'cipherSuites': 'TLS_AES_128_GCM_SHA256',
  'finalMask': '{"tcp":[]}',
  'alpn': 'h2,http/1.1',
  'profileEditable': true,
};

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(
      _control,
      (_) async => <String, Object?>{},
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, null);
    messenger.setMockMethodCallHandler(_control, null);
  });
  testWidgets(
    'TLS information opens an editor containing real profile options',
    (tester) async {
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
            home: ServerInformationScreen(
              server: ServerInfo.fromMap(_profile()),
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('edit-server-profile')),
        250,
      );
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      expect(find.text('FinalMask JSON'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(5));
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(
        fields.map((field) => field.controller!.text),
        containsAll([
          'origin.example.com',
          'chrome',
          'TLS_AES_128_GCM_SHA256',
          '{"tcp":[]}',
          'h2,http/1.1',
        ]),
      );
    },
  );

  testWidgets('read only profile has no editor action', (tester) async {
    final profile = _profile()..['profileEditable'] = false;
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
          home: ServerInformationScreen(server: ServerInfo.fromMap(profile)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('edit-server-profile')), findsNothing);
  });

  testWidgets(
    'save sends only edited values and reopening uses persisted native result',
    (tester) async {
      var profile = _profile();
      Map<dynamic, dynamic>? submitted;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_control, (call) async {
            if (call.method == 'initialize') {
              return {
                'servers': [profile],
              };
            }
            if (call.method == 'updateServerProfile') {
              final args = call.arguments as Map;
              expect(args['id'], 'tls-server');
              submitted = args['values'] as Map;
              profile = {...profile, 'fingerprint': submitted!['fp']};
              return [profile];
            }
            throw StateError('Unexpected native call ${call.method}');
          });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(appControllerProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppStrings.supportedLocales,
            home: ServerInformationScreen(
              server: ServerInfo.fromMap(_profile()),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-fp')),
        'unsafe',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-server-profile')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('save-server-profile')));
      await tester.pumpAndSettle();
      expect(submitted, {'fp': 'unsafe'});
      expect(
        container
            .read(appControllerProvider)
            .asData!
            .value
            .servers
            .single
            .fingerprint,
        'unsafe',
      );
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profile-fp')))
            .controller!
            .text,
        'unsafe',
      );
    },
  );

  testWidgets(
    'Reality offers SNI and fingerprint without editable TLS-only fields',
    (tester) async {
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
            home: ServerInformationScreen(
              server: ServerInfo.fromMap(_profile(security: 'Reality')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byKey(const ValueKey('profile-fm')), findsNothing);
      expect(find.byKey(const ValueKey('profile-cs')), findsNothing);
      expect(find.byKey(const ValueKey('profile-alpn')), findsNothing);
    },
  );

  testWidgets('invalid FinalMask stops save before native mutation', (
    tester,
  ) async {
    var mutations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_control, (call) async {
          if (call.method == 'initialize') return <String, Object?>{};
          if (call.method == 'updateServerProfile') mutations++;
          return [];
        });
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
          home: ServerInformationScreen(server: ServerInfo.fromMap(_profile())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile-fm')), '[]');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-server-profile')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('save-server-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Check the profile settings'), findsOneWidget);
    expect(mutations, 0);
  });

  testWidgets(
    'native rejection keeps editor open and preserves unsaved values',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_control, (call) async {
            if (call.method == 'initialize') return <String, Object?>{};
            if (call.method == 'updateServerProfile') {
              throw PlatformException(code: 'invalid_profile');
            }
            throw StateError('Unexpected native call ${call.method}');
          });
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
            home: ServerInformationScreen(
              server: ServerInfo.fromMap(_profile()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-fp')),
        'invented',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-server-profile')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('save-server-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Profile could not be saved'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profile-fp')))
            .controller!
            .text,
        'invented',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('save-server-profile')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
