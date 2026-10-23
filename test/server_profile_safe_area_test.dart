import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/servers/server_information_screen.dart';
import 'package:nirang/features/servers/server_profile_settings_screen.dart';

const _control = MethodChannel('dev.nirang.client/control');
const _events = MethodChannel('dev.nirang.client/events');
const _profile = <String, Object?>{
  'id': 'tls-server',
  'name': 'TLS profile',
  'protocol': 'VLESS',
  'transport': 'WebSocket',
  'security': 'TLS',
  'port': 443,
  'sni': 'origin.example.com',
  'fingerprint': 'chrome',
  'echConfigList': 'https://resolver.example/ech',
  'echOutbound': '{"tag":"ech","protocol":"freedom"}',
  'profileEditable': true,
};

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppStrings.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.5)),
      child: child!,
    ),
    home: home,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  for (final keyboard in [false, true]) {
    testWidgets(
      'Save stays above ${keyboard ? 'keyboard' : 'three-button navigation'} with large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        tester.view.viewPadding = const FakeViewPadding(bottom: 76);
        tester.view.padding = FakeViewPadding(bottom: keyboard ? 0 : 76);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard ? 280 : 0);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            ServerProfileSettingsScreen(server: ServerInfo.fromMap(_profile)),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('save-server-profile'));
        final rect = tester.getRect(save);
        expect(save.hitTestable(), findsOneWidget);
        expect(rect.bottom, lessThanOrEqualTo(keyboard ? 504 : 708));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'edited multiline ECH outbound reaches native storage with exact formatting',
    (tester) async {
      const edited =
          '\n{\n  "tag": "ech",\n  "protocol": "freedom",\n  "settings": {}\n}\n  ';
      Map<dynamic, dynamic>? submitted;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_control, (
        call,
      ) async {
        if (call.method == 'initialize') {
          return {
            'servers': [_profile],
          };
        }
        if (call.method == 'updateServerProfile') {
          submitted = (call.arguments as Map)['values'] as Map;
          return [
            {..._profile, 'echOutbound': submitted!['echOutbound']},
          ];
        }
        throw StateError('Unexpected native call ${call.method}');
      });
      await tester.pumpWidget(
        _app(ServerInformationScreen(server: ServerInfo.fromMap(_profile))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-server-profile')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('profile-echOutbound'));
      await tester.enterText(field, edited);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller!.text, edited);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-server-profile')));
      await tester.pumpAndSettle();
      expect(submitted, {'echOutbound': edited});
      expect(tester.takeException(), isNull);
    },
  );
}
