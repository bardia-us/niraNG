import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:nirang/features/vpn/app_controller.dart';

void main() {
  for (final options in [
    (motion: false, contrast: false),
    (motion: true, contrast: false),
    (motion: true, contrast: true),
  ]) {
    final reducedMotion = options.motion;
    testWidgets('dialog primes then opens with accessibility $options', (
      tester,
    ) async {
      var shown = 0;
      final bodyKey = GlobalKey();
      late BuildContext routeContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [performanceModeProvider.overrideWithValue(false)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reducedMotion,
                highContrast: options.contrast,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNirangDialog<void>(
                  context: context,
                  onShown: () => shown++,
                  builder: (context) {
                    routeContext = context;
                    return Center(
                      child: GlassSurface(
                        child: SizedBox(key: bodyKey, width: 200, height: 100),
                      ),
                    );
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(GlassVisibilityScope.maybeOf(bodyKey.currentContext!), 0);
      double fallbackOpacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byType(FrostedSurface),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(fallbackOpacity(), 0);
      expect(shown, 0);
      expect(MenuActivity.isOpen.value, isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final visibility = GlassVisibilityScope.maybeOf(bodyKey.currentContext!);
      expect(fallbackOpacity(), visibility);
      final box = bodyKey.currentContext!.findRenderObject() as RenderBox;
      final width =
          (box.localToGlobal(const Offset(200, 0)) -
                  box.localToGlobal(Offset.zero))
              .distance;
      if (reducedMotion) {
        expect(visibility, 1);
        expect(width, closeTo(200, .01));
        expect(shown, 1);
      } else {
        expect(visibility, greaterThan(0));
        expect(visibility, lessThan(1));
        expect(width, greaterThan(188));
        expect(width, lessThan(200));
        expect(shown, 0);
      }
      await tester.pumpAndSettle();
      expect(GlassVisibilityScope.maybeOf(bodyKey.currentContext!), 1);
      expect(shown, 1);
      Navigator.pop(routeContext);
      await tester.pumpAndSettle();
      expect(shown, 1);
      expect(MenuActivity.isOpen.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing during priming never reports a shown dialog', (
    tester,
  ) async {
    late BuildContext context;
    var shown = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    showNirangDialog<void>(
      context: context,
      onShown: () => shown++,
      builder: (_) => const Center(child: SizedBox(width: 200, height: 100)),
    );
    await tester.pump();
    expect(MenuActivity.isOpen.value, isTrue);
    Navigator.pop(context);
    await tester.pumpAndSettle();
    expect(shown, 0);
    expect(MenuActivity.isOpen.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
