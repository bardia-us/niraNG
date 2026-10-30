import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/live_liquid_glass.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _Controller extends AppController {
  _Controller({this.optical = false});
  final bool optical;
  static final reorders = <(int, int)>[];
  @override
  Future<void> reorderServers(int oldIndex, int newIndex) async {
    reorders.add((oldIndex, newIndex));
  }

  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(performanceMode: !optical),
    servers: [
      for (final kind in ['uri', 'json', 'aether', 'aether2'])
        ServerInfo(
          id: kind,
          name: 'Profile $kind',
          country: kind == 'aether2' ? 'DE' : '',
          psiphonEnabled: kind.startsWith('aether'),
          protocol: kind,
          transport: '',
          security: '',
          port: 0,
          selected: kind == 'uri',
          status: 'idle',
          profileKind: kind.startsWith('aether') ? 'aether' : kind,
          profileEditable: kind == 'json',
        ),
    ],
  );
}

Future<void> _mount(
  WidgetTester tester, {
  bool optical = false,
  bool persian = false,
}) async {
  liveGlassReadyListenable.value = optical;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(() => _Controller(optical: optical)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: Locale(persian ? 'fa' : 'en'),
        supportedLocales: AppStrings.supportedLocales,
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
}

void main() {
  tearDown(() => liveGlassReadyListenable.value = false);
  for (final persian in [false, true]) {
    testWidgets('section count follows its title with spacing (fa=$persian)', (
      tester,
    ) async {
      await _mount(tester, persian: persian);
      for (final aether in [false, true]) {
        final group = find.byKey(
          ValueKey('server-group-row-${aether ? 'aether' : 'subscription'}'),
        );
        final title = find.descendant(
          of: group,
          matching: find.text(
            aether
                ? 'Aether'
                : persian
                ? 'سرورهای اشتراک'
                : 'Subscription servers',
          ),
        );
        final count = find.descendant(of: group, matching: find.text('2'));
        final titleRect = tester.getRect(title);
        final countRect = tester.getRect(count);
        final gap = persian
            ? titleRect.left - countRect.right
            : countRect.left - titleRect.right;
        expect(gap, inInclusiveRange(10.0, 16.0));
      }
    });
  }
  testWidgets('compact Persian groups keep add and cards usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester, persian: true);
    expect(
      Directionality.of(tester.element(find.byType(ServersScreen))),
      TextDirection.rtl,
    );
    expect(find.text('افزودن'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
    await tester.pumpAndSettle();
    expect(find.text('Profile aether'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsing subscription group removes rows and their controls only',
    (tester) async {
      await _mount(tester);
      expect(find.text('Profile json'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
      await tester.pumpAndSettle();
      expect(find.text('Profile uri'), findsNothing);
      expect(find.text('Profile json'), findsNothing);
      expect(find.byKey(const ValueKey('server-menu-json')), findsNothing);
      expect(find.text('Profile aether'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
      await tester.pumpAndSettle();
      expect(find.text('Profile json'), findsOneWidget);
    },
  );

  testWidgets(
    'JSON has one flag indicator and Aether has one brand indicator',
    (tester) async {
      await _mount(tester);
      expect(find.text('{}'), findsNothing);
      expect(find.byIcon(Icons.data_object_rounded), findsNothing);
      final aetherRow = find.ancestor(
        of: find.text('Profile aether'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: aetherRow,
          matching: find.byKey(const ValueKey('aether-brand-aether')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: aetherRow,
          matching: find.byIcon(Icons.public_rounded),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('group rows collapse gradually with controls aligned', (
    tester,
  ) async {
    await _mount(tester, optical: true);
    final start = tester.getCenter(find.text('Profile aether')).dy;
    await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final partial = tester.getCenter(find.text('Profile aether')).dy;
    expect(partial, lessThan(start));
    expect(partial, greaterThan(start - 130));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Profile aether')).dy,
      closeTo(start - 130, .1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Aether menu only has its settings editor', (tester) async {
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('server-menu-aether')));
    await tester.pumpAndSettle();
    expect(find.text('Aether settings'), findsOneWidget);
    expect(find.text('Server information'), findsNothing);
  });

  testWidgets('drag boundary clamps Aether before its group header', (
    tester,
  ) async {
    await _mount(tester);
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderStart!(4);
    await tester.pump();
    final context = tester.element(find.byType(ReorderableListView));
    final boundary = list.dragBoundaryProvider!(context)!;
    final row = tester.getRect(find.byKey(const ValueKey('aether')));
    final clamped = boundary.nearestPositionWithinBoundary(
      row.shift(const Offset(0, -500)),
    );
    expect(clamped.top, closeTo(row.top, .1));
    expect(boundary.isWithinBoundary(clamped), isTrue);
    list.onReorderEnd?.call(4);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opening a lower group scrolls while its rows expand', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 350));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('server-group-aether')));
    await tester.pumpAndSettle();
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    final scroll = list.scrollController!;
    final start = scroll.offset;
    await tester.tap(find.byKey(const ValueKey('server-group-aether')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final partial = scroll.offset;
    expect(partial, greaterThan(start));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(partial));
    expect(tester.takeException(), isNull);
  });

  for (final (id, delta) in [('aether', -260.0), ('json', 260.0)]) {
    testWidgets(
      'dragging $id across a group leaves the other group still before drop',
      (tester) async {
        _Controller.reorders.clear();
        await _mount(tester, optical: true);
        final header = find.byKey(const ValueKey('server-group-row-aether'));
        final initialHeader = tester.getTopLeft(header);
        final other = find.text(
          id == 'aether' ? 'Profile json' : 'Profile aether',
        );
        final initialOther = tester.getTopLeft(other);
        final finger = await tester.startGesture(
          tester.getCenter(find.text('Profile $id')),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await finger.moveBy(Offset(0, delta));
        await tester.pump(const Duration(milliseconds: 150));
        expect(tester.getTopLeft(header), initialHeader);
        expect(tester.getTopLeft(other), initialOther);
        expect(_Controller.reorders, isEmpty);
        await finger.up();
        await tester.pumpAndSettle();
        expect(_Controller.reorders, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('JSON information never opens ordinary protocol editor', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('server-menu-json')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server information'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-server-profile')), findsNothing);
  });

  testWidgets(
    'optical collapse removes every hidden control and keeps following group aligned',
    (tester) async {
      await _mount(tester, optical: true);
      final previousAetherY = tester.getCenter(find.text('Profile aether')).dy;
      await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-menu-uri')), findsNothing);
      expect(find.byKey(const ValueKey('server-menu-json')), findsNothing);
      expect(
        tester.getCenter(find.text('Profile aether')).dy,
        closeTo(previousAetherY - 130, .1),
      );
      await tester.tap(find.byKey(const ValueKey('server-group-aether')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('server-menu-aether')), findsNothing);
      expect(find.byKey(const ValueKey('server-menu-aether2')), findsNothing);
      expect(find.text('Profile aether'), findsNothing);
    },
  );

  testWidgets(
    'group reorder uses source indices and rejects cross-group drops',
    (tester) async {
      _Controller.reorders.clear();
      await _mount(tester);
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      list.onReorderItem!(1, 2);
      await tester.pump();
      expect(_Controller.reorders, [(0, 2)]);
      list.onReorderItem!(1, 4);
      await tester.pump();
      expect(_Controller.reorders, [(0, 2)]);
      await tester.tap(find.byKey(const ValueKey('server-group-subscription')));
      await tester.pumpAndSettle();
      final collapsedList = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      collapsedList.onReorderItem!(2, 3);
      await tester.pump();
      expect(_Controller.reorders, [(0, 2), (2, 4)]);
    },
  );
}
