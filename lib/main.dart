import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'core/localization/app_strings.dart';
import 'core/diagnostics.dart';
import 'core/platform/native_models.dart';
import 'core/platform/nirang_native.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'features/vpn/app_controller.dart';
import 'features/vpn/app_shell.dart';
import 'features/registration/registration_bootstrap.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    unawaited(
      _recordFrameworkError(details.exceptionAsString(), details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_recordFrameworkError(error.toString(), stack));
    return true;
  };
  ErrorWidget.builder = (details) => Builder(
    builder: (context) => Material(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'niraNG recovered from a UI error.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    ),
  );
  runApp(
    const ProviderScope(child: NirangRegistrationBootstrap(child: NirangApp())),
  );
}

Future<void> _recordFrameworkError(String message, StackTrace? stack) async {
  final report =
      'feature=${NirangDiagnostics.currentFeature} '
      'route=${NirangDiagnostics.currentRoute}\n'
      '$message\n${stack ?? ''}';
  try {
    await NirangNative.recordFlutterError(
      report.length <= 2000 ? report : report.substring(0, 2000),
    );
  } catch (_) {
    // The native bridge may not be ready during the earliest startup phase.
  }
}

class NirangApp extends ConsumerWidget {
  const NirangApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(
      appControllerProvider.select((value) {
        final settings = value.asData?.value.settings ?? const NativeSettings();
        return (
          themeMode: settings.themeModeValue,
          language: settings.language,
          performanceMode: settings.performanceMode,
        );
      }),
    );
    return MaterialApp(
      navigatorKey: nirangNavigatorKey,
      navigatorObservers: [nirangRouteObserver],
      title: 'niraNG',
      debugShowCheckedModeBanner: false,
      theme: appearance.performanceMode
          ? AppTheme.lightPerformance
          : AppTheme.light,
      darkTheme: appearance.performanceMode
          ? AppTheme.darkPerformance
          : AppTheme.dark,
      themeMode: appearance.themeMode,
      themeAnimationDuration: Duration(
        milliseconds: appearance.performanceMode ? 70 : 120,
      ),
      themeAnimationCurve: Curves.easeOutCubic,
      scrollBehavior: NirangScrollBehavior(
        reducedEffects: appearance.performanceMode,
      ),
      locale: Locale(appearance.language),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final theme = Theme.of(context);
        final dark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarDividerColor: theme.colorScheme.outlineVariant,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }
}
