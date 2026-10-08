import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:nirang/core/interaction_feedback.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/widgets/glass_surface.dart';
import 'package:nirang/core/widgets/menu_activity.dart';
import 'package:nirang/core/registration/device_registration.dart';
import 'package:nirang/core/update_checker.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/app_shell.dart';
import 'package:nirang/features/vpn/home_screen.dart';
import 'package:nirang/features/servers/servers_screen.dart';
import 'package:nirang/features/settings/settings_screen.dart';

class _NavigationController extends AppController {
  _NavigationController({this.feedbackMode = 'off'});

  final String feedbackMode;

  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    settings: NativeSettings(
      performanceModePrompted: true,
      feedbackMode: feedbackMode,
    ),
  );
}

class _PendingClient implements HttpClient {
  final pending = Completer<HttpClientRequest>();
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => pending.future;
  @override
  void close({bool force = false}) {
    closed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _mountShell(
  WidgetTester tester, {
  String feedbackMode = 'off',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(
          () => _NavigationController(feedbackMode: feedbackMode),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'released page reaches destination without a long settling tail',
    (tester) async {
      await _mountShell(tester);
      final pager = tester.widget<PageView>(find.byType(PageView));
      final physics = pager.physics!;
      final simulation = physics.createBallisticSimulation(
        FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 800,
          pixels: 320,
          viewportDimension: 400,
          axisDirection: AxisDirection.right,
          devicePixelRatio: 3,
        ),
        0,
      )!;
      var previous = 320.0;
      for (var frame = 1; frame <= 48; frame++) {
        final position = simulation.x(frame / 120);
        expect(position, greaterThanOrEqualTo(previous));
        expect(position, lessThanOrEqualTo(400));
        previous = position;
      }
      expect(simulation.x(.4), closeTo(400, .06));
      expect(physics.minFlingDistance, 32);
      expect(physics.minFlingVelocity, 650);
    },
  );
  testWidgets('pager refreshes only glass on intersecting retained pages', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Servers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    glass.GlassMotionSync syncFor(Type page) =>
        tester.widget<glass.GlassMotionSync>(
          find.ancestor(
            of: find.byType(page, skipOffstage: false),
            matching: find.byType(glass.GlassMotionSync, skipOffstage: false),
          ),
        );
    expect(syncFor(HomeScreen).shouldRefresh?.call(), isFalse);
    expect(syncFor(ServersScreen).shouldRefresh?.call(), isFalse);
    expect(syncFor(SettingsScreen).shouldRefresh?.call(), isTrue);
    await tester.tap(find.text('Servers').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(syncFor(HomeScreen).shouldRefresh?.call(), isFalse);
    expect(syncFor(ServersScreen).shouldRefresh?.call(), isTrue);
    expect(syncFor(SettingsScreen).shouldRefresh?.call(), isTrue);
    await tester.pumpAndSettle();
    expect(syncFor(ServersScreen).shouldRefresh?.call(), isTrue);
    expect(syncFor(SettingsScreen).shouldRefresh?.call(), isFalse);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(syncFor(HomeScreen).shouldRefresh?.call(), isTrue);
    expect(syncFor(ServersScreen).shouldRefresh?.call(), isTrue);
    expect(syncFor(SettingsScreen).shouldRefresh?.call(), isFalse);
    await tester.pump(const Duration(milliseconds: 40));
    expect(syncFor(HomeScreen).shouldRefresh?.call(), isFalse);
    expect(syncFor(ServersScreen).shouldRefresh?.call(), isTrue);
    expect(syncFor(SettingsScreen).shouldRefresh?.call(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup GitHub request closes its client at seven seconds', (
    tester,
  ) async {
    final client = _PendingClient();
    await HttpOverrides.runZoned(() async {
      final result = const GitHubUpdateChecker(
        requestTimeout: Duration(seconds: 7),
      ).check('1.2.0');
      final completed = expectLater(result, throwsA(isA<TimeoutException>()));
      await tester.pump(const Duration(milliseconds: 6999));
      expect(client.closed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await completed;
      expect(client.closed, isTrue);
      client.pending.completeError(const SocketException('closed'));
      await tester.pump();
    }, createHttpClient: (_) => client);
  });
  testWidgets('startup update completion cannot read a disposed shell', (
    tester,
  ) async {
    final client = _PendingClient();
    await HttpOverrides.runZoned(() async {
      startupNetworkReady.value = true;
      await _mountShell(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      client.pending.completeError(const SocketException('offline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => client);
    startupNetworkReady.value = false;
  });
  testWidgets('last two pixels finish naturally without an early page jump', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Servers').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    // Exercise the small ease-out tail without waiting all 240ms.
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.position.isScrollingNotifier.value, isTrue);
    expect(pager.controller!.page, lessThan(1));
    expect(pager.controller!.page, greaterThan(.99));
    final previous = pager.controller!.page!;
    await tester.pump(const Duration(milliseconds: 5));
    expect(pager.controller!.page, greaterThan(previous));
    expect(pager.controller!.page, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'destination is touchable after 80 percent while animation still moves',
    (tester) async {
      await _mountShell(tester);
      await tester.tap(find.text('Servers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 105));
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, greaterThan(.8));
      expect(pager.controller!.page, lessThan(.99));
      expect(pager.controller!.position.isScrollingNotifier.value, isTrue);
      final viewport = find
          .descendant(
            of: find.byType(PageView),
            matching: find.byType(Viewport),
          )
          .first;
      final ignore = find
          .ancestor(of: viewport, matching: find.byType(IgnorePointer))
          .first;
      expect(
        tester.renderObject<RenderIgnorePointer>(ignore).ignoring,
        isFalse,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a destination setting really opens during the unlocked animation tail',
    (tester) async {
      await _mountShell(tester);
      await tester.tap(find.text('Settings').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, greaterThan(1.8));
      expect(pager.controller!.position.isScrollingNotifier.value, isTrue);
      expect(find.text('Connection mode').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Connection mode'));
      await tester.pumpAndSettle();
      expect(find.byType(NirangAlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('OLED canvas stays black with full visual effects', () {
    final theme = AppTheme.forSettings(
      brightness: Brightness.dark,
      reducedEffects: false,
      accentColor: 'rose',
      darkCanvas: 'oled',
    );
    final background = NirangVisualEffects.shellBackground(
      theme,
      reducedEffects: false,
    );
    expect(background.color, Colors.black);
    expect(background.gradient, isNull);
  });
  testWidgets('interrupting an unlocked tail locks the next transition again', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Servers').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 105));
    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    final viewport = find
        .descendant(of: find.byType(PageView), matching: find.byType(Viewport))
        .first;
    final ignore = find
        .ancestor(of: viewport, matching: find.byType(IgnorePointer))
        .first;
    expect(tester.renderObject<RenderIgnorePointer>(ignore).ignoring, isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab button moves through intermediate horizontal frames', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(PageView), findsOneWidget);
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, greaterThan(0));
    expect(pager.controller!.page, lessThan(2));
    await tester.pumpAndSettle();
    expect(pager.controller!.page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tab transition keeps shader pages live without detached snapshots',
    (tester) async {
      await _mountShell(tester);
      final cache = find.descendant(
        of: find.byType(PageView),
        matching: find.byType(SnapshotWidget),
      );
      expect(cache, findsNothing);
      await tester.tap(find.text('Servers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(cache, findsNothing);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      expect(cache, findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('vertical list drag does not switch the active tab', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-50, -220));
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, 2);
    expect(
      tester
          .widgetList<SnapshotWidget>(
            find.descendant(
              of: find.byType(PageView),
              matching: find.byType(SnapshotWidget),
            ),
          )
          .every((page) => !page.controller.allowSnapshotting),
      isTrue,
    );
  });

  testWidgets(
    'interrupted transitions preserve final tab and can dispose safely',
    (tester) async {
      await _mountShell(tester);
      await tester.tap(find.text('Settings').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, 0);
      expect(
        tester
            .widgetList<SnapshotWidget>(
              find.descendant(
                of: find.byType(PageView),
                matching: find.byType(SnapshotWidget),
              ),
            )
            .every((page) => !page.controller.allowSnapshotting),
        isTrue,
      );
      await tester.tap(find.text('Servers').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'horizontal swipe selects the adjacent page but an open popup blocks it',
    (tester) async {
      await _mountShell(tester);
      MenuActivity.isOpen.value = true;
      addTearDown(() => MenuActivity.isOpen.value = false);
      await tester.pump();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, 0);
      MenuActivity.isOpen.value = false;
      await tester.pump();
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(pager.controller!.page, 1);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
    },
  );

  testWidgets('short slow horizontal drag settles back on the current page', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.timedDrag(
      find.byType(PageView),
      const Offset(-70, 0),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, 0);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('bottom tab tap is blocked until the open menu has closed', (
    tester,
  ) async {
    await _mountShell(tester);
    MenuActivity.isOpen.value = true;
    addTearDown(() => MenuActivity.isOpen.value = false);
    await tester.pump();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(find.byType(PageView));
    expect(pager.controller!.page, 0);
    MenuActivity.isOpen.value = false;
    await tester.pump();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(pager.controller!.page, 2);
  });

  testWidgets('settings expansion and list offset survive leaving the page', (
    tester,
  ) async {
    await _mountShell(tester);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Theme & Appearance'),
      240,
      scrollable: find
          .descendant(
            of: find.byType(PageView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(find.text('Theme & Appearance'));
    await tester.pumpAndSettle();
    final setting = find.text('Dark background');
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(setting);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Dark background'), findsOneWidget);
    expect(tester.getTopLeft(setting), position);
  });

  testWidgets(
    'dark background picker fits its three options without a scroll container',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountShell(tester);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Theme & Appearance'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(PageView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('Theme & Appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dark background'));
      await tester.tap(find.text('Dark background'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.byType(ListTile)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        tester
            .getSize(
              find.descendant(of: dialog, matching: find.byType(GlassSurface)),
            )
            .height,
        lessThan(360),
      );
      expect(MenuActivity.isOpen.value, isTrue);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(MenuActivity.isOpen.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final choice in ['Language', 'Interaction feedback', 'Theme']) {
    testWidgets('$choice picker does not scroll when its options fit', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountShell(tester);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Theme & Appearance'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(PageView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('Theme & Appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(choice));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'each tab change emits one navigation cue and repeated selected tap stays quiet',
    (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('dev.nirang.client/feedback');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _mountShell(tester, feedbackMode: 'haptic');
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(calls, ['playNavigation']);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(calls, ['playNavigation']);
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(calls, ['playNavigation', 'playNavigation']);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
    },
  );

  testWidgets('bottom destination has a gentle elastic pressed state', (
    tester,
  ) async {
    await _mountShell(tester);
    final destination = find.byType(NavigationDestination).first;
    final scaleFinder = find.ancestor(
      of: destination,
      matching: find.byType(AnimatedScale),
    );
    final gesture = await tester.startGesture(tester.getCenter(destination));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, .94);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1);
  });

  testWidgets('navigation feedback sends short haptic and dedicated pop', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    const channel = MethodChannel('dev.nirang.client/feedback');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await InteractionFeedback.playNavigation('haptic');
    expect(
      calls,
      containsAll(['HapticFeedbackType.selectionClick', 'playNavigation']),
    );
    calls.clear();
    await InteractionFeedback.playNavigation('sound');
    expect(
      calls,
      containsAll(['HapticFeedbackType.selectionClick', 'playNavigation']),
    );
    calls.clear();
    await InteractionFeedback.playNavigation('off');
    expect(calls, isEmpty);
  });
}
