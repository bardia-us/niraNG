import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update_checker.dart';
import '../../core/registration/device_registration.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/update_dialog.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
import 'app_controller.dart';
import 'home_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _reminderQueued = false;
  bool _performancePromptQueued = false;
  bool _startupUpdateCheckQueued = false;
  bool _startupUpdateCheckFinished = false;
  bool _whatsNewQueued = false;
  bool _whatsNewFinished = false;
  bool _autoConnectQueued = false;

  @override
  void initState() {
    super.initState();
    NirangDiagnostics.currentFeature = 'home';
    deviceAccessVerified.addListener(_onAccessVerified);
  }

  @override
  void dispose() {
    deviceAccessVerified.removeListener(_onAccessVerified);
    super.dispose();
  }

  void _onAccessVerified() => _tryAutoConnect();

  void _tryAutoConnect() {
    if (_autoConnectQueued || deviceAccessBlock.value != null) return;
    final app = ref.read(appControllerProvider).asData?.value;
    if (app == null ||
        !app.settings.autoConnect ||
        !app.connection.canConnect ||
        app.selectedServer == null) {
      return;
    }
    _autoConnectQueued = true;
    unawaited(_connectAutomatically());
  }

  Future<void> _connectAutomatically() async {
    try {
      await ref.read(appControllerProvider.notifier).connect();
    } catch (_) {
      // AppController publishes the user-facing failure state and diagnostic log.
    }
  }

  @override
  Widget build(BuildContext context) {
    final shellState = ref.watch(
      appControllerProvider.select(
        (value) => (
          ready: value.asData != null,
          loading: value.isLoading,
          error: value.hasError
              ? userFacingError(value.error!, persian: false).combined
              : null,
          performanceMode:
              value.asData?.value.settings.performanceMode ?? false,
        ),
      ),
    );
    ref.listen(appControllerProvider, (_, next) {
      next.whenData((app) {
        if (!_performancePromptQueued &&
            !app.settings.performanceModePrompted) {
          _performancePromptQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showPerformanceModePrompt(),
          );
          return;
        }
        if (deviceAccessVerified.value > 0) _tryAutoConnect();
        if (!_startupUpdateCheckQueued &&
            app.settings.performanceModePrompted &&
            !app.connection.isBusy) {
          _startupUpdateCheckQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _checkForStartupUpdate(app.appVersion),
          );
          return;
        }
        if (_startupUpdateCheckFinished && !_whatsNewQueued) {
          _whatsNewQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showWhatsNewIfNeeded(app),
          );
          return;
        }
        if (_whatsNewFinished) {
          _queueTelegramReminder(app);
        }
      });
    });

    if (!shellState.ready && shellState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!shellState.ready) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 12),
                Text(
                  '${context.s('operationFailed')}\n${shellState.error ?? context.s('unknown')}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(appControllerProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.s('refresh')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    const pages = [HomeScreen(), ServersScreen(), SettingsScreen()];
    final theme = Theme.of(context);
    final navigationBar = NavigationBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedIndex: _index,
      onDestinationSelected: (value) {
        NirangDiagnostics.currentFeature = const [
          'home',
          'servers',
          'settings',
        ][value];
        setState(() => _index = value);
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: context.s('home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.dns_outlined),
          selectedIcon: const Icon(Icons.dns_rounded),
          label: context.s('servers'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings_rounded),
          label: context.s('settings'),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const GlassSurface(
          radius: 0,
          showShadow: false,
          child: SizedBox.expand(),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/branding/nirang-logo-concept.png',
                width: 30,
                height: 30,
                cacheWidth: 60,
                cacheHeight: 60,
              ),
            ),
            const SizedBox(width: 10),
            const Text('niraNG'),
          ],
        ),
      ),
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          const _TransientStatusBanner(),
        ],
      ),
      bottomNavigationBar: GlassSurface(
        radius: 0,
        showShadow: false,
        child: navigationBar,
      ),
    );
  }

  Future<void> _showPerformanceModePrompt() async {
    if (!mounted) return;
    final enable = await showNirangDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => NirangAlertDialog(
        icon: const Icon(Icons.bolt_rounded),
        title: Text(context.s('performanceMode')),
        content: Text(context.s('performanceModeDialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.s('keepFullEffects')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.s('enable')),
          ),
        ],
      ),
    );
    if (!mounted || enable == null) return;
    await ref.read(appControllerProvider.notifier).updateSettings({
      'performanceMode': enable,
      'performanceModePrompted': true,
    });
  }

  Future<void> _showTelegramReminder() async {
    if (!mounted) return;
    var never = false;
    final decision = await showNirangDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => NirangAlertDialog(
          icon: const Icon(Icons.campaign_outlined),
          title: Text(context.s('joinTelegramTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.s('joinTelegramBody')),
              CheckboxListTile(
                value: never,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => never = value ?? false),
                title: Text(context.s('dontShowAgain')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'later'),
              child: Text(context.s('later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'join'),
              child: Text(context.s('joinTelegram')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || decision == null) return;
    final controller = ref.read(appControllerProvider.notifier);
    if (decision == 'join') {
      await controller.openTelegram();
    }
    await controller.recordTelegramDecision(never ? 'never' : 'later');
  }

  Future<void> _checkForStartupUpdate(String currentVersion) async {
    if (!mounted) return;
    try {
      final release = await const GitHubUpdateChecker().check(currentVersion);
      if (!mounted || !release.updateAvailable) return;
      await showUpdateOptionsDialog(context, release);
    } catch (_) {
      // Startup checks are intentionally silent when offline or unavailable.
    } finally {
      _startupUpdateCheckFinished = true;
      final app = ref.read(appControllerProvider).asData?.value;
      if (mounted && app != null && !_whatsNewQueued) {
        _whatsNewQueued = true;
        unawaited(_showWhatsNewIfNeeded(app));
      }
    }
  }

  Future<void> _showWhatsNewIfNeeded(AppSnapshot app) async {
    try {
      if (app.appBuild <= 0 || app.whatsNewSeenBuild >= app.appBuild) return;
      final notes = await const GitHubUpdateChecker().releaseNotes(
        app.appVersion,
      );
      final body = notes.forLanguage(app.settings.language).trim();
      if (!mounted || body.isEmpty) return;
      final persian = app.settings.language == 'fa';
      final accepted = await showNirangDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => NirangAlertDialog(
          icon: const Icon(Icons.auto_awesome_rounded),
          title: Text(persian ? 'چه چیزهایی جدید است؟' : "What's new"),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: SelectableText(
                body,
                textDirection: persian ? TextDirection.rtl : TextDirection.ltr,
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(persian ? 'باشه' : 'Got it'),
            ),
          ],
        ),
      );
      if (accepted == true && mounted) {
        await ref.read(appControllerProvider.notifier).recordWhatsNewSeen();
      }
    } catch (_) {
      // Do not mark this build as seen when GitHub is temporarily unavailable.
    } finally {
      _whatsNewFinished = true;
      final current = ref.read(appControllerProvider).asData?.value;
      if (mounted && current != null) _queueTelegramReminder(current);
    }
  }

  void _queueTelegramReminder(AppSnapshot app) {
    if (_reminderQueued ||
        !app.settings.performanceModePrompted ||
        !app.telegramEligible ||
        app.connection.isBusy ||
        app.isPinging) {
      return;
    }
    _reminderQueued = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showTelegramReminder(),
    );
  }
}

class _TransientStatusBanner extends ConsumerWidget {
  const _TransientStatusBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(
      appControllerProvider.select((value) => value.asData?.value.notice),
    );
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final color = switch (notice?.tone) {
      NoticeTone.success => semantic.success,
      NoticeTone.error => scheme.error,
      _ => scheme.primary,
    };
    return PositionedDirectional(
      start: 16,
      end: 16,
      bottom: 12,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: notice == null
              ? const SizedBox.shrink()
              : Material(
                  key: ValueKey(notice.id),
                  color: Color.alphaBlend(
                    color.withValues(alpha: .14),
                    scheme.surfaceContainerHigh,
                  ),
                  elevation: 2,
                  borderRadius: BorderRadius.circular(13),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (notice.tone == NoticeTone.processing)
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          )
                        else
                          Icon(
                            notice.tone == NoticeTone.success
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            size: 18,
                            color: color,
                          ),
                        const SizedBox(width: 9),
                        Flexible(child: Text(notice.message)),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
