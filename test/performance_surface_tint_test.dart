import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/theme/app_theme.dart';

double distance(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

void main() {
  for (final brightness in Brightness.values) {
    for (final canvas in ['midnight', 'graphite', 'oled']) {
      test(
        'Performance surface is less grey over $canvas / $brightness without losing text contrast',
        () {
          ThemeData theme(bool reduced) => AppTheme.forSettings(
            brightness: brightness,
            reducedEffects: reduced,
            accentColor: 'blue',
            darkCanvas: canvas,
          );
          final normal = theme(false);
          final performance = theme(true);
          final background = performance.scaffoldBackgroundColor;
          final surface = performance.colorScheme.surfaceContainerHigh;
          expect(
            distance(surface, background),
            lessThan(
              distance(normal.colorScheme.surfaceContainerHigh, background),
            ),
          );
          final light = performance.colorScheme.onSurface.computeLuminance();
          final dark = surface.computeLuminance();
          final contrast = light > dark
              ? (light + .05) / (dark + .05)
              : (dark + .05) / (light + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          expect(surface.a, 1);
        },
      );
    }
  }
}
