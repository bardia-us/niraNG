import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
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
  testWidgets(
    'performance mode keeps spring menu and registers overlay until closed',
    (tester) async {
      liveGlassReadyListenable.value = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
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
      );
      await tester.pumpAndSettle();
      expect(find.byType(glass.GlassMenu), findsOneWidget);
      expect(
        tester
            .widget<glass.GlassIconButton>(find.byType(glass.GlassIconButton))
            .useOwnLayer,
        isTrue,
      );
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isTrue);
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isFalse);
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
