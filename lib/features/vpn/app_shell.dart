import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import '../../core/diagnostics.dart';
import '../../core/interaction_feedback.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update_checker.dart';
import '../../core/registration/device_registration.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/menu_activity.dart';
import '../../core/widgets/release_notes_markdown.dart';
import '../../core/widgets/update_dialog.dart';
import '../../core/widgets/telegram_mark.dart';
import '../../core/widgets/startup_loading.dart';
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
  final _pageController = PageController();
  bool _tabAnimating = false;
  int _tabAnimationGeneration = 0;
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
    startupNetworkReady.addListener(_onNetworkReady);
    MenuActivity.isOpen.addListener(_onMenuChanged);
    // Preparation may have completed behind the access screen, before these
    // listeners existed. Process that current state once as well as updates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appControllerProvider).whenData(_handleStartupState);
      }
    });
  }

  @override
  void dispose() {
    deviceAccessVerified.removeListener(_onAccessVerified);
    startupNetworkReady.removeListener(_onNetworkReady);
    MenuActivity.isOpen.removeListener(_onMenuChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _pageChanged(int value) {
    if (_tabAnimating || value == _index) return;
    _activatePage(value);
  }

  bool _isPageVisible(int index) {
    if (!_pageController.hasClients) return index == _index;
    final page = _pageController.page;
    // PageView uses full-width pages. Keep BOTH partially visible pages live,
    // including the intermediate page when Home -> Settings skips a tab.
    // Read current scroll metrics, not _index (which changes before animation).
    return page == null ? index == _index : (page - index).abs() < 1;
  }

  void _activatePage(int value) {
    NirangDiagnostics.currentFeature = const [
      'home',
      'servers',
      'settings',
    ][value];
    setState(() => _index = value);
    final mode =
        ref.read(appControllerProvider).asData?.value.settings.feedbackMode ??
        'off';
    unawaited(InteractionFeedback.playNavigation(mode));
  }

  Future<void> _selectPage(int value) async {
    if (MenuActivity.isOpen.value ||
        value == _index ||
        !_pageController.hasClients) {
      return;
    }
    _activatePage(value);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(value);
      return;
    }
    _tabAnimating = true;
    // An interrupted DrivenScrollActivity also reports shouldIgnorePointer
    // true; Flutter doesn't reset our early unlock when true stays true.
    _pageController.position.context.setIgnorePointer(true);
    final generation = ++_tabAnimationGeneration;
    try {
      await _pageController.animateToPage(
        value,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (mounted && generation == _tabAnimationGeneration) {
        _tabAnimating = false;
      }
    }
  }

  void _onAccessVerified() => _tryAutoConnect();

  void _onMenuChanged() {
    if (!mounted || MenuActivity.isOpen.value) return;
    _queueStartupWork(
      () => ref.read(appControllerProvider).whenData(_handleStartupState),
    );
  }

  void _onNetworkReady() {
    if (startupNetworkReady.value) {
      ref.read(appControllerProvider).whenData(_handleStartupState);
    }
  }

  bool _settleQueued = false;
  bool _pagerDragging = false;
  bool _onPagerScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      _pagerDragging = notification.dragDetails != null;
    } else if (notification is ScrollUpdateNotification) {
      _pagerDragging = notification.dragDetails != null;
      if (!_pagerDragging) {
        _unlockDestination();
        _settleLastPixels(notification.scrollDelta ?? 0);
      }
    } else if (notification is ScrollEndNotification) {
      _pagerDragging = false;
    }
    return false;
  }

  void _unlockDestination() {
    if (!_pageController.hasClients || MenuActivity.isOpen.value) return;
    final page = _pageController.page;
    if (page == null || (page - _index).abs() > .2) return;
    // ScrollContext is Flutter's public pointer-policy interface. Let the
    // destination accept touches once 80% is visible, without stopping the
    // animation or reaching into ScrollableState's protected implementation.
    _pageController.position.context.setIgnorePointer(false);
  }

  void _settleLastPixels(double delta) {
    if (!_pageController.hasClients || _settleQueued) return;
    final position = _pageController.position;
    // Use public scroll notifications, not ScrollPosition's protected activity.
    // A slow ballistic tail may finish; a fast fling/active drag must not.
    if (!position.isScrollingNotifier.value || _pagerDragging) return;
    final page = _pageController.page;
    if (page == null) return;
    final target = _tabAnimating ? _index : page.round();
    if (!_tabAnimating && (delta.abs() > 2 || delta * (target - page) < 0)) {
      return;
    }
    final remaining = (page - target).abs() * position.viewportDimension;
    if (remaining > 2) return;
    _settleQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settleQueued = false;
      if (!mounted || !_pageController.hasClients) return;
      final current = _pageController.position;
      if (_pagerDragging || !current.isScrollingNotifier.value) return;
      final currentPage = _pageController.page!;
      if ((currentPage - target).abs() * current.viewportDimension <= 2) {
        _pageController.jumpToPage(target);
      }
    });
  }

  void _queueStartupWork(VoidCallback work) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) work();
    });
    // A preloaded, idle shell otherwise has no next frame to run this callback.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _handleStartupState(AppSnapshot app) {
    if (!app.settings.performanceModePrompted) {
      if (!_performancePromptQueued) {
        _performancePromptQueued = true;
        _queueStartupWork(_showPerformanceModePrompt);
      }
      return;
    }
    if (deviceAccessVerified.value > 0) _tryAutoConnect();
    if (!startupNetworkReady.value) return;
    if (!_startupUpdateCheckQueued && !app.connection.isBusy) {
      _startupUpdateCheckQueued = true;
      _queueStartupWork(() => _checkForStartupUpdate(app.appVersion));
      return;
    }
    if (_startupUpdateCheckFinished && !_whatsNewQueued) {
      _whatsNewQueued = true;
      _queueStartupWork(() => _showWhatsNewIfNeeded(app));
      return;
    }
    if (_whatsNewFinished) _queueTelegramReminder(app);
  }

  void _tryAutoConnect() {
    if (!startupNetworkReady.value ||
        _autoConnectQueued ||
        deviceAccessBlock.value != null ||
        deviceUpdateRequired.value) {
      return;
    }
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
      next.whenData(_handleStartupState);
    });

    if (!shellState.ready && shellState.loading) {
      return const StartupLoadingScreen(stage: StartupStage.settings);
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
      onDestinationSelected: _selectPage,
      destinations: [
        _ElasticDestination(
          child: NavigationDestination(
            icon: const Icon(Icons.home_outlined, size: 28),
            selectedIcon: const Icon(Icons.home_rounded, size: 28),
            label: context.s('home'),
          ),
        ),
        _ElasticDestination(
          child: NavigationDestination(
            icon: const Icon(Icons.dns_outlined, size: 28),
            selectedIcon: const Icon(Icons.dns_rounded, size: 28),
            label: context.s('servers'),
          ),
        ),
        _ElasticDestination(
          child: NavigationDestination(
            icon: const Icon(Icons.settings_outlined, size: 28),
            selectedIcon: const Icon(Icons.settings_rounded, size: 28),
            label: context.s('settings'),
          ),
        ),
      ],
    );
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: FrostedSurface(
          opaque: _index == 1,
          sigma: 8,
          tintAlpha: theme.brightness == Brightness.dark ? .45 : .64,
          child: const SizedBox.expand(),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/branding/nirang-mark.png',
                width: 30,
                height: 30,
              ),
            ),
            const SizedBox(width: 10),
            const Text('niraNG'),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: NirangVisualEffects.shellBackground(
          theme,
          reducedEffects: shellState.performanceMode,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: MenuActivity.isOpen,
                builder: (context, menuOpen, _) =>
                    NotificationListener<ScrollNotification>(
                      onNotification: _onPagerScroll,
                      child: PageView(
                        controller: _pageController,
                        physics: menuOpen
                            ? const NeverScrollableScrollPhysics()
                            : const _TabScrollPhysics(),
                        onPageChanged: _pageChanged,
                        children: [
                          for (var index = 0; index < pages.length; index++)
                            _RetainedPage(
                              key: ValueKey(index),
                              child: glass.GlassMotionSync(
                                motion: _pageController,
                                shouldRefresh: () => _isPageVisible(index),
                                child: IgnorePointer(
                                  ignoring: index != _index,
                                  child: pages[index],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
              ),
              const _TransientStatusBanner(),
            ],
          ),
        ),
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
    final current = ref.read(appControllerProvider).asData?.value;
    if (current == null ||
        MenuActivity.isOpen.value ||
        deviceAccessBlock.value != null ||
        deviceUpdateRequired.value ||
        !current.telegramEligible ||
        !current.connection.isConnected ||
        current.connection.isBusy) {
      _reminderQueued = false;
      return;
    }
    final optional = current.telegramStage == 'second';
    if (optional) {
      if (!current.hasCompletedPing || current.isPinging) {
        _reminderQueued = false;
        return;
      }
    }
    final controller = ref.read(appControllerProvider.notifier);
    final decision = await showNirangDialog<String>(
      context: context,
      barrierDismissible: false,
      onShown: optional
          ? () {
              // Only consume the once-only reminder after its first visible frame.
              unawaited(
                controller
                    .recordTelegramDecision('second_shown')
                    .catchError((Object _) {}),
              );
            }
          : null,
      builder: (dialogContext) => NirangAlertDialog(
        icon: const TelegramMark(size: 32),
        title: Text(
          optional ? 'اخبار niraNG در تلگرام' : context.s('joinTelegramTitle'),
        ),
        content: optional
            ? const Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'برای اطلاع از نسخه‌های جدید، اخبار و راهنمای برنامه، حتماً عضو کانال تلگرام شوید.',
                ),
              )
            : Text(context.s('joinTelegramBody')),
        actions: [
          if (optional)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'later'),
              child: const Text('بعداً'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'join'),
            child: Text(
              optional ? 'عضویت در تلگرام' : context.s('joinTelegram'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || decision == null) return;
    if (decision == 'join') {
      try {
        await controller.openTelegram();
        if (!optional) await controller.recordTelegramDecision('joined');
      } catch (error) {
        if (!mounted) return;
        _reminderQueued = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userFacingError(
                error,
                persian: Localizations.localeOf(context).languageCode == 'fa',
              ).combined,
            ),
          ),
        );
      }
    }
  }

  Future<void> _checkForStartupUpdate(String currentVersion) async {
    if (!mounted) return;
    try {
      final release = await const GitHubUpdateChecker(
        requestTimeout: Duration(seconds: 7),
      ).check(currentVersion);
      if (!mounted || !release.updateAvailable) return;
      await showUpdateOptionsDialog(context, release);
    } catch (_) {
      // Startup checks are intentionally silent when offline or unavailable.
    } finally {
      _startupUpdateCheckFinished = true;
      final app = mounted
          ? ref.read(appControllerProvider).asData?.value
          : null;
      if (app != null && !_whatsNewQueued) {
        _whatsNewQueued = true;
        unawaited(_showWhatsNewIfNeeded(app));
      }
    }
  }

  Future<void> _showWhatsNewIfNeeded(AppSnapshot app) async {
    try {
      if (!shouldShowWhatsNew(
        appBuild: app.appBuild,
        seenBuild: app.whatsNewSeenBuild,
        upgradedFromBuild: app.whatsNewUpgradeFromBuild,
      )) {
        return;
      }
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
          content: Directionality(
            textDirection: persian ? TextDirection.rtl : TextDirection.ltr,
            child: ReleaseNotesMarkdown(data: body),
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
      final current = mounted
          ? ref.read(appControllerProvider).asData?.value
          : null;
      if (current != null) _queueTelegramReminder(current);
    }
  }

  void _queueTelegramReminder(AppSnapshot app) {
    if (_reminderQueued ||
        MenuActivity.isOpen.value ||
        deviceAccessBlock.value != null ||
        deviceUpdateRequired.value ||
        !app.settings.performanceModePrompted ||
        !app.telegramEligible ||
        !app.connection.isConnected ||
        app.connection.isBusy ||
        app.isPinging ||
        (app.telegramStage == 'second' && !app.hasCompletedPing)) {
      return;
    }
    _reminderQueued = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showTelegramReminder(),
    );
  }
}

/// Horizontal and vertical recognizers compete in Flutter's gesture arena;
/// once a list's vertical drag wins, this pager cannot steal that gesture.
class _TabScrollPhysics extends PageScrollPhysics {
  const _TabScrollPhysics({super.parent});

  @override
  _TabScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _TabScrollPhysics(parent: buildParent(ancestor));

  @override
  double get minFlingVelocity => 650;

  @override
  double get minFlingDistance => 32;

  @override
  double get dragStartDistanceMotionThreshold => 28;
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({required this.child, super.key});
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ElasticDestination extends StatefulWidget {
  const _ElasticDestination({required this.child});
  final Widget child;
  @override
  State<_ElasticDestination> createState() => _ElasticDestinationState();
}

class _ElasticDestinationState extends State<_ElasticDestination> {
  bool _pressed = false;
  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _press(true),
    onPointerUp: (_) => _press(false),
    onPointerCancel: (_) => _press(false),
    child: AnimatedScale(
      scale: _pressed ? .94 : 1,
      duration:
          (MediaQuery.disableAnimationsOf(context) ||
              MediaQuery.highContrastOf(context))
          ? Duration.zero
          : Duration(milliseconds: _pressed ? 90 : 260),
      curve: _pressed ? Curves.easeOutCubic : Curves.elasticOut,
      child: widget.child,
    ),
  );
}

bool shouldShowWhatsNew({
  required int appBuild,
  required int seenBuild,
  required int upgradedFromBuild,
}) =>
    appBuild > 0 &&
    upgradedFromBuild > 0 &&
    upgradedFromBuild < appBuild &&
    seenBuild < appBuild;

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
