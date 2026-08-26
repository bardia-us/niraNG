import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics.dart';
import '../../core/localization/app_strings.dart';
import '../logs/logs_screen.dart';
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

  @override
  void initState() {
    super.initState();
    NirangDiagnostics.currentFeature = 'home';
  }

  @override
  Widget build(BuildContext context) {
    final shellState = ref.watch(
      appControllerProvider.select(
        (value) => (
          ready: value.asData != null,
          loading: value.isLoading,
          error: value.hasError ? '${value.error}' : null,
        ),
      ),
    );
    ref.listen(appControllerProvider, (_, next) {
      next.whenData((app) {
        if (!_reminderQueued &&
            app.telegramEligible &&
            !app.connection.isBusy &&
            !app.isPinging) {
          _reminderQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showTelegramReminder(),
          );
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

    const pages = [
      HomeScreen(),
      ServersScreen(),
      SettingsScreen(),
      LogsScreen(),
    ];
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(.72, -.82),
          radius: 1.45,
          colors: [
            scheme.primary.withValues(alpha: .14),
            scheme.secondary.withValues(alpha: .055),
            Theme.of(context).scaffoldBackgroundColor,
          ],
          stops: const [0, .38, 1],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: scheme.surface.withValues(alpha: .58),
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: const SizedBox.expand(),
            ),
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
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: NavigationBar(
              backgroundColor: scheme.surface.withValues(alpha: .68),
              selectedIndex: _index,
              onDestinationSelected: (value) {
                NirangDiagnostics.currentFeature = const [
                  'home',
                  'servers',
                  'settings',
                  'logs',
                ][value];
                setState(() => _index = value);
                if (value == 3) {
                  ref.read(appControllerProvider.notifier).refreshLogs();
                }
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
                NavigationDestination(
                  icon: const Icon(Icons.article_outlined),
                  selectedIcon: const Icon(Icons.article_rounded),
                  label: context.s('logs'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTelegramReminder() async {
    if (!mounted) return;
    var never = false;
    final decision = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
}
