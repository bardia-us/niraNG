import 'package:flutter/material.dart';

import '../../core/registration/device_registration.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialization = widget.coordinator.initialize();
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
      if (snapshot.data == true) return widget.child;
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
      setState(() => _initialization = Future<bool>.value(true));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Consent could not be saved. Please try again.\n'
              'ذخیره رضایت انجام نشد؛ دوباره تلاش کنید.';
        });
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _exit() => widget.coordinator.exitApplication();
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
                  blur: 14,
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
                        'Before entering niraNG, this installation must be registered. After you accept, synchronization runs asynchronously over HTTPS and does not delay the VPN.',
                      ),
                      const SizedBox(height: 12),
                      const _DisclosureItem(
                        'A random, persistent installation ID',
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
                        'niraNG does not collect IMEI, hardware serial, MAC address, Android hardware ID, SIM number, SSID, files, contacts, or a hidden fingerprint.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 13),
                      const Text(
                        'برای مدیریت نصب، شناسهٔ تصادفی نصب، نام دستگاه، سازنده و مدل، نسخهٔ Android و niraNG و زمان اولین/آخرین اجرا ارسال می‌شود. IMEI، سریال، MAC، Android ID سخت‌افزاری، سیم‌کارت، Wi-Fi، فایل‌ها و مخاطبان جمع‌آوری نمی‌شوند.',
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
