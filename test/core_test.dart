import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/formatters.dart';
import 'package:nirang/core/localization/app_strings.dart';
import 'package:nirang/core/platform/native_models.dart';
import 'package:nirang/core/theme/app_theme.dart';
import 'package:nirang/core/update_checker.dart';

void main() {
  test('formats persisted byte counters without speed units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.00 MB');
    expect(formatBytes(18 * 1024 * 1024 * 1024 + 451 * 1024 * 1024), '18.4 GB');
    expect(formatBytes(2 * 1024 * 1024 * 1024 * 1024), '2.00 TB');
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
    });
    expect(updated.themeMode, 'dark');
    expect(updated.vpnMtu, 1400);
    expect(updated.remoteDns, '8.8.8.8,https://dns.google/dns-query');
    expect(updated.vpnDns, '1.1.1.1');
    expect(updated.connectionMode, 'proxy');
    expect(updated.localSocksPort, 10818);
    expect(updated.enableLocalDns, isFalse);
    expect(updated.enableFakeDns, isTrue);
  });

  test('fresh Dart settings use the v1.0.5 network defaults', () {
    const settings = NativeSettings();

    expect(settings.domainStrategy, 'AsIs');
    expect(settings.routingMode, 'bypassIran');
    expect(settings.enableIpv6, isTrue);
  });

  test('semantic release versions compare without lexical mistakes', () {
    expect(
      SemanticVersion.parse(
        'v1.0.10',
      ).compareTo(SemanticVersion.parse('1.0.4')),
      greaterThan(0),
    );
    expect(SemanticVersion.parse('v1.0.4+5').toString(), '1.0.4');
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
      expect(color.computeLuminance(), greaterThan(.75));
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
