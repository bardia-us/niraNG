import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_scroll_behavior.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(feedbackMode: 'off'));
}

void main() {
  testWidgets(
    'glass control drag owns its gesture but tap and surrounding scroll work',
    (tester) async {
      liveGlassReadyListenable.value = true;
      addTearDown(() => liveGlassReadyListenable.value = false);
      final list = ScrollController(initialScrollOffset: 40);
      final pages = PageController();
      addTearDown(list.dispose);
      addTearDown(pages.dispose);
      var selected = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            home: Scaffold(
              body: glass.GlassBackdropGroup(
                child: PageView(
                  controller: pages,
                  children: [
                    ListView(
                      controller: list,
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: LiquidActionMenu<int>(
                            tooltip: 'Actions',
                            fallback: const SizedBox.square(dimension: 44),
                            onSelected: (_) => selected = true,
                            items: const [
                              LiquidActionItem(
                                value: 1,
                                label: 'Update',
                                icon: Icons.refresh,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 1500),
                      ],
                    ),
                    const Center(child: Text('Second')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byTooltip('Actions'), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(
        list.offset,
        40,
        reason: 'Pulling the lens must not scroll its list',
      );
      await tester.drag(find.byTooltip('Actions'), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(pages.page, 0, reason: 'Pulling the lens must not change tabs');
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      await tester.dragFrom(const Offset(80, 400), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(list.offset, greaterThan(40));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bouncing scroll does not add a second nonuniform stretch to circles',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const NirangScrollBehavior(reducedEffects: false),
          home: Scaffold(
            body: ListView(
              children: const [
                SizedBox(height: 50),
                CircleAvatar(),
                SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(
        scroll.position.physics.toString(),
        contains('BouncingScrollPhysics'),
      );
    },
  );
}
