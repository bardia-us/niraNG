import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/formatters.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/choice_dialog_options.dart';
import 'package:nirang/core/widgets/clay_surface.dart';
import 'package:nirang/core/widgets/status_toast.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/server_name_text.dart';
import 'package:nirang/core/widgets/country_flag_badge.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/app_shell.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    settings: NativeSettings(
      performanceMode: false,
      performanceModePrompted: true,
      feedbackMode: 'off',
    ),
  );
}

Widget mount(Widget child, {ThemeData? theme}) => ProviderScope(
  overrides: [appControllerProvider.overrideWith(_Controller.new)],
  child: MaterialApp(
    theme: theme ?? AppTheme.dark,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  ),
);

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  testWidgets('light dock transmits backdrop without changing its capsule', (
    tester,
  ) async {
    await tester.pumpWidget(mount(const AppShell(), theme: AppTheme.light));
    await tester.pumpAndSettle();
    final dock = find
        .ancestor(
          of: find.byType(NavigationBar),
          matching: find.byType(FrostedSurface),
        )
        .first;
    final surface = tester.widget<FrostedSurface>(dock);
    final tint = tester
        .widget<ColoredBox>(
          find.descendant(of: dock, matching: find.byType(ColoredBox)).first,
        )
        .color;
    expect(tint.a, lessThan(.7));
    expect(
      find.descendant(of: dock, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(surface.radius, 36);
    expect(tester.takeException(), isNull);
  });
  for (final direction in TextDirection.values) {
    testWidgets('dialog option press follows rounded shape ($direction)', (
      tester,
    ) async {
      var selected = '';
      await tester.pumpWidget(
        mount(
          Directionality(
            textDirection: direction,
            child: NirangAlertDialog(
              title: const Text('Local network'),
              scrollContent: false,
              content: ChoiceDialogOptions(
                values: const {'auto': 'Automatic', 'bypass': 'Bypass proxy'},
                current: 'auto',
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'Bypass proxy');
      final ink = tester.widget<InkWell>(
        find.descendant(of: tile, matching: find.byType(InkWell)),
      );
      expect(ink.customBorder, isA<RoundedRectangleBorder>());
      final shape = ink.customBorder!;
      final rect = Offset.zero & tester.getSize(tile);
      expect(
        shape.getOuterPath(rect).contains(const Offset(1, 1)),
        isFalse,
        reason: 'Press feedback must exclude the square row corners',
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(selected, 'bypass');
    });
  }
  testWidgets('header menu stays open while parent rebuilds', (tester) async {
    liveGlassReadyListenable.value = true;
    var selected = false;
    await tester.pumpWidget(
      mount(
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: MenuActivity.isOpen,
            builder: (context, open, _) => Center(
              child: GlassSurface(
                child: LiquidActionMenu<int>(
                  tooltip: 'Header actions',
                  items: const [
                    LiquidActionItem(
                      value: 1,
                      label: 'Keep menu open',
                      icon: Icons.refresh,
                    ),
                  ],
                  onSelected: (_) => selected = true,
                  fallback: const Icon(Icons.menu),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(LiquidActionMenu<int>));
    await tester.tap(find.byTooltip('Header actions'));
    await tester.pumpAndSettle();
    expect(MenuActivity.isOpen.value, isTrue);
    expect(tester.state(find.byType(LiquidActionMenu<int>)), same(state));
    expect(find.text('Keep menu open'), findsOneWidget);
    await tester.tap(find.text('Keep menu open'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(MenuActivity.isOpen.value, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test(
    'country flag moves to its dedicated slot even in the middle or end',
    () {
      expect(displayServerName('Edge 🇩🇪 Fast'), 'Edge Fast');
      expect(displayServerName('پروفایل 🇸🇪'), 'پروفایل');
      expect(displayServerName('🇳🇱 - Server'), 'Server');
      expect(displayServerName('No flag'), 'No flag');
      // Only the primary flag moves; a second flag must not disappear.
      expect(displayServerName('Edge 🇩🇪 / 🇸🇪'), 'Edge / 🇸🇪');
    },
  );

  testWidgets(
    'nested surfaces retain their original independent glass material',
    (tester) async {
      await tester.pumpWidget(
        mount(
          const Scaffold(
            body: Center(
              child: GlassSurface(
                child: SizedBox(
                  width: 250,
                  height: 150,
                  child: GlassSurface(child: Text('Inner')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      expect(find.text('Inner'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'secondary country flags use image badges without duplicating the primary flag',
    (tester) async {
      await tester.pumpWidget(
        mount(
          const Scaffold(
            body: SizedBox(
              width: 200,
              child: ServerNameText('Edge 🇩🇪 / 🇸🇪 🇫🇷'),
            ),
          ),
        ),
      );
      final badges = tester
          .widgetList<CountryFlagBadge>(find.byType(CountryFlagBadge))
          .map((badge) => badge.countryCode);
      expect(badges, ['SE', 'FR']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested connect retains its own optical layer and stays tappable',
    (tester) async {
      liveGlassReadyListenable.value = true;
      var taps = 0;
      await tester.pumpWidget(
        mount(
          Scaffold(
            body: Center(
              child: GlassSurface(
                child: LiquidConnectButton(
                  label: 'Connect',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<glass.GlassButton>(
        find.byType(glass.GlassButton),
      );
      expect(
        button.settings!.frost,
        0,
        reason: 'Approved Clear Lens refracts without the old frosted cloud',
      );
      expect(button.useOwnLayer, isTrue);
      expect(button.stretch, greaterThan(0));
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    },
  );

  testWidgets('opening a popup does not flatten the original underlay glass', (
    tester,
  ) async {
    await tester.pumpWidget(
      mount(
        const Scaffold(
          body: Column(
            children: [
              GlassSurface(child: Text('Behind')),
              GlassSurface(child: Text('Menu')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Behind'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'navigation stays floating over the page instead of a separate dark surround',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 28);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(mount(const AppShell()));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(NavigationBar));
      expect(rect.left, 16);
      expect(rect.right, 384);
      expect(rect.bottom, 766);
      final shell = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(shell.extendBody, isTrue);
      // Content and background continue behind the floating capsule. Each
      // scrollable reserves its inset at the END, not a black empty viewport.
      expect(tester.getRect(find.byType(PageView)).bottom, 800);
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final tint = tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find
                      .ancestor(
                        of: find.byType(NavigationBar),
                        matching: find.byType(FrostedSurface),
                      )
                      .first,
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;
      expect(
        tint.a,
        lessThan(.5),
        reason: 'Dark dock should transmit its backdrop like the top bar',
      );
      expect(
        nav.overlayColor?.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
      expect(
        nav.overlayColor?.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      final clayDecoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ClayNavigationIcon).first,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(clayDecoration.border, isNull);
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byType(ClayNavigationIcon).first,
              matching: find.byType(Icon),
            )
            .first,
      );
      expect(icon.size, 28);
      final serversIcon = find.byIcon(Icons.dns_outlined);
      final start = tester.getCenter(serversIcon);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(30, -12));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getCenter(serversIcon).dx,
        greaterThan(start.dx),
        reason: 'The icon follows a bounded stretch, not only a tap scale',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(tester.getCenter(serversIcon).dx, closeTo(start.dx, .1));
      await tester.tap(find.text('Servers').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clay confirmation remains readable and dismisses automatically',
    (tester) async {
      await tester.pumpWidget(
        mount(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSuccessToast(context, 'Saved correctly'),
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Saved correctly'), findsOneWidget);
      final raised = find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            ((widget.decoration as BoxDecoration).boxShadow?.length ?? 0) == 2,
      );
      expect(raised, findsWidgets);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Saved correctly'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
