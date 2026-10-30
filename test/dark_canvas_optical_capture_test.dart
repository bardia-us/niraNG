import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _EmptyController extends AppController {
  @override
  Future<AppSnapshot> build() async =>
      const AppSnapshot(settings: NativeSettings(performanceMode: false));
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);

  for (final canvas in AppTheme.darkCanvases.keys) {
    testWidgets(
      'empty $canvas Servers capture contains the visible opaque canvas',
      (tester) async {
        liveGlassReadyListenable.value = true;
        final screen = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(_EmptyController.new),
            ],
            child: MaterialApp(
              theme: AppTheme.forSettings(
                brightness: Brightness.dark,
                reducedEffects: false,
                accentColor: 'purple',
                darkCanvas: canvas,
              ),
              localizationsDelegates: const [AppStrings.delegate],
              home: RepaintBoundary(
                key: screen,
                child: const Scaffold(body: ServersScreen()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final source = tester
            .widget<OpticalBackdropBoundary>(
              find.byType(OpticalBackdropBoundary),
            )
            .source;
        // This lies below both empty section headers: only the selected canvas
        // should be available to any lens sampling this area.
        const region = Rect.fromLTWH(250, 400, 100, 80);
        final captured = source.captureRegion(1, 0, region)!.$1;
        final boundary =
            screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final rendered = boundary.toImageSync();
        final pixels = (await tester.runAsync(
          () => captured.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        final visible = (await tester.runAsync(
          () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        for (final point in [
          const Offset(10, 10),
          const Offset(50, 40),
          const Offset(90, 70),
        ]) {
          final sampledOffset =
              ((point.dy.toInt() * captured.width) + point.dx.toInt()) * 4;
          final visibleOffset =
              (((region.top + point.dy).toInt() * rendered.width) +
                  (region.left + point.dx).toInt()) *
              4;
          expect(
            pixels.getUint8(sampledOffset + 3),
            255,
            reason:
                'The captured background must not depend on an uncaptured Scaffold.',
          );
          for (var channel = 0; channel < 3; channel++) {
            expect(
              pixels.getUint8(sampledOffset + channel),
              closeTo(visible.getUint8(visibleOffset + channel), 1),
              reason:
                  'Glass must receive the visible $canvas background, not a transparent purple glow.',
            );
          }
        }
        rendered.dispose();
      },
    );
  }
}
