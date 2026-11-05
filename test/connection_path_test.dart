import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/country_flag_badge.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/vpn/connection_path_card.dart';

ServerInfo server({
  String mode = 'masque',
  String placement = 'chain',
  String kind = 'aether',
}) => ServerInfo(
  id: 'a',
  name: 'A',
  country: 'DE',
  protocol: 'AETHER',
  transport: '',
  security: '',
  port: 0,
  selected: true,
  status: 'idle',
  profileKind: kind,
  aetherMode: mode,
  psiphonPlacement: placement,
);
void main() {
  test(
    'native progress and route metadata survive parsing and ping updates',
    () {
      final parsed = ServerInfo.fromMap({
        'id': 'a',
        'profileKind': 'aether',
        'aetherMode': 'warp-in-warp',
        'psiphonPlacement': 'reverse',
      }).copyWith(ping: 42);
      expect(parsed.aetherMode, 'warp-in-warp');
      expect(parsed.psiphonPlacement, 'reverse');
      expect(
        ConnectionInfo.fromMap({
          'state': 'preparing',
          'aetherStage': 'registering',
        }).aetherStage,
        'registering',
      );
    },
  );
  for (final fa in [false, true]) {
    testWidgets(
      'compact path expands, ignores stale exit and settles idle fa=$fa',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: fa ? AppTheme.light : AppTheme.dark,
            locale: Locale(fa ? 'fa' : 'en'),
            supportedLocales: const [Locale('en'), Locale('fa')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: SingleChildScrollView(
                child: ConnectionPathCard(
                  server: server(mode: 'wireguard-over-masque'),
                  connection: const ConnectionInfo(
                    state: 'connected',
                    serverId: 'other',
                    publicIp: '203.0.113.2',
                    publicCountry: 'JP',
                    publicIpChecked: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('connection-path-toggle')));
        await tester.pumpAndSettle();
        expect(find.textContaining('203.0.113.2'), findsNothing);
        expect(find.byType(CountryFlagBadge), findsNothing);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }
  testWidgets('only matching successful IP result supplies exit flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionPathCard(
            server: server(),
            connection: const ConnectionInfo(
              state: 'connected',
              serverId: 'a',
              publicIp: '203.0.113.2',
              publicCountry: 'JP',
              publicIpChecked: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CountryFlagBadge>(find.byType(CountryFlagBadge))
          .countryCode,
      'JP',
    );
  });
  test('nested and reverse paths describe real configured order', () {
    expect(connectionPathLabels(server(mode: 'wireguard-over-masque')), [
      'Device',
      'MASQUE',
      'WireGuard',
      'Psiphon',
      'Exit',
    ]);
    expect(
      connectionPathLabels(
        server(mode: 'masque-in-masque', placement: 'reverse'),
      ),
      ['Device', 'Psiphon', 'MASQUE', 'MASQUE', 'Exit'],
    );
    expect(connectionPathLabels(server(placement: 'only')), [
      'Device',
      'Psiphon',
      'Exit',
    ]);
  });
  test('custom JSON does not invent its outbound chain', () {
    expect(connectionPathLabels(server(kind: 'json')), [
      'Device',
      'Custom JSON',
      'Exit',
    ]);
  });
}
