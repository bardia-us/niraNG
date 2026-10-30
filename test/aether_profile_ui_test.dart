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
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
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
          if (call.method == 'prepareAetherProfile') {
            return {'state': 'prepared'};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
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

  testWidgets('Advanced expands progressively', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true, textScale: 1.3);
    await _reveal(tester, 'aether-advanced');
    final header = find.byKey(const ValueKey('aether-advanced'));
    final collapsedHeight = tester
        .getSize(
          find
              .ancestor(of: header, matching: find.byType(FrostedSurface))
              .first,
        )
        .height;
    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final partialHeight = tester
        .getSize(
          find
              .ancestor(of: header, matching: find.byType(FrostedSurface))
              .first,
        )
        .height;
    await tester.pumpAndSettle();
    final expandedHeight = tester
        .getSize(
          find
              .ancestor(of: header, matching: find.byType(FrostedSurface))
              .first,
        )
        .height;
    expect(partialHeight, greaterThan(collapsedHeight));
    expect(partialHeight, lessThan(expandedHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact RTL endpoint help wraps fully at larger text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true, textScale: 1.3);
    await _reveal(tester, 'aether-advanced');
    await tester.tap(find.byKey(const ValueKey('aether-advanced')));
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-endpoint');
    final help = find.text('برای جست‌وجوی خودکار IP، آدرس رو پاک و ذخیره کن.');
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
    await _reveal(tester, 'aether-advanced');
    await tester.tap(find.byKey(const ValueKey('aether-advanced')));
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-endpoint');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new profile keeps advanced settings collapsed and rejects host endpoints',
    (tester) async {
      await _mount(tester);
      expect(find.byKey(const ValueKey('aether-scan')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('aether-advanced')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('aether-scan')), findsOneWidget);
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
      expect(
        calls.where((call) => call.method == 'saveAetherProfile'),
        isEmpty,
      );
      expect(find.text('Enter an IP:port or [IPv6]:port.'), findsOneWidget);
    },
  );

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
      await tester.tap(find.byKey(const ValueKey('aether-advanced')));
      await tester.pumpAndSettle();
      await _reveal(tester, 'aether-renew-identity');
      await tester.tap(find.byKey(const ValueKey('aether-renew-identity')));
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
      await tester.tap(find.byKey(const ValueKey('aether-renew-identity')));
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

  testWidgets('unsaved manual endpoint cannot test an old saved address', (
    tester,
  ) async {
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
    await tester.tap(find.byKey(const ValueKey('aether-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('aether-endpoint')),
      '203.0.113.10:443',
    );
    await tester.pump();
    await _reveal(tester, 'aether-prepare');
    final prepare = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('aether-prepare')),
    );
    expect(prepare.onPressed, isNull);
    expect(
      calls.where((call) => call.method == 'prepareAetherProfile'),
      isEmpty,
    );
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
    await tester.tap(find.byKey(const ValueKey('aether-advanced')));
    await tester.pumpAndSettle();
    await _reveal(tester, 'aether-renew-identity');
    await tester.tap(find.byKey(const ValueKey('aether-renew-identity')));
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
          if (call.method == 'prepareAetherProfile') return preparation.future;
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
          matching: find.text(
            endpoint.isEmpty ? 'Find endpoint IP' : 'Prepare / test path',
          ),
        ),
        findsOneWidget,
      );
      if (endpoint.isNotEmpty) {
        expect(
          find.textContaining('Clear the endpoint and save'),
          findsOneWidget,
        );
        expect(find.text('Find a new endpoint IP'), findsNothing);
      }
    });
  }
}
