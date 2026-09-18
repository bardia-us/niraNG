import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/formatters.dart';
import 'package:nirang/core/async_operation_guard.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/update_checker.dart';
import 'package:nirang/core/user_facing_error.dart';
import 'package:nirang/core/widgets/release_notes_markdown.dart';
import 'package:nirang/core/widgets/glass_dialog.dart';
import 'package:nirang/core/widgets/update_dialog.dart';
import 'package:nirang/features/settings/per_app_ordering.dart';
import 'package:nirang/features/servers/server_sorting.dart';
import 'package:nirang/features/vpn/app_controller.dart';
import 'package:nirang/features/vpn/app_shell.dart';

void main() {
  testWidgets(
    'release notes render Markdown structure instead of raw markers',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReleaseNotesMarkdown(
              data: '## Changes\n- Added **forced updates**.\n`1.1.8`',
            ),
          ),
        ),
      );

      expect(find.text('Changes'), findsOneWidget);
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('forced updates'), findsOneWidget);
      expect(find.textContaining('1.1.8'), findsOneWidget);
    },
  );

  testWidgets('release notes dialog has one continuous scroll view', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NirangAlertDialog(
              title: Text("What's new"),
              content: ReleaseNotesMarkdown(
                data: '## Changes\n- First item\n- Second item',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  test('formats persisted byte counters without speed units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.00 MB');
    expect(formatBytes(18 * 1024 * 1024 * 1024 + 451 * 1024 * 1024), '18.4 GB');
    expect(formatBytes(2 * 1024 * 1024 * 1024 * 1024), '2.00 TB');
  });

  test('active update progress never moves backwards for one transfer', () {
    const current = UpdateDownloadSnapshot(
      state: 'downloading',
      received: 2300,
      total: 10000,
      name: 'niraNG.apk',
      version: '1.1.9',
      url:
          'https://github.com/bardia-us/niraNG/releases/download/v1.1.9/niraNG.apk',
    );
    const stalePoll = UpdateDownloadSnapshot(
      state: 'downloading',
      received: 2100,
      total: 10000,
      name: 'niraNG.apk',
      version: '1.1.9',
      url:
          'https://github.com/bardia-us/niraNG/releases/download/v1.1.9/niraNG.apk',
    );
    expect(current.merge(stalePoll).received, 2300);
  });

  test('presentation strips only a leading country flag from server names', () {
    expect(displayServerName('🇳🇱 2-bardia'), '2-bardia');
    expect(displayServerName('🇺🇸-edge'), 'edge');
    expect(displayServerName('Server 🇸🇪 inside'), 'Server 🇸🇪 inside');
  });

  test('server metadata keeps only masked credential fields', () {
    final server = ServerInfo.fromMap({
      'id': 'safe-id',
      'name': 'Example',
      'country': 'DE',
      'protocol': 'VLESS',
      'transport': 'WebSocket',
      'security': 'Reality',
      'port': 443,
      'sni': 'example.com',
      'credentialLabel': 'UUID',
      'credentialMasked': '********-****-****-****-************',
      'realityPublicKeyMasked': '••••••••••••••••',
      'shortIdMasked': '••••••',
      'selected': true,
      'status': 'success',
    });

    expect(server.port, 443);
    expect(server.security, 'Reality');
    expect(server.credentialMasked, '********-****-****-****-************');
    expect(server.realityPublicKeyMasked, isNotEmpty);
    expect(server.selected, isTrue);
  });

  test('malformed native log values are normalized without throwing', () {
    final entry = LogEntry.fromMap({
      'time': 9223372036854775807,
      'level': 'fatal',
      'message': List.filled(5000, 'x').join(),
    });

    expect(entry.level, 'info');
    expect(entry.message.length, 1200);
    expect(
      entry.time.isBefore(DateTime.now().add(const Duration(days: 1))),
      isTrue,
    );
  });

  test('connection metadata includes the current IP city', () {
    final connection = ConnectionInfo.fromMap({
      'state': 'connected',
      'publicIp': '213.165.41.160',
      'publicCountry': 'NL',
      'publicCity': 'Amsterdam',
      'publicIpChecked': true,
    });

    expect(connection.publicIp, '213.165.41.160');
    expect(connection.publicCountry, 'NL');
    expect(connection.publicCity, 'Amsterdam');
    expect(connection.publicIpChecked, isTrue);
  });

  test('settings updates are granular and preserve unrelated values', () {
    const settings = NativeSettings(
      themeMode: 'system',
      enableLocalDns: true,
      enableFakeDns: false,
      remoteDns: '8.8.8.8,https://dns.google/dns-query',
      vpnDns: '1.1.1.1',
      vpnMtu: 1500,
    );

    final updated = settings.withUpdates({
      'themeMode': 'dark',
      'vpnMtu': 1400,
      'connectionMode': 'proxy',
      'enableLocalDns': false,
      'enableFakeDns': true,
      'localSocksPort': 10818,
      'fragmentEnabled': true,
      'fragmentPackets': 'tlshello',
      'fragmentLength': '50-100',
      'fragmentInterval': '10-20',
      'fragmentMaxSplit': 8,
      'muxEnabled': true,
      'muxConcurrency': 32,
      'muxXudpConcurrency': 64,
      'muxQuicHandling': 'allow',
    });
    expect(updated.themeMode, 'dark');
    expect(updated.vpnMtu, 1400);
    expect(updated.remoteDns, '8.8.8.8,https://dns.google/dns-query');
    expect(updated.vpnDns, '1.1.1.1');
    expect(updated.connectionMode, 'proxy');
    expect(updated.localSocksPort, 10818);
    expect(updated.enableLocalDns, isFalse);
    expect(updated.enableFakeDns, isTrue);
    expect(updated.fragmentEnabled, isTrue);
    expect(updated.fragmentMaxSplit, 8);
    expect(updated.muxEnabled, isTrue);
    expect(updated.muxConcurrency, 32);
    expect(updated.muxXudpConcurrency, 64);
    expect(updated.muxQuicHandling, 'allow');
  });

  test('latency sort is stable and leaves failed or untested servers last', () {
    const base = ServerInfo(
      id: 'base',
      name: 'Base',
      country: '',
      protocol: 'VLESS',
      transport: 'TCP',
      security: 'TLS',
      port: 443,
      selected: false,
      status: 'idle',
    );
    final sorted = sortServersByTestResults([
      base.copyWith(status: 'timeout'),
      const ServerInfo(
        id: 'slow',
        name: 'Slow',
        country: '',
        protocol: 'VLESS',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        selected: false,
        status: 'success',
        ping: 220,
      ),
      const ServerInfo(
        id: 'fast-a',
        name: 'Fast A',
        country: '',
        protocol: 'VLESS',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        selected: false,
        status: 'success',
        ping: 80,
      ),
      const ServerInfo(
        id: 'fast-b',
        name: 'Fast B',
        country: '',
        protocol: 'VLESS',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        selected: false,
        status: 'success',
        ping: 80,
      ),
      base.copyWith(status: 'idle'),
    ]);

    expect(sorted.map((server) => server.id), [
      'fast-a',
      'fast-b',
      'slow',
      'base',
      'base',
    ]);
  });

  test('async operation guard coalesces duplicate heavy commands', () async {
    final guard = AsyncOperationGuard(cooldown: Duration.zero);
    final release = Completer<void>();
    var calls = 0;
    Future<void> operation() async {
      calls++;
      await release.future;
    }

    final first = guard.run('ping', operation);
    final duplicate = guard.run('ping', operation);
    expect(guard.isRunning('ping'), isTrue);
    expect(calls, 1);
    release.complete();
    await Future.wait([first, duplicate]);
    expect(calls, 1);
    expect(guard.isRunning('ping'), isFalse);
  });

  test('fresh Dart settings use the current network defaults', () {
    const settings = NativeSettings();

    expect(settings.domainStrategy, 'AsIs');
    expect(settings.routingMode, 'bypassIran');
    expect(settings.enableIpv6, isTrue);
    expect(settings.directDnsEnabled, isTrue);
    expect(settings.directDns, '178.22.122.100');
    expect(settings.routeOnly, isTrue);
    expect(settings.muxEnabled, isFalse);
  });

  test('selected applications are ordered before unselected applications', () {
    final ordered = orderSelectedFirst(
      const ['Zulu', 'Alpha', 'Beta'],
      isSelected: (value) => value == 'Zulu',
      label: (value) => value,
    );

    expect(ordered, const ['Zulu', 'Alpha', 'Beta']);
  });

  test('only explicit version notice remarks are not connectable', () {
    expect(isSubscriptionNoticeName('هر دفعه آپدیت کنید - V8.8'), isTrue);
    expect(isSubscriptionNoticeName('Update every time - V1.2'), isTrue);
    expect(isSubscriptionNoticeName('Update route Amsterdam'), isFalse);
    expect(isSubscriptionNoticeName('Normal VLESS 1.1.1.1'), isFalse);
  });

  test('semantic release versions compare without lexical mistakes', () {
    expect(
      SemanticVersion.parse('v1.1.0').compareTo(SemanticVersion.parse('1.0.4')),
      greaterThan(0),
    );
    expect(SemanticVersion.parse('v1.0.4+5').toString(), '1.0.4');
  });

  test('bilingual release notes select the matching language section', () {
    final notes = parseBilingualReleaseNotes('''
## English
- Added forced updates.
- Fixed network errors.

## فارسی
- آپدیت اجباری اضافه شد.
- خطاهای شبکه اصلاح شد.
''');

    expect(notes.forLanguage('en'), contains('forced updates'));
    expect(notes.forLanguage('fa'), contains('آپدیت اجباری'));
    expect(notes.forLanguage('fa'), isNot(contains('forced updates')));
  });

  test('What’s New is shown only after a real build upgrade', () {
    expect(
      shouldShowWhatsNew(appBuild: 19, seenBuild: 19, upgradedFromBuild: 0),
      isFalse,
      reason: 'Fresh installs establish a baseline without an update dialog.',
    );
    expect(
      shouldShowWhatsNew(appBuild: 19, seenBuild: 19, upgradedFromBuild: 0),
      isFalse,
      reason: 'Skipping a newer GitHub release is not an installed upgrade.',
    );
    expect(
      shouldShowWhatsNew(appBuild: 20, seenBuild: 19, upgradedFromBuild: 19),
      isTrue,
    );
    expect(
      shouldShowWhatsNew(appBuild: 20, seenBuild: 20, upgradedFromBuild: 19),
      isFalse,
      reason: 'Acknowledged notes stay dismissed for the installed build.',
    );
  });

  test('user-facing network errors never expose raw hosts or exceptions', () {
    final error = userFacingError(
      PlatformException(
        code: 'network',
        message: 'SocketException: Failed host lookup: neovip.ir',
      ),
      persian: false,
    );

    expect(error.combined, contains('Network is unavailable'));
    expect(error.combined, isNot(contains('neovip.ir')));
    expect(error.combined, isNot(contains('SocketException')));
  });

  test('invalid subscription responses produce actionable Persian text', () {
    final error = userFacingError(
      const FormatException('raw parser stack'),
      persian: true,
    );

    expect(error.combined, contains('Subscription'));
    expect(error.combined, contains('لینک'));
    expect(error.combined, isNot(contains('raw parser stack')));
  });

  test('GitHub release selects the APK matching Android ABI', () {
    final release = parseGitHubRelease({
      'tag_name': 'v1.1.4',
      'html_url': 'https://github.com/bardia-us/niraNG/releases/tag/v1.1.4',
      'assets': [
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url':
              'https://github.com/bardia-us/niraNG/releases/download/v1.1.4/niraNG-v1.1.4-armeabi-v7a.apk',
          'size': 100,
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url':
              'https://github.com/bardia-us/niraNG/releases/download/v1.1.4/niraNG-v1.1.4-arm64-v8a.apk',
          'size': 120,
          'digest':
              'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
      ],
    }, '1.1.3');

    final asset = release.assetForAbis(['arm64-v8a', 'armeabi-v7a']);
    expect(release.updateAvailable, isTrue);
    expect(asset?.name, 'app-arm64-v8a-release.apk');
    expect(asset?.sha256, 'a' * 64);
  });

  test('untrusted and non-APK GitHub assets are ignored', () {
    final release = parseGitHubRelease({
      'tag_name': 'v1.1.4',
      'html_url': 'https://github.com/bardia-us/niraNG/releases/tag/v1.1.4',
      'assets': [
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.com/fake.apk',
          'size': 120,
        },
        {
          'name': 'source.zip',
          'browser_download_url':
              'https://github.com/bardia-us/niraNG/releases/download/v1.1.4/source.zip',
          'size': 120,
        },
      ],
    }, '1.1.3');

    expect(release.assets, isEmpty);
    expect(release.assetForAbis(['arm64-v8a']), isNull);
  });

  test('light theme surfaces never inherit the dark canvas', () {
    expect(AppTheme.light.brightness, Brightness.light);
    expect(
      AppTheme.light.scaffoldBackgroundColor,
      isNot(AppPalette.darkCanvas),
    );
    expect(
      AppTheme.light.colorScheme.surface.computeLuminance(),
      greaterThan(AppTheme.dark.colorScheme.surface.computeLuminance()),
    );
    expect(
      AppTheme.light.dialogTheme.backgroundColor,
      isNot(AppPalette.darkCanvas),
    );
  });

  test('light full effects use only bright opaque gradient stops', () {
    final decoration = NirangVisualEffects.shellBackground(
      AppTheme.light,
      reducedEffects: false,
    );
    final gradient = decoration.gradient! as RadialGradient;

    expect(gradient.colors, isNotEmpty);
    for (final color in gradient.colors) {
      expect(color.a, 1);
      expect(color.computeLuminance(), greaterThan(.70));
    }
  });

  test('performance themes use solid backgrounds without a gradient', () {
    for (final theme in [AppTheme.lightPerformance, AppTheme.darkPerformance]) {
      final decoration = NirangVisualEffects.shellBackground(
        theme,
        reducedEffects: true,
      );
      expect(decoration.gradient, isNull);
      expect(decoration.color, theme.scaffoldBackgroundColor);
    }
  });

  test('app bars use readable status icons in both themes', () {
    expect(
      AppTheme.light.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      AppTheme.dark.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.light,
    );
  });

  testWidgets('Persian localization is RTL and translated', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (context) => Text(context.s('connect'))),
      ),
    );

    expect(find.text('اتصال'), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );
  });
}
