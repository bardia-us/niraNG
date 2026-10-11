import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/header_excluded_control.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/main.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: const NativeSettings(
      performanceMode: true,
      performanceModePrompted: true,
      feedbackMode: 'off',
    ),
    servers: [
      for (var i = 0; i < 30; i++)
        ServerInfo(
          id: 's$i',
          name: 'Server $i',
          country: 'DE',
          protocol: 'VLESS',
          transport: 'TCP',
          security: 'TLS',
          port: 443,
          selected: i == 0,
          status: 'idle',
        ),
    ],
  );

  void performance(bool enabled) => state = AsyncData(
    AppSnapshot(settings: NativeSettings(performanceMode: enabled)),
  );
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  testWidgets(
    'performance pages, scroll and open menus never reintroduce optical passes',
    (tester) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      void expectMatte() {
        expect(
          find.byType(glass.AdaptiveGlass, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(glass.GlassButton, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(glass.GlassMenu, skipOffstage: false), findsNothing);
        expect(find.byType(BackdropFilter, skipOffstage: false), findsNothing);
        expect(find.byType(ImageFiltered, skipOffstage: false), findsNothing);
        expect(
          find.byType(HeaderExcludedControl, skipOffstage: false),
          findsNothing,
        );
      }

      expectMatte();
      await tester.tap(find.text('Servers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expectMatte();
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, greaterThan(0));
      expect(pageView.controller!.page, lessThan(1));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Server 3'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expectMatte();
      final actions = find.byTooltip('Server actions').hitTestable().first;
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      final offset = list.scrollController!.offset;
      await tester.drag(actions, const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(list.scrollController!.offset, offset);
      await tester.drag(actions, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(pageView.controller!.page, 1);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      expect(find.text('Server information'), findsOneWidget);
      expect(MenuActivity.isOpen.value, isTrue);
      expectMatte();
      await tester.tapAt(const Offset(8, 120));
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isFalse);
      await tester.tap(find.byTooltip('Server page actions'));
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsOneWidget);
      expectMatte();
      await tester.tapAt(const Offset(8, 120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expectMatte();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('matte connect has a visible outline in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: LiquidConnectButton(
                label: 'Connect',
                icon: const Icon(Icons.play_arrow),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      final side = button.style!.side?.resolve({});
      expect(side, isNotNull);
      expect(side!.style, BorderStyle.solid);
      expect(side.width, greaterThanOrEqualTo(1));
      expect(side.color.a, greaterThan(.15));
      expect(tester.getSize(find.byType(LiquidConnectButton)).height, 46);
    });
    for (final ready in [false, true]) {
      testWidgets(
        'matte surfaces omit all filters ($brightness, ready=$ready)',
        (tester) async {
          liveGlassReadyListenable.value = ready;
          var taps = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [appControllerProvider.overrideWith(_Controller.new)],
              child: MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                  body: Column(
                    children: [
                      GlassSurface(
                        radius: 24,
                        padding: const EdgeInsets.all(12),
                        child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('Card'),
                        ),
                      ),
                      const FrostedSurface(child: Text('Toolbar')),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(glass.AdaptiveGlass), findsNothing);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(ImageFiltered), findsNothing);
          final surfaces = tester.widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(FrostedSurface),
              matching: find.byType(ColoredBox),
            ),
          );
          expect(surfaces, hasLength(2));
          expect(surfaces.every((surface) => surface.color.a == 1), isTrue);
          await tester.tap(find.text('Card'));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'matte controls stay circular and usable; normal mode restores glass',
    (tester) async {
      liveGlassReadyListenable.value = true;
      final controller = _Controller();
      var menuTaps = 0;
      var connects = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 44,
                    height: 40,
                    child: LiquidActionMenu<int>(
                      serverActions: true,
                      tooltip: 'Actions',
                      fallback: IconButton(
                        tooltip: 'Actions',
                        onPressed: () => menuTaps++,
                        icon: const Icon(Icons.more_vert),
                      ),
                      items: const [
                        LiquidActionItem(
                          value: 1,
                          label: 'Action',
                          icon: Icons.copy,
                        ),
                      ],
                      onSelected: (_) {},
                    ),
                  ),
                  LiquidConnectButton(
                    label: 'Connect',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => connects++,
                  ),
                  const LiquidConnectButton(
                    label: 'Busy',
                    icon: Icon(Icons.stop),
                    onPressed: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(glass.GlassMenu), findsNothing);
      expect(find.byType(glass.GlassButton), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final circle = find.byWidgetPredicate(
        (w) => w is Material && w.shape is CircleBorder,
      );
      expect(circle, findsOneWidget);
      expect(tester.getSize(circle), const Size(40, 40));
      final connect = find.byType(LiquidConnectButton).first;
      expect(tester.getSize(connect).height, 46);
      await tester.tap(find.byTooltip('Actions'));
      await tester.tap(find.text('Connect'));
      await tester.tap(find.text('Busy'));
      expect(menuTaps, 1);
      expect(connects, 1);
      controller.performance(false);
      await tester.pumpAndSettle();
      expect(find.byType(glass.GlassMenu), findsOneWidget);
      expect(find.byType(glass.GlassButton), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
