import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/features/logs/logs_screen.dart';
import 'package:nirang/features/vpn/app_controller.dart';

class _LogsController extends AppController {
  _LogsController(this.initialLogs);
  final List<LogEntry> initialLogs;

  @override
  Future<AppSnapshot> build() async => AppSnapshot(logs: initialLogs);

  void replaceLogs(List<LogEntry> logs) {
    state = AsyncData(state.asData!.value.copyWith(logs: logs));
  }

  @override
  Future<void> refreshLogs() async {}

  @override
  Future<void> clearLogs() async => replaceLogs(const []);
}

LogEntry _log(String message, [int index = 0]) =>
    LogEntry(DateTime(2026, 10, 5, 12, 0, index), 'info', message);

Future<void> _showLogs(WidgetTester tester, _LogsController controller) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LogsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('long press copies a selected log word', (tester) async {
    final controller = _LogsController([_log('Connected')]);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _showLogs(tester, controller);
    await tester.longPress(find.text('Connected'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'Connected');
  });

  testWidgets('active selection survives a new batch and keeps scroll still', (
    tester,
  ) async {
    final logs = List.generate(30, (i) => _log('Connected$i', i));
    final controller = _LogsController(logs);
    await _showLogs(tester, controller);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Connected29'));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    final offset = scroll.position.pixels;
    controller.replaceLogs([_log('Newest')]);
    await tester.pumpAndSettle();
    expect(find.text('Connected29'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(scroll.position.pixels, offset);
    await tester.tapAt(const Offset(350, 70));
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
  });

  testWidgets('a long log renders its last line for selection', (tester) async {
    const message = 'line1\nline2\nline3\nline4\nline5\nline6\nfinal line';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _showLogs(tester, _LogsController([_log(message)]));
    final text = tester.widget<Text>(find.text(message));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    await tester.longPress(find.text(message));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, contains(message));
  });

  testWidgets('clear requires confirmation and then shows the empty state', (
    tester,
  ) async {
    await _showLogs(tester, _LogsController([_log('Connected')]));
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No logs yet'), findsOneWidget);
  });
}
