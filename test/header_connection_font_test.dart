import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/home_screen.dart';
import 'package:nirang/main.dart';

class _Controller extends AppController {
  _Controller({this.performance = false, this.firstName = 'Server 0'});
  final bool performance;
  final String firstName;
  int selections = 0;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(
      performanceMode: performance,
      performanceModePrompted: true,
      feedbackMode: 'off',
    ),
    subscriptionConfigured: true,
    servers: [
      for (var i = 0; i < 30; i++)
        ServerInfo(
          id: 's$i',
          name: i == 0 ? firstName : 'Server $i',
          country: 'DE',
          protocol: 'VLESS',
          transport: 'TCP',
          security: 'TLS',
          port: 443,
          status: 'idle',
          selected: i == 0,
        ),
    ],
  );
  @override
  Future<void> selectServer(String id) async => selections++;
  void connected(bool value) {
    state = AsyncData(
      state.requireValue.copyWith(
        connection: ConnectionInfo(
          state: value ? 'connected' : 'disconnected',
          publicIpChecked: true,
        ),
      ),
    );
  }
}

Future<_Controller> _mount(
  WidgetTester tester,
  Widget page, {
  bool performance = false,
  String firstName = 'Server 0',
}) async {
  late _Controller controller;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => controller = _Controller(
            performance: performance,
            firstName: firstName,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: page),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets(
    'compact server remarks fit more name without covering controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(tester, const ServersScreen(), firstName: 'Amsterdam 8');
      final label = tester.renderObject<RenderParagraph>(
        find.text('Amsterdam 8'),
      );
      expect(label.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Home vertical scroll drives the optical motion synchronizer', (
    tester,
  ) async {
    final controller = await _mount(tester, const HomeScreen());
    final list = tester.widget<ListView>(find.byType(ListView));
    final syncFinder = find.ancestor(
      of: find.byType(ListView),
      matching: find.byType(glass.GlassMotionSync),
    );
    expect(syncFinder, findsOneWidget);
    final sync = tester.widget<glass.GlassMotionSync>(syncFinder);
    expect(list.controller, isNotNull);
    var refreshes = 0;
    void observeMotion() => refreshes++;
    sync.motion.addListener(observeMotion);
    addTearDown(() => sync.motion.removeListener(observeMotion));
    list.controller!.jumpTo(12);
    await tester.pump();
    expect(refreshes, greaterThan(0));
    await tester.pumpAndSettle();
    controller.connected(true);
    await tester.pump();
    refreshes = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      refreshes,
      greaterThan(0),
      reason: 'Resizing a card also moves the glass below it',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Restart pushes the card content and next section gradually', (
    tester,
  ) async {
    final controller = await _mount(tester, const HomeScreen());
    final selectedLabel = find.text('SELECTED SERVER');
    final usageLabel = find.text('Subscription usage');
    final start = tester.getTopLeft(selectedLabel).dy;
    final usageStart = tester.getTopLeft(usageLabel).dy;
    controller.connected(true);
    await tester.pump();
    expect(tester.getTopLeft(selectedLabel).dy, closeTo(start, .1));
    await tester.pump(const Duration(milliseconds: 120));
    final middle = tester.getTopLeft(selectedLabel).dy;
    final usageMiddle = tester.getTopLeft(usageLabel).dy;
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(selectedLabel).dy;
    final usageEnd = tester.getTopLeft(usageLabel).dy;
    expect(middle, greaterThan(start));
    expect(middle, lessThan(end));
    expect(usageMiddle, greaterThan(usageStart));
    expect(usageMiddle, lessThan(usageEnd));
    controller.connected(false);
    await tester.pump();
    expect(tester.getTopLeft(selectedLabel).dy, closeTo(end, .1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(selectedLabel).dy, closeTo(start, .1));
  });

  testWidgets('bottom system navigation area has no optical rim or divider', (
    tester,
  ) async {
    // 72 physical pixels at the test view's 3x DPR = 24 logical pixels.
    tester.view.padding = const FakeViewPadding(bottom: 72);
    tester.view.viewPadding = const FakeViewPadding(bottom: 72);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_Controller.new)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    final navGlass = find.ancestor(
      of: find.byType(NavigationBar),
      matching: find.byType(FrostedSurface),
    );
    expect(tester.getBottomLeft(navGlass).dy, closeTo(600, .01));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.systemNavigationBarDividerColor, Colors.transparent);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
  });
  for (final performance in [false, true]) {
    testWidgets(
      'fixed server header blocks the row behind it (performance=$performance)',
      (tester) async {
        final controller = await _mount(
          tester,
          const ServersScreen(),
          performance: performance,
        );
        final scroll = tester
            .widget<ReorderableListView>(find.byType(ReorderableListView))
            .scrollController!;
        final header = find.ancestor(
          of: find.text('Servers (30)'),
          matching: find.byType(GlassSurface),
        );
        final headerCenter = tester.getCenter(header);
        expect(
          find.ancestor(
            of: header,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Listener &&
                  widget.behavior == HitTestBehavior.opaque,
            ),
          ),
          findsOneWidget,
          reason:
              'The input wall must exist even when premium glass has no painted background',
        );
        final rowTitleCenter = tester.getCenter(find.text('Server 0'));
        scroll.jumpTo(rowTitleCenter.dy - headerCenter.dy);
        await tester.pumpAndSettle();
        // The first row's text is geometrically behind the blank middle of the header.
        expect(
          tester.getCenter(find.text('Server 0')).dy,
          closeTo(headerCenter.dy, .01),
        );
        await tester.tapAt(headerCenter);
        await tester.pumpAndSettle();
        expect(
          controller.selections,
          0,
          reason: 'Transparent header gaps must not select a hidden row',
        );
        final before = scroll.offset;
        await tester.dragFrom(headerCenter, const Offset(0, -50));
        await tester.pumpAndSettle();
        expect(
          scroll.offset,
          before,
          reason:
              'A drag starting on the header belongs to the header, not the list',
        );
        await tester.tap(find.byTooltip('Server page actions'));
        await tester.pumpAndSettle();
        expect(find.text('Update now'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'connection panel grows and shrinks without a height jump (performance=$performance)',
      (tester) async {
        final controller = await _mount(
          tester,
          const HomeScreen(),
          performance: performance,
        );
        final panel = find.byType(GlassSurface).first;
        final small = tester.getSize(panel).height;
        controller.connected(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final growing = tester.getSize(panel).height;
        await tester.pumpAndSettle();
        final large = tester.getSize(panel).height;
        expect(growing, greaterThan(small));
        expect(
          growing,
          lessThan(large),
          reason: 'Restart must not teleport the panel to its final height',
        );
        controller.connected(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final shrinking = tester.getSize(panel).height;
        expect(shrinking, greaterThan(small));
        expect(shrinking, lessThan(large));
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, closeTo(small, .01));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('app text remains standard when the device font scale changes', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.75;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_Controller.new)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    final label = tester.element(find.text('Connection status'));
    expect(MediaQuery.textScalerOf(label).scale(16), 16);
    tester.platformDispatcher.textScaleFactorTestValue = .85;
    await tester.pumpAndSettle();
    expect(MediaQuery.textScalerOf(label).scale(16), 16);
    expect(tester.takeException(), isNull);
  });
}
