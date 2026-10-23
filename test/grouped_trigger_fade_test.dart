import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:liquid_glass_widgets/src/renderer/glass_materialize_scope.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    settings: NativeSettings(feedbackMode: 'off', performanceMode: false),
  );
}

void main() {
  testWidgets('painted row trigger fades without creating an optical layer', (
    tester,
  ) async {
    liveGlassReadyListenable.value = true;
    final progress = ValueNotifier<double>(1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(_Controller.new)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, child) => GlassMaterializeScope(
                  glassProgress: value,
                  contentOpacity: value,
                  contentSigma: 0,
                  child: child!,
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: LiquidActionMenu<int>(
                    serverActions: true,
                    tooltip: 'Actions',
                    fallback: const SizedBox(),
                    onSelected: (_) {},
                    items: const [
                      LiquidActionItem(
                        value: 1,
                        label: 'Open',
                        icon: Icons.info,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byWidgetPredicate(
      (w) => w is glass.GlassButton && w.label == 'Actions',
    );
    final element = tester.element(finder);
    expect(tester.widget<glass.GlassButton>(finder).useOwnLayer, isFalse);
    progress.value = .45;
    await tester.pump();
    expect(
      tester.widget<glass.GlassButton>(finder).useOwnLayer,
      isFalse,
      reason: 'An independent fade must not recreate the removed optical pass',
    );
    expect(
      find.descendant(
        of: finder,
        matching: find.byWidgetPredicate(
          (widget) => widget is Opacity && widget.opacity == .45,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: finder, matching: find.byType(glass.AdaptiveGlass)),
      findsNothing,
    );
    expect(
      tester.element(finder),
      same(element),
      reason: 'Layer selection must preserve the button/gesture state',
    );
    progress.value = 1;
    await tester.pumpAndSettle();
    expect(tester.widget<glass.GlassButton>(finder).useOwnLayer, isFalse);
    expect(tester.element(finder), same(element));
    await tester.pumpWidget(const SizedBox());
    progress.dispose();
    liveGlassReadyListenable.value = false;
    expect(tester.takeException(), isNull);
  });
}
