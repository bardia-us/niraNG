import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/liquid_controls.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  _Controller(this.performanceMode);
  final bool performanceMode;
  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(performanceMode: performanceMode),
    servers: [
      for (var i = 0; i < 30; i++)
        ServerInfo(
          id: 's$i',
          name: 'Server $i',
          protocol: 'VLESS',
          transport: 'TCP',
          country: 'DE',
          port: 443,
          security: 'TLS',
          status: 'idle',
          selected: i == 0,
        ),
    ],
  );
}

void main() {
  testWidgets(
    'scrolling cancels row press deformation while the finger stays down',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => _Controller(false)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(body: ServersScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ListTile, 'Server 0');
      double paintedWidth() =>
          tester.getTopRight(row).dx - tester.getTopLeft(row).dx;
      final normalWidth = paintedWidth();
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Server 0')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(paintedWidth(), lessThan(normalWidth));
      await finger.moveBy(const Offset(0, -40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        paintedWidth(),
        closeTo(normalWidth, .01),
        reason:
            'Vertical scrolling must not keep the row compressed until finger-up',
      );
      await finger.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final performance in [false, true]) {
    testWidgets(
      'server lenses follow motion before paint (performance=$performance)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(
                () => _Controller(performance),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              localizationsDelegates: const [
                AppStrings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Scaffold(body: ServersScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final list = tester.widget<ReorderableListView>(
          find.byType(ReorderableListView),
        );
        expect(list.scrollController, isNotNull);
        final trigger = find.byType(LiquidActionMenu<String>).first;
        final syncs = tester
            .widgetList<glass.GlassMotionSync>(
              find.ancestor(
                of: trigger,
                matching: find.byType(glass.GlassMotionSync),
              ),
            )
            .toList();
        expect(
          syncs.where((sync) => identical(sync.motion, list.scrollController)),
          hasLength(1),
        );
        expect(
          syncs.where((sync) => sync.motion is Animation),
          hasLength(performance ? 0 : 1),
          reason:
              'The row press also moves the cached lens, independently of scrolling',
        );
        for (final offset in [40.0, 100.0, 60.0]) {
          list.scrollController!.jumpTo(offset);
          await tester.pump();
          expect(list.scrollController!.offset, offset);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
