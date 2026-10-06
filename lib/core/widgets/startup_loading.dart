import 'dart:async';
import 'package:flutter/material.dart';
import '../localization/app_strings.dart';

enum StartupStage { device, access, settings }

/// Honest startup feedback: no fake percentage, network activity or glass
/// shader on this path. A long access check is labelled rather than hidden.
class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({required this.stage, super.key});
  final StartupStage stage;
  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen> {
  Timer? _delay;
  bool _slow = false;
  @override
  void initState() {
    super.initState();
    _watchStage();
  }

  @override
  void didUpdateWidget(StartupLoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) _watchStage();
  }

  void _watchStage() {
    _delay?.cancel();
    _slow = false;
    if (widget.stage == StartupStage.access) {
      _delay = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _slow = true);
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (widget.stage) {
      StartupStage.device => 'startupDevice',
      StartupStage.access => 'startupAccess',
      StartupStage.settings => 'startupSettings',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/nirang-mark.png',
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(height: 16),
                  Text('niraNG', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(context.s(label), textAlign: TextAlign.center),
                  if (_slow) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.s('startupNetworkWait'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
