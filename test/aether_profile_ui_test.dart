import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/theme/app_scroll_behavior.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/country_flag_badge.dart';
import 'package:nirang/features/servers/aether_profile_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: true));
}

Future<void> _mount(
  WidgetTester tester, {
  ServerInfo? server,
  bool persian = false,
  double bottomPadding = 0,
  double keyboardInset = 0,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(_Controller.new)],
      child: MaterialApp(
        scrollBehavior: const NirangScrollBehavior(reducedEffects: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(
              bottom: keyboardInset > 0 ? 0 : bottomPadding,
            ),
            viewPadding: EdgeInsets.only(bottom: bottomPadding),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        theme: AppTheme.dark,
        locale: Locale(persian ? 'fa' : 'en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AetherProfileScreen(server: server),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    key == 'aether-mode' ? -180 : 180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final rect = tester.getRect(find.byKey(ValueKey(key)));
  if (rect.top < 70 && !key.contains('save') && !key.contains('prepare')) {
    await tester.drag(find.byType(Scrollable).first, Offset(0, 85 - rect.top));
    await tester.pumpAndSettle();
  }
}

void main() {
  const channel = MethodChannel('dev.nirang.client/control');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getAetherProfile') {
            return {
              'id': 'sub',
              'name': 'Managed Aether',
              'values': {
                'mode': 'masque',
                'psiphon': 'chain',
                'scan': 'stealth',
              },
            };
          }
          if (call.method == 'saveAetherProfile') return [];
          if (call.method == 'renewAetherIdentity') {
            return {'state': 'prepared'};
          }
          if (call.method == 'scanAetherDraft') {
            return {
              'state': 'ready',
              'scan': {'endpoint': '162.159.199.65:443'},
            };
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'changing mode restores its own endpoint and saves bounded history',
    (tester) async {
      await _mount(tester);
      await _reveal(tester, 'aether-endpoint');
      await tester.enterText(
        find.byKey(const ValueKey('aether-endpoint')),
        '162.159.199.65:443',
      );
      await _reveal(tester, 'aether-mode');
      await tester.tap(find.byKey(const ValueKey('aether-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WireGuard (WARP)'));
      await tester.pumpAndSettle();
      await _reveal(tester, 'aether-endpoint');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('aether-endpoint')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const ValueKey('aether-endpoint')),
        '188.114.96.1:2408',
      );
      await _reveal(tester, 'aether-mode');
      await tester.tap(find.byKey(const ValueKey('aether-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MASQUE (Aether)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('aether-save')));
      await tester.pumpAndSettle();
      final values =
          (calls.singleWhere((c) => c.method == 'saveAetherProfile').arguments
                  as Map)['values']
              as Map;
      expect(values['endpoint'], '162.159.199.65:443');
      expect(
        ((values['endpointHistory'] as Map)['wireguard'] as Map)['endpoint'],
        '188.114.96.1:2408',
      );
    },
  );

  testWidgets('region picker retains released drag and selects last country', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true);
    await tester.tap(find.byKey(const ValueKey('aether-psiphon')));
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-psiphonRegion');
    final formScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final formOffset = formScroll.position.pixels;
    await tester.tap(find.byKey(const ValueKey('aether-psiphonRegion')));
    await tester.pumpAndSettle();
    final dialog = find.byType(NirangAlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(CountryFlagBadge)),
      findsWidgets,
    );
    final countries = tester.widget<ListView>(
      find.descendant(of: dialog, matching: find.byType(ListView)),
    );
    expect(countries.physics, isA<BouncingScrollPhysics>());
    for (var i = 0; i < 12; i++) {
      await tester.dragFrom(tester.getCenter(dialog), const Offset(0, -380));
      // Settling after pointer release catches the old snap-back to the top.
      await tester.pumpAndSettle();
    }
    expect(find.text('South Africa').hitTestable(), findsOneWidget);
    expect(formScroll.position.pixels, formOffset);
    await tester.tap(find.text('South Africa'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('aether-psiphonRegion')),
        matching: find.text('South Africa'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final keyboard in [0.0, 240.0]) {
    testWidgets('compact RTL Save clears navigation/keyboard inset $keyboard', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(
        tester,
        persian: true,
        bottomPadding: 48,
        keyboardInset: keyboard,
      );
      await _reveal(tester, 'aether-save');
      // Scroll to the true end, so an accidental clipped button cannot pass.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('aether-save'));
      final usableBottom = 640 - (keyboard > 0 ? keyboard : 48);
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(usableBottom - 12));
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('five modes are available and draft scan fills an unsaved form', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('aether-mode')));
    await tester.pumpAndSettle();
    for (final label in [
      'MASQUE (Aether)',
      'WireGuard (WARP)',
      'WireGuard over MASQUE',
      'WARP-in-WARP',
      'MASQUE-in-MASQUE',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    Navigator.of(tester.element(find.byType(NirangAlertDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aether-prepare')));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'scanAetherDraft'), hasLength(1));
    expect(calls.where((c) => c.method == 'saveAetherProfile'), isEmpty);
    await _reveal(tester, 'aether-endpoint');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('aether-endpoint')))
          .controller!
          .text,
      '162.159.199.65:443',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact RTL endpoint help wraps fully at larger text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true, textScale: 1.3);
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-endpoint');
    final help = find.text(
      'برای انتخاب خودکار خالی بگذار. اسکن، فرم را پر می‌کند؛ ذخیره تغییرات را اعمال می‌کند.',
    );
    expect(help, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(help);
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: paragraph.text.toPlainText().length,
      ),
    );
    expect(boxes.map((box) => box.top).toSet().length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Persian editor expands with no layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true);
    expect(
      Directionality.of(tester.element(find.byType(AetherProfileScreen))),
      TextDirection.rtl,
    );
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-endpoint');
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft scan is visible and host endpoints are rejected', (
    tester,
  ) async {
    await _mount(tester);
    expect(find.byKey(const ValueKey('aether-prepare')), findsOneWidget);
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-endpoint');
    await tester.enterText(
      find.byKey(const ValueKey('aether-endpoint')),
      'example.com:443',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('aether-save')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('aether-save')));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'saveAetherProfile'), isEmpty);
    expect(find.text('Enter an IP:port or [IPv6]:port.'), findsOneWidget);
  });

  testWidgets('editor header uses settings frosted transparency', (
    tester,
  ) async {
    await _mount(tester);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBodyBehindAppBar, isTrue);
    final appbar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appbar.backgroundColor, Colors.transparent);
    final frost = appbar.flexibleSpace! as FrostedSurface;
    expect(frost.sigma, 8);
    expect(frost.tintAlpha, .45);
  });

  testWidgets(
    'key renewal requires explicit confirmation and calls native once',
    (tester) async {
      const server = ServerInfo(
        id: 'local',
        name: 'Local',
        country: '',
        protocol: 'AETHER',
        transport: '',
        security: '',
        port: 0,
        selected: false,
        status: 'idle',
        profileKind: 'aether',
        origin: 'local',
      );
      await _mount(tester, server: server);
      await tester.pumpAndSettle();
      await _reveal(tester, 'aether-renew');
      await tester.tap(find.byKey(const ValueKey('aether-renew')));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.method == 'renewAetherIdentity'),
        isEmpty,
      );
      expect(
        find.textContaining('Other profiles using this mode share'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.method == 'renewAetherIdentity'),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('aether-renew')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renew'));
      await tester.pumpAndSettle();
      final renew = calls.singleWhere(
        (call) => call.method == 'renewAetherIdentity',
      );
      expect((renew.arguments as Map)['id'], 'local');
      expect(find.text('Connection identity renewed.'), findsOneWidget);
    },
  );

  testWidgets('subscription preset is read-only until explicit local copy', (
    tester,
  ) async {
    const server = ServerInfo(
      id: 'sub',
      name: 'Managed Aether',
      country: '',
      protocol: 'AETHER',
      transport: '',
      security: '',
      port: 0,
      selected: false,
      status: 'idle',
      profileKind: 'aether',
    );
    await _mount(tester, server: server);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('aether-name')))
          .enabled,
      isFalse,
    );
    expect(find.byKey(const ValueKey('aether-save')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('aether-create-copy')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('aether-name')))
          .enabled,
      isTrue,
    );
    await _reveal(tester, 'aether-save');
    await tester.tap(find.byKey(const ValueKey('aether-save')));
    await tester.pumpAndSettle();
    final saved = calls.singleWhere(
      (call) => call.method == 'saveAetherProfile',
    );
    expect((saved.arguments as Map)['id'], isNull);
    expect(((saved.arguments as Map)['values'] as Map)['scan'], 'stealth');
  });

  testWidgets('leaving during key renewal cancels its native preparation', (
    tester,
  ) async {
    final renewal = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getAetherProfile') {
            return {'name': 'Local', 'values': {}};
          }
          if (call.method == 'renewAetherIdentity') return renewal.future;
          if (call.method == 'cancelAetherPreparation') return true;
          return null;
        });
    const server = ServerInfo(
      id: 'local',
      name: 'Local',
      country: '',
      protocol: 'AETHER',
      transport: '',
      security: '',
      port: 0,
      selected: false,
      status: 'idle',
      profileKind: 'aether',
      origin: 'local',
    );
    await _mount(tester, server: server);
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-renew');
    await tester.tap(find.byKey(const ValueKey('aether-renew')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renew'));
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'renewAetherIdentity'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'cancelAetherPreparation'),
      hasLength(1),
    );
    renewal.complete({'state': 'prepared'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving an active preparation requests cancellation', (
    tester,
  ) async {
    final preparation = Completer<Map<String, Object?>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getAetherProfile') {
            return {'name': 'Local', 'values': {}};
          }
          if (call.method == 'scanAetherDraft') return preparation.future;
          if (call.method == 'cancelAetherPreparation') return true;
          return null;
        });
    const server = ServerInfo(
      id: 'local',
      name: 'Local',
      country: '',
      protocol: 'AETHER',
      transport: '',
      security: '',
      port: 0,
      selected: false,
      status: 'idle',
      profileKind: 'aether',
      origin: 'local',
    );
    await _mount(tester, server: server);
    await _reveal(tester, 'aether-prepare');
    await tester.tap(find.byKey(const ValueKey('aether-prepare')));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'cancelAetherPreparation'),
      hasLength(1),
    );
    preparation.complete({'state': 'prepared'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final endpoint in ['', '203.0.113.10:443']) {
    testWidgets('path action describes saved endpoint pin: $endpoint', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getAetherProfile') {
              return {
                'name': 'Local',
                'values': {'endpoint': endpoint},
              };
            }
            return null;
          });
      const server = ServerInfo(
        id: 'local',
        name: 'Local',
        country: '',
        protocol: 'AETHER',
        transport: '',
        security: '',
        port: 0,
        selected: false,
        status: 'idle',
        profileKind: 'aether',
        origin: 'local',
      );
      await _mount(tester, server: server);
      await _reveal(tester, 'aether-prepare');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('aether-prepare')),
          matching: find.text('Scan IP'),
        ),
        findsOneWidget,
      );
    });
  }
}
