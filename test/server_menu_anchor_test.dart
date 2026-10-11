import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/main.dart';

class _Controller extends AppController {
  _Controller(this.performance, this.dark);
  final bool performance;
  final bool dark;

  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(
      performanceMode: performance,
      performanceModePrompted: true,
      themeMode: dark ? 'dark' : 'light',
      feedbackMode: 'off',
    ),
  );
}

void main() {
  for (final performance in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'header fallback menu does not add top chrome twice (matte=$performance, dark=$dark)',
        (tester) async {
          tester.view.padding = const FakeViewPadding(top: 48);
          addTearDown(tester.view.resetPadding);
          liveGlassReadyListenable.value = false;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appControllerProvider.overrideWith(
                  () => _Controller(performance, dark),
                ),
              ],
              child: const NirangApp(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Servers').last);
          await tester.pumpAndSettle();
          final header = find.ancestor(
            of: find.text('Servers (0)'),
            matching: find.byType(GlassSurface),
          );
          final headerBottom = tester.getRect(header).bottom;
          await tester.tap(find.byTooltip('Server page actions'));
          await tester.pumpAndSettle();
          final menu = find.byKey(
            const ValueKey('server-page-actions-surface'),
          );
          // The header has already cleared the app bar + status area. Its menu
          // needs only the small anchor gap, not another status/app-bar inset.
          expect(tester.getRect(menu).top - headerBottom, closeTo(5, .1));
          expect(find.text('Update now'), findsOneWidget);
          await tester.tapAt(const Offset(4, 200));
          await tester.pumpAndSettle();
          expect(menu, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
