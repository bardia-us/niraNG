import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/optical_backdrop.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  void changeName() => state = const AsyncData(
    AppSnapshot(
      settings: NativeSettings(performanceMode: false, feedbackMode: 'off'),
      servers: [
        ServerInfo(
          id: 'one',
          name: 'MMMMMMMMMMMM',
          country: 'DE',
          protocol: 'VLESS',
          transport: 'TCP',
          security: 'TLS',
          port: 443,
          status: 'idle',
          selected: true,
        ),
      ],
    ),
  );
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    settings: NativeSettings(performanceMode: false, feedbackMode: 'off'),
    servers: [
      ServerInfo(
        id: 'one',
        name: 'One',
        country: 'DE',
        protocol: 'VLESS',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        status: 'idle',
        selected: true,
      ),
    ],
  );
}

class _LongListController extends AppController {
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: const NativeSettings(performanceMode: false),
    servers: [
      for (var i = 0; i < 40; i++)
        ServerInfo(
          id: 's$i',
          name: 'Server $i',
          country: i.isEven ? 'DE' : 'FI',
          protocol: 'VLESS',
          transport: 'TCP',
          security: 'TLS',
          port: 443,
          status: 'idle',
          selected: i == 2,
        ),
    ],
  );
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  for (final brightness in Brightness.values) {
    testWidgets(
      'long scroll samples current header pixels in two images $brightness',
      (tester) async {
        liveGlassReadyListenable.value = true;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(_LongListController.new),
            ],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: const [AppStrings.delegate],
              home: const Scaffold(body: ServersScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final capture = tester.widget<OpticalBackdropCapture>(
          find.byType(OpticalBackdropCapture),
        );
        final source = capture.source;
        final scroll = tester
            .widget<ReorderableListView>(find.byType(ReorderableListView))
            .scrollController!;
        for (final offset in [
          0.0,
          130.0,
          390.0,
          780.0,
          1365.0,
          1950.0,
          1170.0,
          0.0,
        ]) {
          scroll.jumpTo(offset);
          await tester.pump();
          final region = source.captureRegion(1, 0, capture.sampleRegion!)!;
          final pixels = (await tester.runAsync(() => region.$1.toByteData()))!;
          // Compare the adapter's cache against the real painted display list,
          // not against a mock or a second call to that same cache.
          final boundary =
              source.key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final fresh = boundary.toImageSync();
          final current = (await tester.runAsync(() => fresh.toByteData()))!;
          final x0 = (region.$2.dx - source.origin.dx).round();
          final y0 = (region.$2.dy - source.origin.dy).round();
          for (var y = 0; y < region.$1.height; y += 11) {
            // The header sees the ordinary whole row, including painted circles.
            // No separate glyph-only source or dynamically cut control column.
            for (var x = 0; x < region.$1.width; x += 13) {
              for (var c = 0; c < 4; c++) {
                expect(
                  pixels.getUint8((y * region.$1.width + x) * 4 + c),
                  current.getUint8(((y + y0) * fresh.width + x + x0) * 4 + c),
                  reason:
                      'Current source at scroll=$offset without another touch',
                );
              }
            }
          }
          fresh.dispose();
          var allocations = 0;
          final previous = ui.Image.onCreate;
          ui.Image.onCreate = (_) => allocations++;
          try {
            source.captureRegion(1, 4.5, capture.sampleRegion!);
          } finally {
            ui.Image.onCreate = previous;
          }
          expect(
            allocations,
            2,
            reason:
                'Legacy independent capture retains its raw input and Gaussian output',
          );
          allocations = 0;
          ui.Image.onCreate = (_) => allocations++;
          try {
            source.captureRegion(1, 2.4, capture.sampleRegion!);
          } finally {
            ui.Image.onCreate = previous;
          }
          expect(
            allocations,
            1,
            reason:
                'The button needs only its own Gaussian output, not a raw intermediate',
          );
        }
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final hostGlass in [true, false]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        testWidgets(
          'header retains live optics over decorative rows with host=$hostGlass/$direction/$brightness',
          (tester) async {
            liveGlassReadyListenable.value = true;
            Widget page = const ServersScreen();
            // An outer optical host must not make the header button refract its
            // sibling header a second time or remove its independent lens.
            if (hostGlass) {
              page = glass.InheritedLiquidGlass(
                settings: liquidSurfaceSettings(brightness),
                quality: glass.GlassQuality.premium,
                avoidsRefraction: true,
                child: page,
              );
            }
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  appControllerProvider.overrideWith(_Controller.new),
                ],
                child: MaterialApp(
                  builder: (_, child) =>
                      Directionality(textDirection: direction, child: child!),
                  theme: ThemeData(brightness: brightness),
                  localizationsDelegates: const [
                    AppStrings.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  home: Scaffold(body: page),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final trigger = find.byWidgetPredicate(
              (w) => w is glass.GlassButton && w.label == 'Server page actions',
            );
            expect(trigger, findsOneWidget);
            expect(
              tester.widget<glass.GlassButton>(trigger).useOwnLayer,
              isTrue,
            );
            final rowButton = find.byWidgetPredicate(
              (w) => w is glass.GlassButton && w.label == 'Server actions',
            );
            expect(
              tester.widget<glass.GlassButton>(rowButton).useOwnLayer,
              isFalse,
              reason: 'Painted row controls allocate no optical layer',
            );
            expect(
              find.ancestor(
                of: rowButton,
                matching: find.byType(glass.AdaptiveLiquidGlassLayer),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: rowButton,
                matching: find.byType(glass.AdaptiveGlass),
              ),
              findsNothing,
              reason: 'Rows must not regain refraction through an outer host',
            );
            expect(
              find.ancestor(of: trigger, matching: find.byType(GlassSurface)),
              findsNothing,
              reason:
                  'The header trigger is a sibling, so it cannot sample the header glass',
            );
            final headerSurface = find
                .descendant(
                  of: find
                      .ancestor(of: trigger, matching: find.byType(Stack))
                      .last,
                  matching: find.byType(GlassSurface),
                )
                .first;
            final headerCutouts = find.ancestor(
              of: headerSurface,
              matching: find.byWidgetPredicate(
                (widget) => widget is ClipPath && widget.clipper != null,
              ),
            );
            for (final element in headerCutouts.evaluate()) {
              final clip = element.renderObject! as RenderBox;
              final path = (element.widget as ClipPath).clipper!.getClip(
                clip.size,
              );
              expect(
                path.contains(clip.globalToLocal(tester.getCenter(trigger))),
                isTrue,
                reason:
                    'Header must remain continuous under the independent trigger',
              );
            }
            final headerCapture = tester.widget<OpticalBackdropCapture>(
              find.ancestor(
                of: trigger,
                matching: find.byType(OpticalBackdropCapture),
              ),
            );
            final original = headerCapture.source
                .captureRegion(1, 0, headerCapture.sampleRegion!)!
                .$1;
            final originalPixels = (await tester.runAsync(
              () => original.toByteData(),
            ))!;
            final controller =
                ProviderScope.containerOf(
                      tester.element(find.byType(ServersScreen)),
                    ).read(appControllerProvider.notifier)
                    as _Controller;
            controller.changeName();
            await tester.pump();
            final updated = headerCapture.source
                .captureRegion(1, 0, headerCapture.sampleRegion!)!
                .$1;
            final updatedPixels = (await tester.runAsync(
              () => updated.toByteData(),
            ))!;
            expect(
              updatedPixels.buffer.asUint8List(),
              isNot(orderedEquals(originalPixels.buffer.asUint8List())),
              reason:
                  'Header pixels must follow list-only repaint without a touch',
            );
            expect(
              find.ancestor(
                of: rowButton,
                matching: find.byType(OpticalBackdropCapture),
              ),
              findsNothing,
              reason: 'The full-height row capture has been removed',
            );
            expect(
              headerCapture.source.underlay,
              isNull,
              reason: 'Painted rows and list share one current header snapshot',
            );
            expect(find.byType(OpticalBackdropBoundary), findsOneWidget);
            expect(
              find.ancestor(
                of: rowButton,
                matching: find.byKey(headerCapture.source.key),
              ),
              findsOneWidget,
              reason:
                  'The same source captures list pixels and painted controls',
            );
            expect(headerCapture.source.key.currentContext, isNotNull);
            expect(
              headerCapture.sampleRegion!.height,
              lessThan(300),
              reason:
                  'Only fixed header optics sample, not the full-height row column',
            );
            await tester.tap(trigger);
            await tester.pumpAndSettle();
            expect(find.text('Update now'), findsOneWidget);
            await tester.tapAt(const Offset(4, 250));
            await tester.pumpAndSettle();
            expect(find.text('Update now'), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
