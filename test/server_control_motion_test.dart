import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/optical_list_controls.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';
import 'package:nirang/core/widgets/optical_row_anchor.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  _Controller(this.performanceMode);
  final bool performanceMode;
  @override
  Future<void> reorderServers(int oldIndex, int requestedNewIndex) async {}
  @override
  Future<void> selectServer(String id) async {}
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(performanceMode: performanceMode),
    servers: [
      for (var i = 0; i < 30; i++)
        ServerInfo(
          id: 's$i',
          name: 'Server $i',
          protocol: 'VLESS',
          transport: 'TCP',
          country: 'DE',
          port: 443,
          security: 'TLS',
          status: 'idle',
          selected: i == 0,
        ),
    ],
  );
}

// Keep the real optimistic reorder/persistence path. Only the native write is
// replaced; a no-op reorder cannot exercise the drop's provider update.
class _ReorderingController extends AppController {
  @override
  Future<AppSnapshot> build() => _Controller(false).build();
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  for (final sameCardSecondPointer in [false, true]) {
    testWidgets(
      'drag proxy owns one raised card unit (second pointer=$sameCardSecondPointer)',
      (tester) async {
        liveGlassReadyListenable.value = true;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(() => _Controller(false)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              localizationsDelegates: const [AppStrings.delegate],
              home: const Scaffold(body: ServersScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final oldMenu = find.descendant(
          of: find.descendant(
            of: find.byType(OpticalListControls),
            matching: find.byKey(const ValueKey('s1')),
          ),
          matching: find.byType(LiquidActionMenu<String>),
        );
        final oldState = tester.state(oldMenu);
        final earlyFinger = sameCardSecondPointer
            ? await tester.startGesture(
                tester.getCenter(find.text('Server 1')),
                pointer: 8,
              )
            : null;
        final finger = await tester.startGesture(
          tester.getCenter(find.text('Server 1')),
          pointer: 1,
        );
        await tester.pump(const Duration(milliseconds: 650));
        await finger.moveBy(const Offset(0, 37));
        await tester.pump(const Duration(milliseconds: 16));
        final proxyRow = find.widgetWithText(ListTile, 'Server 1');
        final proxyMenu = find.descendant(
          of: proxyRow,
          matching: find.byType(LiquidActionMenu<String>),
        );
        expect(
          proxyMenu,
          findsOneWidget,
          reason:
              'A raised card must contain its own control, above other cards AND their controls',
        );
        expect(
          tester.state(proxyMenu),
          same(oldState),
          reason: 'Promotion must not restart the menu state',
        );
        final secondFinger = await tester.startGesture(
          const Offset(12, 20),
          pointer: 9,
        );
        await secondFinger.cancel();
        await tester.pump();
        expect(
          proxyMenu,
          findsOneWidget,
          reason:
              'Canceling another pointer must not demote the active proxy menu',
        );
        expect(tester.state(proxyMenu), same(oldState));
        await earlyFinger?.cancel();
        await tester.pump();
        expect(
          proxyMenu,
          findsOneWidget,
          reason:
              'The latest row pointer owns the reorder, independently of press depth',
        );
        expect(tester.state(proxyMenu), same(oldState));
        expect(tester.takeException(), isNull);
        final otherMenu = find.byKey(const ValueKey('server-menu-s2'));
        final overlap = tester
            .getRect(proxyRow)
            .intersect(tester.getRect(otherMenu));
        expect(
          overlap.isEmpty,
          isFalse,
          reason: 'The probe must actually overlap another row control',
        );
        final hit = tester
            .hitTestOnBinding(overlap.center)
            .path
            .map((entry) => entry.target);
        expect(
          hit,
          contains(tester.renderObject(proxyRow)),
          reason:
              'The held card, not a neighboring menu, must be the frontmost hit',
        );
        await finger.cancel();
        await tester.pumpAndSettle();
        expect(tester.state(oldMenu), same(oldState));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('ordinary card press keeps its menu attached and equally scaled', (
    tester,
  ) async {
    liveGlassReadyListenable.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => _Controller(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: const [AppStrings.delegate],
          home: const Scaffold(body: ServersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.widgetWithText(ListTile, 'Server 1');
    final anchor = find.descendant(
      of: row,
      matching: find.byType(OpticalRowAnchor),
    );
    final menu = find.descendant(
      of: find.descendant(
        of: find.byType(OpticalListControls),
        matching: find.byKey(const ValueKey('s1')),
      ),
      matching: find.byType(LiquidActionMenu<String>),
    );
    double width(Finder finder) =>
        (tester.getTopRight(finder) - tester.getTopLeft(finder)).distance;
    final rowWidth = width(row);
    final menuWidth = width(menu);
    final initialCenter = tester.getCenter(menu);
    final finger = await tester.startGesture(
      tester.getCenter(find.text('Server 1')),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(microseconds: 8333));
      expect(
        (tester.getCenter(menu) - tester.getCenter(anchor)).distance,
        lessThan(.02),
        reason:
            'A short press must move its menu with the card before reorder starts',
      );
      expect(
        width(menu) / menuWidth,
        closeTo(width(row) / rowWidth, .0001),
        reason:
            'The whole menu must share card press depth, not only translation',
      );
    }
    expect(width(menu), lessThan(menuWidth - .5));
    await finger.cancel();
    await tester.pumpAndSettle();
    expect((tester.getCenter(menu) - initialCenter).distance, lessThan(.01));
    expect(width(menu), closeTo(menuWidth, .01));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'cached menu freely paints above adjacent cards in both stretch directions dark=$dark',
      (tester) async {
        liveGlassReadyListenable.value = true;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(() => _Controller(false)),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              localizationsDelegates: const [AppStrings.delegate],
              home: const Scaffold(body: ServersScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final menu = find.descendant(
          of: find.descendant(
            of: find.byType(OpticalListControls),
            matching: find.byKey(const ValueKey('s5')),
          ),
          matching: find.byType(LiquidActionMenu<String>),
        );
        final glyph = find.descendant(
          of: menu,
          matching: find.byIcon(Icons.more_vert_rounded),
        );
        final capture = tester.widget<OpticalBackdropCapture>(
          find.byType(OpticalBackdropCapture),
        );
        final boundary =
            capture.source.key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final card = tester.getRect(find.widgetWithText(ListTile, 'Server 5'));
        final resting = tester.getCenter(glyph);
        for (final direction in [-1.0, 1.0]) {
          final beforeImage = boundary.toImageSync();
          final before = (await tester.runAsync(
            () => beforeImage.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          beforeImage.dispose();
          final fullRegion = Offset.zero & boundary.size;
          capture.source.captureRegion(1, 0, fullRegion);
          final finger = await tester.startGesture(tester.getCenter(menu));
          await tester.pumpAndSettle();
          // Warm the cache after press-scale/layer changes have settled. The next
          // movement alone must invalidate it, without incidental parent paint.
          capture.source.captureRegion(1, 0, fullRegion);
          await finger.moveBy(Offset(0, direction * 160));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          final current = tester.getCenter(glyph);
          expect((current.dy - resting.dy) * direction, greaterThan(10));
          final center = boundary.globalToLocal(current);
          final edge = boundary
              .globalToLocal(Offset(0, direction < 0 ? card.top : card.bottom))
              .dy
              .round();
          final image = boundary.toImageSync();
          final pixels = (await tester.runAsync(
            () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          final captured = capture.source.captureRegion(1, 0, fullRegion)!.$1;
          final cachedPixels = (await tester.runAsync(
            () => captured.toByteData(format: ui.ImageByteFormat.rawRgba),
          ))!;
          var changed = 0;
          for (var distance = 2; distance <= 16; distance++) {
            final y = edge + (direction * distance).toInt();
            for (
              var x = center.dx.round() - 24;
              x <= center.dx.round() + 24;
              x++
            ) {
              final at = (y * image.width + x) * 4;
              for (var channel = 0; channel < 4; channel++) {
                expect(
                  cachedPixels.getUint8(at + channel),
                  pixels.getUint8(at + channel),
                  reason:
                      'Stationary elastic movement must refresh the capture without another scroll or touch',
                );
              }
              if ((pixels.getUint8(at) - before.getUint8(at)).abs() > 4 ||
                  (pixels.getUint8(at + 1) - before.getUint8(at + 1)).abs() >
                      4 ||
                  (pixels.getUint8(at + 2) - before.getUint8(at + 2)).abs() >
                      4) {
                changed++;
              }
            }
          }
          image.dispose();
          expect(
            changed,
            greaterThan(12),
            reason:
                'The cached circle must paint outside its card, not clip or hide below the next card',
          );
          await finger.cancel();
          await tester.pumpAndSettle();
          expect((tester.getCenter(glyph) - resting).distance, lessThan(.01));
        }
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('static menu paint is reused during fractional list scrolling', (
    tester,
  ) async {
    liveGlassReadyListenable.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => _Controller(false)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: const [AppStrings.delegate],
          home: const Scaffold(body: ServersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.descendant(
      of: find.descendant(
        of: find.byType(OpticalListControls),
        matching: find.byKey(const ValueKey('s5')),
      ),
      matching: find.byType(LiquidActionMenu<String>),
    );
    final renderObjects = find
        .descendant(
          of: menu,
          matching: find.byWidgetPredicate((w) => w is RenderObjectWidget),
        )
        .evaluate()
        .whereType<RenderObjectElement>()
        .map((e) => e.renderObject)
        .toSet();
    expect(renderObjects, isNotEmpty);
    final previous = debugOnProfilePaint;
    var paints = 0;
    debugOnProfilePaint = (object) {
      previous?.call(object);
      if (renderObjects.contains(object)) paints++;
    };
    addTearDown(() => debugOnProfilePaint = previous);
    final scroll = tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .scrollController!;
    for (final offset in [1.25, 7.75, 22.5, 40.25, 60.0]) {
      scroll.jumpTo(offset);
      await tester.pump();
    }
    expect(
      paints,
      0,
      reason:
          'Moving a static decorative button must reuse its display list, not paint its subtree again',
    );
    // Positive control: ensure this observes actual paints, not a silent hook.
    await tester.pumpAndSettle();
    final capture = tester.widget<OpticalBackdropCapture>(
      find.byType(OpticalBackdropCapture),
    );
    final sourceBounds =
        Offset.zero &
        tester.getSize(
          find.byWidgetPredicate((w) => w is OpticalBackdropBoundary),
        );
    final oldCapture = capture.source.captureRegion(1, 0, sourceBounds)!.$1;
    paints = 0;
    tester
        .renderObject(
          find
              .ancestor(
                of: menu,
                matching: find.byWidgetPredicate(
                  (w) => w is RepaintBoundary || w is OpticalPaintObserver,
                ),
              )
              .first,
        )
        .markNeedsPaint();
    await tester.pump();
    expect(paints, greaterThan(0));
    expect(
      capture.source.captureRegion(1, 0, sourceBounds)!.$1,
      isNot(same(oldCapture)),
      reason:
          'Independent menu repaint must invalidate the source cache even when list/parent does not repaint',
    );
    debugOnProfilePaint = previous;
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'dragged row menu pixels follow the proxy, not only its hit-test transform',
    (tester) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _Controller(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: const [AppStrings.delegate],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.descendant(
        of: find.byKey(const ValueKey('server-menu-s1')),
        matching: find.byType(LiquidActionMenu<String>),
      );
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Server 1')),
      );
      await tester.pump(const Duration(milliseconds: 650));
      await finger.moveBy(const Offset(0, 37));
      await tester.pump(const Duration(milliseconds: 16));
      final capture = tester.widget<OpticalBackdropCapture>(
        find.byType(OpticalBackdropCapture),
      );
      final boundary =
          capture.source.key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final center = boundary.globalToLocal(tester.getCenter(control));
      final image = boundary.toImageSync(pixelRatio: 1);
      final pixels = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      var brightPixels = 0;
      for (var y = center.dy.round() - 12; y <= center.dy.round() + 12; y++) {
        for (var x = center.dx.round() - 6; x <= center.dx.round() + 6; x++) {
          final at = (y * image.width + x) * 4;
          if (pixels.getUint8(at) > 150 &&
              pixels.getUint8(at + 1) > 150 &&
              pixels.getUint8(at + 2) > 150) {
            brightPixels++;
          }
        }
      }
      image.dispose();
      expect(
        brightPixels,
        greaterThan(12),
        reason:
            'The three white dots must actually repaint at the live dragged-row position; logical getCenter alone is insufficient',
      );
      await finger.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'continuous scroll keeps row and control on the same simulated frame',
    (tester) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _Controller(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .scrollController!;
      final row = find.widgetWithText(ListTile, 'Server 5');
      final control = find.descendant(
        of: find
            .descendant(
              of: find.byType(OpticalListControls),
              matching: find.byKey(const ValueKey('s5')),
            )
            .first,
        matching: find.byType(LiquidActionMenu<String>),
      );
      final initialY = tester.getCenter(row).dy;
      var notifications = 0;
      var movedFrames = 0;
      var maxGap = 0.0;
      var lastOffset = scroll.offset;
      void notified() => notifications++;
      scroll.addListener(notified);
      final movement = scroll.animateTo(
        300,
        duration: const Duration(seconds: 1),
        curve: Curves.linear,
      );
      // 120Hz logical clock, NOT a hardware FPS benchmark.
      for (var i = 0; i < 122; i++) {
        await tester.pump(const Duration(microseconds: 8333));
        if (scroll.offset != lastOffset) movedFrames++;
        lastOffset = scroll.offset;
        final rowY = tester.getCenter(row).dy;
        final controlY = tester.getCenter(control).dy;
        final gap = (rowY - controlY).abs();
        if (gap > maxGap) maxGap = gap;
        expect(rowY, closeTo(initialY - scroll.offset, .01));
        expect(
          gap,
          lessThan(.01),
          reason:
              'A control cannot trail the row by a frame or jump across a batch',
        );
        expect(tester.takeException(), isNull);
      }
      await movement;
      scroll.removeListener(notified);
      expect(movedFrames, greaterThanOrEqualTo(119));
      debugPrint(
        'SCROLL_SYNC_PROBE movedFrames=$movedFrames notifications=$notifications maxRowControlGap=$maxGap; simulated only',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('cross-slot drop retains row lenses and their live anchors', (
    tester,
  ) async {
    const channel = MethodChannel('dev.nirang.client/control');
    var persisted = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'reorderServers') return null;
      final ids = (call.arguments as Map)['ids'] as List;
      persisted = true;
      return [
        for (final id in ids)
          {
            'id': id,
            'name': 'Server ${id.toString().substring(1)}',
            'protocol': 'VLESS',
            'transport': 'TCP',
            'security': 'TLS',
            'country': 'DE',
            'port': 443,
            'selected': id == 's0',
            'status': 'idle',
          },
      ];
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    liveGlassReadyListenable.value = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(_ReorderingController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: ServersScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder menu(String id) => find.descendant(
      of: find.byKey(ValueKey('server-menu-$id')),
      matching: find.byType(LiquidActionMenu<String>),
    );
    final originalStates = {
      for (final id in ['s0', 's1', 's2', 's3', 's4'])
        id: tester.state(menu(id)),
    };
    final finger = await tester.startGesture(
      tester.getCenter(find.text('Server 1')),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await finger.moveBy(const Offset(0, 1));
    await tester.pump(const Duration(milliseconds: 16));
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.scrollController!.jumpTo(650);
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      menu('s1'),
      findsOneWidget,
      reason:
          'Scrolling the original slot away must not dispose the proxy lens',
    );
    expect(tester.state(menu('s1')), same(originalStates['s1']));
    expect(
      find
          .descendant(
            of: find.byType(OpticalListControls),
            matching: find.byType(LiquidActionMenu<String>),
          )
          .evaluate()
          .length,
      lessThan(20),
      reason:
          'Retaining one dragged lens must not activate every offscreen lens',
    );
    list.scrollController!.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    // Offscreen, non-dragged controls are intentionally virtualized. The held
    // lens is the one that must survive the excursion; compare the others from
    // their remount onward through the actual drop/provider update.
    for (final id in ['s0', 's2', 's3', 's4']) {
      originalStates[id] = tester.state(menu(id));
    }
    await finger.moveBy(const Offset(0, 189));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      menu('s1'),
      findsOneWidget,
      reason: 'The dragged row must keep its original shared lens visible',
    );
    expect(tester.state(menu('s1')), same(originalStates['s1']));
    expect(
      find.ancestor(
        of: find.text('Server 1'),
        matching: find.byType(OpticalBackdropBoundary),
      ),
      findsOneWidget,
      reason:
          'The proxy belongs in the captured list, not the root route overlay',
    );
    await finger.up();
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final id in ['s0', 's1', 's2', 's3', 's4']) {
        expect(tester.state(menu(id)), same(originalStates[id]));
        final anchor = find.descendant(
          of: find.widgetWithText(ListTile, 'Server ${id.substring(1)}'),
          matching: find.byType(OpticalRowAnchor),
        );
        expect(
          (tester.getCenter(menu(id)) - tester.getCenter(anchor)).distance,
          lessThan(.02),
          reason:
              '$id must stay aligned during native order update, frame $frame',
        );
      }
    }
    expect(persisted, isTrue);
    expect(tester.state(menu('s1')), same(originalStates['s1']));
    final listContext = tester.element(find.byType(ServersScreen));
    final app = ProviderScope.containerOf(
      listContext,
    ).read(appControllerProvider).requireValue;
    expect(app.servers.take(5).map((server) => server.id), [
      's0',
      's2',
      's3',
      's4',
      's1',
    ]);
    expect(tester.takeException(), isNull);
  });
  for (final cancel in [true, false]) {
    testWidgets('row reorder restores optics after cancel=$cancel', (
      tester,
    ) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _Controller(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalStage = tester.element(find.byType(OpticalListControls));
      final originalFirstMenu = tester.state(
        find
            .descendant(
              of: find.byType(OpticalListControls),
              matching: find.byType(LiquidActionMenu<String>),
            )
            .first,
      );
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Server 1')),
      );
      await tester.pump(const Duration(milliseconds: 650));
      await finger.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(
        tester.element(find.byType(OpticalListControls)),
        same(originalStage),
        reason:
            'Reordering must retain the shared pass instead of mounting per-row optics',
      );
      expect(
        tester.state(
          find
              .descendant(
                of: find.byType(OpticalListControls),
                matching: find.byType(LiquidActionMenu<String>),
              )
              .first,
        ),
        same(originalFirstMenu),
      );
      final header = find.byWidgetPredicate(
        (w) => w is glass.GlassButton && w.label == 'Server page actions',
      );
      final capture = tester.widget<OpticalBackdropCapture>(
        find.ancestor(
          of: header,
          matching: find.byType(OpticalBackdropCapture),
        ),
      );
      expect(
        capture.source.key.currentContext,
        isNotNull,
        reason:
            'A dragged row must not leave the header sampling a removed stage',
      );
      final retainedTrigger = find.descendant(
        of: find.byKey(const ValueKey('server-menu-s1')),
        matching: find.byWidgetPredicate(
          (w) => w is glass.GlassButton && w.label == 'Server actions',
        ),
      );
      expect(
        retainedTrigger,
        findsOneWidget,
        reason: 'The proxy must keep its original shared row lens visible',
      );
      expect(tester.getSize(retainedTrigger), const Size(44, 44));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final row2 = find.widgetWithText(ListTile, 'Server 2');
        final anchor = find.descendant(
          of: row2,
          matching: find.byType(OpticalRowAnchor),
        );
        final control = find.descendant(
          of: find.descendant(
            of: find.byType(OpticalListControls),
            matching: find.byKey(const ValueKey('s2')),
          ),
          matching: find.byType(LiquidActionMenu<String>),
        );
        expect(
          (tester.getCenter(control) - tester.getCenter(anchor)).distance,
          lessThan(.01),
          reason:
              'Gap animation and lens must agree before paint, without a Flow-frame delay',
        );
      }
      final shiftedControl = find.descendant(
        of: find.descendant(
          of: find.byType(OpticalListControls),
          matching: find.byKey(const ValueKey('s2')),
        ),
        matching: find.byType(LiquidActionMenu<String>),
      );
      await tester.tapAt(tester.getCenter(shiftedControl));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('Select'),
        findsOneWidget,
        reason: 'A shifted lens must remain hittable at its painted position',
      );
      await tester.tapAt(const Offset(2, 20));
      await tester.pump(const Duration(milliseconds: 350));
      if (cancel) {
        await finger.cancel();
      } else {
        await finger.up();
        await tester.pump();
        expect(
          tester.element(find.byType(OpticalListControls)),
          same(originalStage),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(OpticalListControls), findsOneWidget);
      expect(
        tester.element(find.byType(OpticalListControls)),
        same(originalStage),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'scrolling cancels row press deformation while the finger stays down',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _Controller(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ListTile, 'Server 0');
      double paintedWidth() =>
          tester.getTopRight(row).dx - tester.getTopLeft(row).dx;
      final normalWidth = paintedWidth();
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Server 0')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(paintedWidth(), lessThan(normalWidth));
      await finger.moveBy(const Offset(0, -40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        paintedWidth(),
        closeTo(normalWidth, .01),
        reason:
            'Vertical scrolling must not keep the row compressed until finger-up',
      );
      await finger.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final performance in [false, true]) {
    testWidgets(
      'row menu follows scrolling without rebuilding and remains tappable (performance=$performance)',
      (tester) async {
        liveGlassReadyListenable.value = true;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(
                () => _Controller(performance),
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
              home: const Scaffold(body: ServersScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = tester.widget<ReorderableListView>(
          find.byType(ReorderableListView),
        );
        expect(list.scrollController, isNotNull);
        expect(
          list.itemExtent,
          65,
          reason: 'Rows and the optical stage must share layout geometry',
        );
        final trigger = find.byType(LiquidActionMenu<String>).first;
        final originalMenu = tester.widget(trigger);
        final originalCenter = tester.getCenter(trigger);
        if (!performance) {
          final activeMenus = find.descendant(
            of: find.byType(OpticalListControls),
            matching: find.byType(LiquidActionMenu<String>),
          );
          expect(
            activeMenus.evaluate().length,
            lessThan(30),
            reason: 'Only viewport lenses allocate active GPU geometry',
          );
          final row = find.widgetWithText(ListTile, 'Server 0');
          expect(tester.getCenter(trigger).dy, tester.getCenter(row).dy);
          expect(tester.getSize(row).height, 58);
        }
        expect(
          find.byType(OpticalListControls),
          performance ? findsNothing : findsOneWidget,
        );
        // The shared normal-mode stage retains offscreen controls across its
        // 260px layout batches. Performance mode uses ordinary recycled rows;
        // keep its first-row assertions within that row's cache extent.
        final offsets = performance
            ? [0.25, 0.5, 1.25, 40.0, 100.0, 60.0]
            : [
                0.25,
                0.5,
                1.25,
                40.0,
                100.0,
                259.75,
                260.0,
                260.25,
                260.5,
                60.0,
              ];
        for (final offset in offsets) {
          list.scrollController!.jumpTo(offset);
          if (!performance) {
            await tester.pump(Duration.zero, EnginePhase.layout);
            expect(
              tester.getCenter(trigger).dy,
              closeTo(originalCenter.dy - offset, .01),
              reason:
                  'Shared glass must see the new lens transform before paint, not after a previous paint',
            );
          }
          await tester.pump();
          expect(list.scrollController!.offset, offset);
          expect(
            tester.getCenter(trigger).dy,
            closeTo(originalCenter.dy - offset, .01),
          );
          expect(
            tester.widget(trigger),
            same(originalMenu),
            reason:
                'Scroll changes paint coordinates, not the menu widget or gesture state',
          );
          expect(tester.takeException(), isNull);
        }
        // The first row remains mounted beneath the fixed header. Its dots
        // are part of the captured row stage instead of being culled there.
        expect(trigger, findsOneWidget);
        list.scrollController!.jumpTo(0);
        await tester.pumpAndSettle();
        if (!performance) {
          final glyph = find.descendant(
            of: trigger,
            matching: find.byIcon(Icons.more_vert_rounded),
          );
          final restingCenter = tester.getCenter(glyph);
          for (final cancel in [false, true]) {
            final drag = await tester.startGesture(tester.getCenter(trigger));
            await tester.pump(const Duration(milliseconds: 60));
            await drag.moveBy(const Offset(48, 31));
            await tester.pump(const Duration(milliseconds: 120));
            if (cancel) {
              await drag.cancel();
            } else {
              await drag.up();
            }
            await tester.pumpAndSettle();
            expect(
              (tester.getCenter(glyph) - restingCenter).distance,
              lessThan(.01),
              reason:
                  'Release and pointer cancel both restore the glyph before opening its menu',
            );
          }
        }
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(find.text('Server information'), findsOneWidget);
        await tester.tapAt(const Offset(4, 250));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
