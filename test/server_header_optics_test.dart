import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
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

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  for (final hostGlass in [true, false]) {
    testWidgets('header reuses host optics only when provided ($hostGlass)', (
      tester,
    ) async {
      liveGlassReadyListenable.value = true;
      Widget page = const ServersScreen();
      // Flutter desktop tests cannot open the Impeller shader path. Supply
      // exactly the inheritance contract that GlassSurface supplies there.
      if (hostGlass) {
        page = glass.InheritedLiquidGlass(
          settings: liquidSurfaceSettings(Brightness.dark),
          quality: glass.GlassQuality.premium,
          avoidsRefraction: true,
          child: page,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(_Controller.new)],
          child: MaterialApp(
            theme: ThemeData.dark(),
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
      final trigger = find.byType(glass.GlassIconButton);
      expect(trigger, findsOneWidget);
      expect(
        tester.widget<glass.GlassIconButton>(trigger).useOwnLayer,
        !hostGlass,
      );
      final rowButton = find.byWidgetPredicate(
        (w) => w is glass.GlassButton && w.isStationary,
      );
      expect(
        tester.widget<glass.GlassButton>(rowButton).useOwnLayer,
        isTrue,
        reason: 'Standalone row controls keep their premium lens',
      );
      if (hostGlass) {
        expect(
          find.descendant(of: trigger, matching: find.byType(BackdropFilter)),
          findsNothing,
          reason: 'Header control must not read/blur its host again',
        );
        expect(
          find.descendant(of: trigger, matching: find.byType(CustomPaint)),
          findsWidgets,
          reason: 'Rim and specular painting are retained',
        );
      }
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsOneWidget);
      await tester.tapAt(const Offset(4, 250));
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
