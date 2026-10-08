import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/servers/server_information_screen.dart';
import 'package:nirang/features/servers/server_profile_settings_screen.dart';
import 'package:nirang/features/servers/tls_profile_choices.dart';
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
  testWidgets('advanced bundled fingerprints are selectable without typing', (
    tester,
  ) async {
    final profile = _profile()..['fingerprint'] = 'hellochrome_133';
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
          home: ServerProfileSettingsScreen(
            server: ServerInfo.fromMap(profile),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('profile-fp')),
    );
    final button = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('profile-fp')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    expect(
      button.items!.map((item) => item.value),
      containsAll(profileAdvancedFingerprints),
    );
    expect(dropdown.initialValue, 'hellochrome_133');
    expect(find.byKey(const ValueKey('profile-custom-fp')), findsNothing);
  });
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
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(
        fields.map((field) => field.controller!.text),
        containsAll([
          'origin.example.com',
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
      await tester.tap(find.byKey(const ValueKey('profile-fp')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('unsafe'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('unsafe').last);
      await tester.pumpAndSettle();
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
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('profile-fp')),
            )
            .initialValue,
        'unsafe',
      );
    },
  );

  testWidgets(
    'imported REALITY unsafe fingerprint can be corrected without crashing',
    (tester) async {
      final profile = _profile(security: 'Reality')..['fingerprint'] = 'unsafe';
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('profile-custom-fp')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-server-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a supported fingerprint'), findsOneWidget);
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
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-fp')));
      await tester.pumpAndSettle();
      expect(find.text('unsafe'), findsNothing);
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
        find.byKey(const ValueKey('profile-sni')),
        'edited.example.com',
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
            .widget<TextFormField>(find.byKey(const ValueKey('profile-sni')))
            .controller!
            .text,
        'edited.example.com',
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

  testWidgets(
    'ALPN selection keeps imported custom protocols when toggling a standard option',
    (tester) async {
      final profile = _profile()..['alpn'] = 'custom/1,h2';
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-alpn')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('profile-alpn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('http/1.1').last);
      await tester.tap(find.byKey(const ValueKey('apply-profile-choices')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profile-alpn')))
            .controller!
            .text,
        'custom/1,h2,http/1.1',
      );
    },
  );

  testWidgets(
    'editing SNI does not normalize untouched imported advanced values',
    (tester) async {
      final profile = _profile()
        ..['fingerprint'] = 'future-fingerprint'
        ..['cipherSuites'] = '  FUTURE_CIPHER  '
        ..['alpn'] = ' custom/1 ,h2 '
        ..['finalMask'] = ' {"future":{"option":true}} ';
      Map<dynamic, dynamic>? submitted;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_control, (call) async {
            if (call.method == 'initialize') {
              return {
                'servers': [profile],
              };
            }
            if (call.method == 'updateServerProfile') {
              submitted = (call.arguments as Map)['values'] as Map;
              return [profile];
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
            home: ServerInformationScreen(server: ServerInfo.fromMap(profile)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-sni')),
        'edited.example.com',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('save-server-profile')),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('save-server-profile')));
      await tester.pumpAndSettle();
      expect(submitted, {'sni': 'edited.example.com'});
    },
  );

  testWidgets(
    'confirming an untouched ALPN selection preserves imported spacing and duplicates',
    (tester) async {
      final profile = _profile()..['alpn'] = ' custom/1 ,h2,h2 ';
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile-alpn')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('profile-alpn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-profile-choices')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('profile-alpn')))
            .controller!
            .text,
        ' custom/1 ,h2,h2 ',
      );
    },
  );

  testWidgets(
    'selected information header keeps compact badge within narrow Persian layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final profile = _profile()
        ..['name'] = 'نام طولانی سرور انتخاب‌شده برای اتصال';
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('fa'),
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
      await tester.pumpAndSettle();
      final badge = find.byKey(const ValueKey('selected-profile-badge'));
      expect(badge, findsOneWidget);
      expect(tester.getSize(badge).height, lessThanOrEqualTo(30));
      expect(tester.takeException(), isNull);
    },
  );
}
