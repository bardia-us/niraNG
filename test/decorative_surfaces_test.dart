import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/decorative_glass_surface.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/home_screen.dart';

class _Controller extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    subscriptionConfigured: true,
    settings: NativeSettings(performanceMode: false, feedbackMode: 'off'),
    usage: SubscriptionUsage(used: 100, total: 1000),
  );
}

Widget _app(Widget child, Brightness brightness) => ProviderScope(
  overrides: [appControllerProvider.overrideWith(_Controller.new)],
  child: MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  testWidgets(
    'circle and glyph pass together into the header input without masking',
    (tester) async {
      liveGlassReadyListenable.value = true;
      final header = GlobalKey();
      final frame = GlobalKey();
      final source = OpticalBackdropSource();
      final movement = ValueNotifier(Offset.zero);
      addTearDown(movement.dispose);
      await tester.pumpWidget(
        _app(
          Center(
            child: OpticalBackdropBoundary(
              source: source,
              child: RepaintBoundary(
                key: frame,
                child: SizedBox.square(
                  dimension: 120,
                  child: ColoredBox(
                    color: const Color(0xFFFF00FF),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 10,
                          top: 8,
                          width: 100,
                          height: 40,
                          child: SizedBox(key: header),
                        ),
                        Positioned(
                          left: 40,
                          top: 30,
                          width: 40,
                          height: 40,
                          child: ValueListenableBuilder(
                            valueListenable: movement,
                            builder: (_, offset, child) => Transform.translate(
                              offset: offset,
                              child: child,
                            ),
                            child: LiquidActionMenu<int>(
                              serverActions: true,
                              tooltip: 'Painted control',
                              icon: const SizedBox(
                                width: 4,
                                height: 12,
                                child: ColoredBox(color: Color(0xFF00FF00)),
                              ),
                              fallback: const SizedBox(),
                              items: const [
                                LiquidActionItem(
                                  value: 1,
                                  label: 'Choose',
                                  icon: Icons.check,
                                ),
                              ],
                              onSelected: (_) {},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Brightness.light,
        ),
      );
      await tester.pumpAndSettle();
      Future<List<int>> pixel(int x, int y) async =>
          (await tester.runAsync(() async {
            final boundary =
                frame.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final index = (y * image.width + x) * 4;
              return [
                for (var channel = 0; channel < 4; channel++)
                  bytes.getUint8(index + channel),
              ];
            } finally {
              image.dispose();
            }
          }))!;
      expect(
        await pixel(50, 40),
        isNot([255, 0, 255, 255]),
        reason: 'The circle enters the header together with its glyph',
      );
      expect(await pixel(60, 46), [
        0,
        255,
        0,
        255,
      ], reason: 'The glyph still paints inside header');
      final outsideCircle = await pixel(60, 65);
      expect(
        outsideCircle,
        isNot([255, 0, 255, 255]),
        reason:
            'The part outside the header must remain visible, not disappear',
      );
      final captured = source
          .captureRegion(1, 0, const Rect.fromLTWH(0, 0, 120, 120))!
          .$1;
      final bytes = (await tester.runAsync(() => captured.toByteData()))!;
      List<int> sample(int x, int y) => [
        for (var c = 0; c < 4; c++) bytes.getUint8((y * 120 + x) * 4 + c),
      ];
      expect(
        sample(60, 65),
        outsideCircle,
        reason:
            'The header input includes the same whole circle, not a glyph-only cutout',
      );
      expect(sample(60, 46), [
        0,
        255,
        0,
        255,
      ], reason: 'The foreground glyph still enters the header input');
      expect(
        await pixel(60, 65),
        outsideCircle,
        reason: 'Capturing must not leave the main scene missing its circle',
      );
      movement.value = const Offset(0, 45);
      await tester.pumpAndSettle();
      expect(
        await pixel(50, 85),
        isNot([255, 0, 255, 255]),
        reason: 'Circle returns without a corrective touch',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      source.dispose();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('row keeps elastic input without backdrop reads ($brightness)', (
      tester,
    ) async {
      liveGlassReadyListenable.value = true;
      var selected = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: LiquidActionMenu<int>(
              serverActions: true,
              tooltip: 'Row menu',
              fallback: const Text('Fallback'),
              items: const [
                LiquidActionItem(value: 1, label: 'Choose', icon: Icons.check),
              ],
              onSelected: (_) => selected++,
            ),
          ),
          brightness,
        ),
      );
      await tester.pumpAndSettle();
      final control = find.byType(glass.GlassButton);
      // A future optical/filter regression must fail even if the icon looks OK.
      expect(
        find.descendant(
          of: control,
          matching: find.byType(glass.AdaptiveGlass),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: control, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      final glyph = find.byIcon(Icons.more_vert_rounded);
      final resting = tester.getCenter(glyph);
      for (final cancel in [false, true]) {
        final drag = await tester.startGesture(resting);
        await tester.pump(const Duration(milliseconds: 60));
        await drag.moveBy(const Offset(-36, 28));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect((tester.getCenter(glyph) - resting).distance, greaterThan(1));
        if (cancel) {
          await drag.cancel();
        } else {
          await drag.up();
        }
        await tester.pumpAndSettle();
        expect((tester.getCenter(glyph) - resting).distance, lessThan(.01));
      }
      await tester.tap(find.byTooltip('Row menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'Home and its traffic dialog do not sample the backdrop ($brightness)',
      (tester) async {
        liveGlassReadyListenable.value = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.nirang.client/control'),
          (call) async => call.method == 'getMeasuredTraffic'
              ? {'available': true, 'todayBytes': 10, 'monthBytes': 20}
              : throw StateError('Unexpected native call ${call.method}'),
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('dev.nirang.client/control'),
            null,
          ),
        );
        await tester.pumpWidget(_app(const HomeScreen(), brightness));
        await tester.pumpAndSettle();
        expect(find.byType(glass.AdaptiveGlass), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('Connect'), findsOneWidget);
        final connect = find.ancestor(
          of: find.text('Connect'),
          matching: find.byType(glass.GlassButton),
        );
        final paintedButton = find.descendant(
          of: connect,
          matching: find.byType(DecorativeGlassSurface),
        );
        expect(
          tester.getSize(paintedButton).height,
          closeTo(tester.getSize(connect).height, .01),
          reason:
              'The painted face must fill the full button, not just its label',
        );
        await tester.ensureVisible(find.byIcon(Icons.info_outline_rounded));
        await tester.tap(find.byIcon(Icons.info_outline_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Close'), findsOneWidget);
        expect(find.byType(glass.AdaptiveGlass), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
