import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/vpn/app_controller.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('Premium dialog overrides only backdrop blur $brightness', () {
      final message = liquidMessageSettings(brightness);
      final actual = GlassSurface.settingsFor(
        brightness,
        messageSurface: true,
        backdropBlur: 11,
      );
      expect(actual, message.copyWith(blur: 11));
      expect(actual.glassColor, message.glassColor);
      expect(actual.thickness, message.thickness);
      expect(liquidMessageSettings(brightness).blur, 3.5);
      expect(liquidSurfaceSettings(brightness).blur, 4.5);
    });
    testWidgets(
      'text dialog diffuses rather than covers its backdrop $brightness',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [performanceModeProvider.overrideWithValue(false)],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(
                body: NirangAlertDialog(
                  title: Text('Fragment settings'),
                  content: Text(
                    'Fragment packets\nFragment length\nFragment interval',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlassSurface>(find.byType(GlassSurface)).backdropBlur,
          11,
        );
        final filter = tester.widget<BackdropFilter>(
          find.byType(BackdropFilter),
        );
        expect(
          filter.filter.toString(),
          contains('11.0, 11.0'),
          reason: 'Only the background diffusion grows; no opaque backer',
        );
        final surface = tester.widget<FrostedSurface>(
          find.byType(FrostedSurface),
        );
        expect(surface.opaque, isFalse);
        expect(surface.tintAlpha, isNull);
      },
    );
  }
}
