import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/registration/device_registration.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_surface.dart';

class NirangRegistrationBootstrap extends StatefulWidget {
  const NirangRegistrationBootstrap({
    required this.child,
    this.coordinator = const NativeDeviceRegistrationCoordinator(),
    super.key,
  });

  final Widget child;
  final DeviceRegistrationCoordinator coordinator;

  @override
  State<NirangRegistrationBootstrap> createState() =>
      _NirangRegistrationBootstrapState();
}

class _NirangRegistrationBootstrapState
    extends State<NirangRegistrationBootstrap> {
  late Future<bool> _initialization;
  bool _accepting = false;
  bool _backgroundVerificationQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialization = _verifyAccess();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return _registrationApp(
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      final error = snapshot.error;
      if (_isBlocked(error)) markDeviceAccessBlocked(_platformMessage(error));
      if (snapshot.data == true) {
        _queueBackgroundVerification();
        return ValueListenableBuilder<String?>(
          valueListenable: deviceAccessBlock,
          child: widget.child,
          builder: (context, blocked, child) => blocked == null
              ? child!
              : _registrationApp(
                  BlockedAccessScreen(onRetry: _retry, onExit: _exit),
                ),
        );
      }
      if (error != null) {
        return _registrationApp(
          _isBlocked(error)
              ? BlockedAccessScreen(onRetry: _retry, onExit: _exit)
              : AccessVerificationScreen(
                  message:
                      _platformMessage(error) ??
                      'Access status could not be verified.',
                  onRetry: _retry,
                  onExit: _exit,
                ),
        );
      }
      return _registrationApp(
        RegistrationConsentScreen(
          accepting: _accepting,
          error: _error,
          onAccept: _accept,
          onExit: _exit,
        ),
      );
    },
  );

  Future<bool> _verifyAccess() async {
    final accepted = await widget.coordinator.initialize();
    return accepted;
  }

  void _queueBackgroundVerification() {
    if (_backgroundVerificationQueued) return;
    _backgroundVerificationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.coordinator.verifyAccess();
        clearDeviceAccessBlocked();
        markDeviceAccessVerified();
      } catch (error) {
        if (_isBlocked(error)) markDeviceAccessBlocked(_platformMessage(error));
        // Offline/startup API failures never keep the local UI on a loading page.
      }
    });
  }

  void _retry() {
    _retryAccess();
  }

  Future<void> _retryAccess() async {
    try {
      await widget.coordinator.verifyAccess();
      clearDeviceAccessBlocked();
      markDeviceAccessVerified();
    } catch (error) {
      if (_isBlocked(error)) markDeviceAccessBlocked(_platformMessage(error));
    }
  }

  Widget _registrationApp(Widget home) => MaterialApp(
    title: 'niraNG — Device registration',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    home: home,
  );

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.coordinator.accept();
      if (!mounted) return;
      setState(() {
        _backgroundVerificationQueued = false;
        _initialization = Future<bool>.value(true);
      });
    } catch (error) {
      if (mounted) {
        if (_isBlocked(error)) {
          markDeviceAccessBlocked(_platformMessage(error));
          setState(() => _initialization = Future<bool>.error(error));
          return;
        }
        final nativeMessage = error is PlatformException
            ? error.message?.trim()
            : null;
        setState(() {
          _error = nativeMessage?.isNotEmpty == true
              ? nativeMessage
              : 'Registration could not be completed. Please try again.\n'
                    'ثبت دستگاه کامل نشد؛ دوباره تلاش کنید.';
        });
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _exit() => widget.coordinator.exitApplication();

  static bool _isBlocked(Object? error) =>
      error is PlatformException &&
      (error.code == 'blocked' ||
          error.message?.contains('blocked_by_administrator') == true ||
          error.message?.toLowerCase().contains('blocked') == true);

  static String? _platformMessage(Object? error) =>
      error is PlatformException ? error.message?.trim() : null;
}

class BlockedAccessScreen extends StatelessWidget {
  const BlockedAccessScreen({
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => _AccessMessageCard(
    icon: Icons.block_rounded,
    title: 'Access blocked',
    message:
        'دسترسی شما مسدود شده است.\n'
        'برای اطلاع از دلیل مسدود شدن می‌توانید به تلگرام سازنده مراجعه کنید.',
    actions: [
      TextButton(onPressed: onExit, child: const Text('Exit')),
      OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      FilledButton.icon(
        onPressed: () async {
          try {
            await NirangNative.openTelegram();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Telegram link is unavailable.')),
              );
            }
          }
        },
        icon: const Icon(Icons.send_rounded),
        label: const Text('Telegram'),
      ),
    ],
  );
}

class AccessVerificationScreen extends StatelessWidget {
  const AccessVerificationScreen({
    required this.message,
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => _AccessMessageCard(
    icon: Icons.cloud_off_rounded,
    title: 'Access check failed',
    message: message,
    actions: [
      TextButton(onPressed: onExit, child: const Text('Exit')),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

class _AccessMessageCard extends StatelessWidget {
  const _AccessMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: NirangVisualEffects.shellBackground(
        theme,
        reducedEffects: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: GlassSurface(
                  radius: 24,
                  blur: GlassSurface.liquidBlur,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistrationConsentScreen extends StatelessWidget {
  const RegistrationConsentScreen({
    required this.accepting,
    required this.error,
    required this.onAccept,
    required this.onExit,
    super.key,
  });

  final bool accepting;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: NirangVisualEffects.shellBackground(
        theme,
        reducedEffects: false,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: GlassSurface(
                  radius: 24,
                  blur: GlassSurface.liquidBlur,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: .72),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.phonelink_setup_rounded,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              'niraNG device registration',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Before entering niraNG, this installation must be registered and its access status verified securely over HTTPS.',
                      ),
                      const SizedBox(height: 12),
                      const _DisclosureItem(
                        'A random, persistent installation ID',
                      ),
                      const _DisclosureItem(
                        'A one-way device key derived from ANDROID_ID; the raw ANDROID_ID is never sent or stored by niraNG',
                      ),
                      const _DisclosureItem(
                        'Device Name, or Manufacturer + Model as fallback',
                      ),
                      const _DisclosureItem('Manufacturer and Model'),
                      const _DisclosureItem('Android version'),
                      const _DisclosureItem('niraNG version'),
                      const _DisclosureItem('First seen and last seen times'),
                      const SizedBox(height: 13),
                      Text(
                        'niraNG does not collect IMEI, hardware serial, MAC address, raw ANDROID_ID, SIM number, SSID, files, contacts, or a hidden hardware fingerprint.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 13),
                      const Text(
                        'برای مدیریت دسترسی، شناسهٔ نصب و یک Device Key یک‌طرفه مشتق‌شده از ANDROID_ID ارسال می‌شود؛ مقدار خام ANDROID_ID هرگز ارسال یا ذخیره نمی‌شود. IMEI، سریال، MAC، سیم‌کارت، Wi-Fi، فایل‌ها و مخاطبان جمع‌آوری نمی‌شوند.',
                        textDirection: TextDirection.rtl,
                      ),
                      if (error case final message?) ...[
                        const SizedBox(height: 13),
                        Text(
                          message,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: accepting ? null : onExit,
                            child: const Text('Exit'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: accepting ? null : onAccept,
                            icon: accepting
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: const Text('Accept & Continue'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclosureItem extends StatelessWidget {
  const _DisclosureItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
