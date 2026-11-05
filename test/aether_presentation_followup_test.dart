import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/country_flag_badge.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/home_screen.dart';

class _Controller extends AppController {
  _Controller(this.snapshot);
  final AppSnapshot snapshot;
  int stops = 0;
  @override
  Future<AppSnapshot> build() async => snapshot;
  @override
  Future<void> disconnect() async {
    stops++;
  }
}

ServerInfo _server(String id, {bool aether = false, String country = 'DE'}) =>
    ServerInfo(
      id: id,
      name: aether ? 'Renamed personal profile' : 'Server $id',
      country: country,
      protocol: aether ? 'AETHER' : 'VLESS',
      transport: 'TCP',
      security: '',
      port: 443,
      selected: true,
      status: 'idle',
      profileKind: aether ? 'aether' : 'uri',
      psiphonEnabled: aether,
    );

Future<void> _mount(
  WidgetTester tester,
  _Controller controller,
  Widget screen, {
  bool persian = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: Locale(persian ? 'fa' : 'en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final persian in [false, true]) {
    testWidgets(
      'Psiphon flag stays physically left of brand after rename (fa=$persian)',
      (tester) async {
        final controller = _Controller(
          AppSnapshot(
            settings: const NativeSettings(performanceMode: true),
            servers: [_server('psiphon', aether: true)],
          ),
        );
        await _mount(
          tester,
          controller,
          const ServersScreen(),
          persian: persian,
        );
        final brand = find.byKey(const ValueKey('aether-brand-psiphon'));
        final flag = find.byType(CountryFlagBadge);
        expect(tester.getCenter(flag).dx, lessThan(tester.getCenter(brand).dx));
        expect(find.text('Renamed personal profile'), findsOneWidget);
      },
    );
  }

  for (final state in [
    'connected',
    'restarting',
    'disconnected',
    'mismatched',
  ]) {
    testWidgets('Home uses only observed matching Psiphon exit ($state)', (
      tester,
    ) async {
      final controller = _Controller(
        AppSnapshot(
          settings: const NativeSettings(performanceMode: true),
          servers: [_server('psiphon', aether: true)],
          connection: ConnectionInfo(
            state: state == 'mismatched' ? 'connected' : state,
            serverId: state == 'mismatched' ? 'another' : 'psiphon',
            publicIp: '203.0.113.2',
            publicCountry: 'JP',
            publicIpChecked: true,
          ),
        ),
      );
      await _mount(tester, controller, const HomeScreen());
      expect(
        tester
            .widget<CountryFlagBadge>(
              find.byKey(const ValueKey('selected-server-country')),
            )
            .countryCode,
        state == 'connected' ? 'JP' : '',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary profile keeps its own flag rather than exit country', (
    tester,
  ) async {
    final controller = _Controller(
      AppSnapshot(
        settings: const NativeSettings(performanceMode: true),
        servers: [_server('normal')],
        connection: const ConnectionInfo(
          state: 'connected',
          serverId: 'normal',
          publicIp: '203.0.113.2',
          publicCountry: 'JP',
          publicIpChecked: true,
        ),
      ),
    );
    await _mount(tester, controller, const HomeScreen());
    expect(
      tester
          .widget<CountryFlagBadge>(
            find.byKey(const ValueKey('selected-server-country')),
          )
          .countryCode,
      'DE',
    );
  });

  testWidgets('Home can cancel a pending Aether restart', (tester) async {
    final controller = _Controller(
      AppSnapshot(
        settings: const NativeSettings(performanceMode: true),
        servers: [_server('psiphon', aether: true)],
        connection: const ConnectionInfo(
          state: 'restarting',
          serverId: 'psiphon',
        ),
      ),
    );
    await _mount(tester, controller, const HomeScreen());
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(controller.stops, 1);
  });

  for (final optical in [false, true]) {
    testWidgets(
      'large group animation keeps mounted rows bounded by viewport (glass=$optical)',
      (tester) async {
        final controller = _Controller(
          AppSnapshot(
            settings: NativeSettings(performanceMode: !optical),
            servers: [for (var i = 0; i < 500; i++) _server('large$i')],
          ),
        );
        liveGlassReadyListenable.value = optical;
        addTearDown(() => liveGlassReadyListenable.value = false);
        await _mount(tester, controller, const ServersScreen());
        final toggle = find.byKey(const ValueKey('server-group-subscription'));
        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 318));
        expect(
          find.byType(ReorderableDelayedDragStartListener).evaluate().length,
          lessThan(35),
        );
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          find.byType(ReorderableDelayedDragStartListener).evaluate().length,
          lessThan(35),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Aether group explains independence without promising service limits away',
    (tester) async {
      final controller = _Controller(
        AppSnapshot(
          settings: const NativeSettings(performanceMode: true),
          servers: [_server('psiphon', aether: true)],
        ),
      );
      await _mount(tester, controller, const ServersScreen());
      await tester.tap(find.byKey(const ValueKey('aether-group-info')));
      await tester.pumpAndSettle();
      expect(find.textContaining('subscription quota'), findsOneWidget);
      expect(find.textContaining('network'), findsWidgets);
    },
  );
}
