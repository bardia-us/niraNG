import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:liquid_glass_widgets/src/renderer/glass_backdrop_group_boundary.dart';
import 'package:liquid_glass_widgets/src/renderer/glass_materialize_scope.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_focus_ring_painter.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    settings: NativeSettings(performanceMode: true, feedbackMode: 'off'),
  );
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  Future<void> mountFocusedMenu(
    WidgetTester tester,
    glass.GlassMenuController controller,
    FocusNode focus,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: glass.GlassMenu(
              controller: controller,
              useGlassTriggerFade: true,
              quality: glass.GlassQuality.minimal,
              triggerBuilder: (context, toggle) => glass.GlassIconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: toggle,
                semanticLabel: 'Menu trigger',
                focusNode: focus,
                useOwnLayer: true,
                quality: glass.GlassQuality.minimal,
              ),
              items: [glass.GlassMenuItem(title: 'Action', onTap: () {})],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hidden glass trigger leaves no keyboard focus ring', (
    tester,
  ) async {
    final previous = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = previous);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final controller = glass.GlassMenuController();
    await mountFocusedMenu(tester, controller, focus);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final rings = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is GlassFocusRingPainter,
    );
    expect(rings, findsOneWidget);
    controller.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final ring =
        tester.widget<CustomPaint>(rings).painter! as GlassFocusRingPainter;
    expect(ring.color.a, greaterThan(0));
    expect(ring.color.a, lessThan(1));
    await tester.pumpAndSettle();
    expect(rings, findsNothing);
    controller.close();
    await tester.pumpAndSettle();
    expect(rings, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden glass trigger leaves no accessible duplicate button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final controller = glass.GlassMenuController();
      await mountFocusedMenu(tester, controller, focus);
      expect(find.semantics.byLabel('Menu trigger'), findsOneWidget);
      controller.open();
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Menu trigger'), findsNothing);
      controller.close();
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel('Menu trigger'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'performance mode keeps spring menu and registers overlay until closed',
    (tester) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            home: Scaffold(
              body: glass.GlassBackdropGroup(
                child: Center(
                  child: LiquidActionMenu<int>(
                    tooltip: 'Actions',
                    fallback: const Text('Fallback'),
                    onSelected: (_) {},
                    items: const [
                      LiquidActionItem(
                        value: 1,
                        label: 'Action',
                        icon: Icons.copy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(glass.GlassMenu), findsOneWidget);
      expect(
        tester
            .widget<glass.GlassIconButton>(find.byType(glass.GlassIconButton))
            .useOwnLayer,
        isTrue,
      );
      // Actual app trigger path must not put its optical layer under an
      // Opacity/save-layer boundary that opts it out of shared backdrop reads.
      expect(
        enclosingBackdropGroup(
          tester.renderObject(find.byType(glass.GlassIconButton)),
        ),
        isNotNull,
      );
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      final triggerContext = tester.element(find.byType(glass.GlassIconButton));
      final fade = GlassMaterializeScope.maybeOf(triggerContext)!;
      expect(fade.glassProgress, greaterThan(0));
      expect(fade.glassProgress, lessThan(1));
      // Old enclosing opacity + content scope combined as t * t.
      expect(
        fade.contentOpacity,
        closeTo(fade.glassProgress * fade.glassProgress, 1e-9),
      );
      expect(
        enclosingBackdropGroup(
          tester.renderObject(find.byType(glass.GlassIconButton)),
        ),
        isNotNull,
      );
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isTrue);
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isFalse);
      final restored = GlassMaterializeScope.maybeOf(
        tester.element(find.byType(glass.GlassIconButton)),
      )!;
      expect(restored.glassProgress, 1);
      expect(restored.contentOpacity, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'performance mode keeps elastic connect control instead of static replacement',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
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
      expect(find.byType(glass.GlassButton), findsOneWidget);
      expect(
        tester
            .widget<glass.GlassButton>(find.byType(glass.GlassButton))
            .useOwnLayer,
        isTrue,
      );
    },
  );
}
