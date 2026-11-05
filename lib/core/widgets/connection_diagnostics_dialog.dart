import 'dart:async';
import 'package:flutter/material.dart';
import '../platform/nirang_native.dart';
import 'glass_dialog.dart';
import 'clay_surface.dart';

class DiagnosticAction extends StatelessWidget {
  const DiagnosticAction({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .5 : 1,
    child: ClaySurface(
      radius: 18,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 7),
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String diagnosticLabel(String name, bool fa) => switch (name) {
  'network' => fa ? 'اینترنت اولیه · بدون VPN' : 'Underlying internet · no VPN',
  'core' => fa ? 'هسته' : 'Core',
  'tcp' => fa ? 'TCP از داخل تونل' : 'TCP through tunnel',
  _ => fa ? 'HTTPS از داخل تونل' : 'HTTPS through tunnel',
};
String diagnosticDetail(String code, bool fa) {
  final text = <String, (String, String)>{
    'direct_https_ok': (
      'Google HTTPS responded on the physical network, outside the VPN.',
      'گوگل از شبکهٔ اولیه و بیرون VPN با HTTPS پاسخ داد.',
    ),
    'direct_https_failed': (
      'Direct Google HTTPS did not succeed. Filtering or VPN restrictions may also cause this; it does not prove all internet access is down.',
      'HTTPS مستقیم گوگل موفق نبود؛ فیلترینگ یا محدودیت VPN هم می‌تواند علت باشد. این نتیجه قطع‌بودن کل اینترنت را ثابت نمی‌کند.',
    ),
    'direct_unknown': (
      'Android did not permit or complete the direct check. Result unknown.',
      'اندروید اجازه یا امکان تکمیل بررسی مستقیم را نداد؛ نتیجه نامشخص است.',
    ),
    'network_changed': (
      'The physical network changed during the check. Please retry.',
      'شبکهٔ اولیه وسط بررسی عوض شد؛ دوباره تلاش کن.',
    ),
    'network_present': (
      'Underlying network detected; internet is checked separately.',
      'شبکه شناسایی شد؛ دسترسی اینترنت جدا بررسی می‌شود.',
    ),
    'no_network': (
      'No underlying internet network detected.',
      'شبکهٔ زیرین دارای مسیر اینترنت شناسایی نشد.',
    ),
    'core_running': (
      'The active core is running.',
      'هستهٔ اتصال فعلی در حال اجراست.',
    ),
    'core_missing': (
      'The active core is not running.',
      'هستهٔ اتصال فعلی اجرا نیست.',
    ),
    'core_error': (
      'The last connection failed; check its logs.',
      'اتصال قبلی خطا داده؛ لاگ را ببین.',
    ),
    'disconnected': (
      'Connect before testing the tunnel.',
      'برای بررسی تونل ابتدا وصل شو.',
    ),
    'busy': (
      'A connection operation is in progress.',
      'اتصال در حال آماده‌سازی یا قطع است.',
    ),
    'not_tested': (
      'Not tested: no ready active connection.',
      'بررسی نشد؛ اتصال فعال و آماده‌ای نیست.',
    ),
    'no_probe_input': (
      'This JSON has no supported local SOCKS input; it was not changed.',
      'این JSON ورودی SOCKS مناسب بررسی ندارد؛ تنظیماتش تغییر نکرده.',
    ),
    'tcp_ok': (
      'The TCP destination was reached through this tunnel.',
      'اتصال TCP به مقصد از داخل همین تونل برقرار شد.',
    ),
    'tcp_failed': (
      'TCP through the tunnel failed; this alone does not identify the cause.',
      'اتصال TCP از تونل موفق نبود؛ علت قطعی از این نتیجه مشخص نیست.',
    ),
    'tcp_unavailable': (
      'Skipped HTTPS because the TCP stage did not succeed.',
      'چون مرحلهٔ TCP موفق نبود، HTTPS بررسی نشد.',
    ),
    'https_ok': (
      'HTTPS succeeded with domain and certificate verification.',
      'HTTPS با نام دامنه و تأیید گواهی موفق بود.',
    ),
    'timeout': (
      'The destination timed out; this alone does not identify the cause.',
      'مقصد در مهلت پاسخ نداد؛ این نتیجه به‌تنهایی علت را مشخص نمی‌کند.',
    ),
    'dns_failed': (
      'Probe domain lookup failed.',
      'نام دامنهٔ مقصد بررسی پیدا نشد.',
    ),
    'tls_failed': (
      'TLS handshake/certificate verification failed. Check device time and logs.',
      'دست‌دهی TLS یا تأیید گواهی شکست خورد؛ ساعت دستگاه و لاگ را ببین.',
    ),
    'proxy_unreachable': (
      'The local proxy did not accept the connection.',
      'ورودی محلی پروکسی اتصال را نپذیرفت.',
    ),
  }[code];
  return text == null
      ? (fa
            ? 'دسترسی تأیید نشد؛ علت دقیق مشخص نیست.'
            : 'Access could not be verified; the exact cause is unknown.')
      : (fa ? text.$2 : text.$1);
}

class DiagnosticResultRow extends StatelessWidget {
  const DiagnosticResultRow({
    super.key,
    required this.name,
    this.row,
    this.loading = false,
  });
  final String name;
  final Map? row;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    row?['status'] == 'pass'
                        ? Icons.check_circle_outline_rounded
                        : row?['status'] == 'fail'
                        ? Icons.error_outline_rounded
                        : Icons.help_outline_rounded,
                    color: row?['status'] == 'fail'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diagnosticLabel(name, fa),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  loading && row == null
                      ? (fa ? 'در حال بررسی…' : 'Checking…')
                      : diagnosticDetail(
                          '${row?['detail'] ?? 'not_tested'}',
                          fa,
                        ),
                ),
                if (row?['ms'] is num)
                  Text('${row!['ms']} ms', textDirection: TextDirection.ltr),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionDiagnosticsDialog extends StatefulWidget {
  const ConnectionDiagnosticsDialog({super.key});
  @override
  State<ConnectionDiagnosticsDialog> createState() =>
      _ConnectionDiagnosticsDialogState();
}

class _ConnectionDiagnosticsDialogState
    extends State<ConnectionDiagnosticsDialog> {
  final _rows = <String, Map>{};
  final _done = <String>{};
  String? _networkInfo;
  StreamSubscription<Map<dynamic, dynamic>>? _events;
  bool _running = false;
  String? _error;
  String _requestId = '';
  static const _names = ['network', 'core', 'tcp', 'https'];
  @override
  void initState() {
    super.initState();
    _events = NirangNative.events.listen((event) {
      if (!mounted || event['type'] != 'connectionDiagnostic') return;
      final data = event['data'];
      if (data is! Map ||
          data['requestId'] != _requestId ||
          data['row'] is! Map) {
        return;
      }
      final row = data['row'] as Map;
      final name = row['name'];
      if (!_names.contains(name)) return;
      setState(() {
        _rows[name] = row;
        _done.add(name);
      });
    });
    _load();
  }

  Future<void> _load() async {
    if (_running) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _running = true;
      _error = null;
      _done.clear();
      _requestId = id;
    });
    try {
      final result = await NirangNative.diagnoseConnection(requestId: id);
      if (!mounted || _requestId != id) return;
      setState(() {
        final metadata = result['metadata'];
        if (metadata is Map) {
          final kind = metadata['network'];
          final carrier = metadata['carrier'];
          final fa = Localizations.localeOf(context).languageCode == 'fa';
          _networkInfo = kind == 'wifi'
              ? (fa
                    ? 'Wi-Fi · شرکت اینترنت نامشخص'
                    : 'Wi-Fi · provider unknown')
              : kind == 'mobile'
              ? (carrier is String && carrier.isNotEmpty
                    ? (fa
                          ? 'دادهٔ موبایل · $carrier'
                          : 'Mobile data · $carrier')
                    : (fa
                          ? 'دادهٔ موبایل · اپراتور نامشخص'
                          : 'Mobile data · carrier unknown'))
              : null;
        }
        if (result['stale'] == true) {
          _rows.clear();
          _error = 'stale';
        } else {
          for (final row in result['rows'] as List? ?? []) {
            if (row is Map && _names.contains(row['name'])) {
              _rows[row['name']] = row;
            }
          }
        }
      });
    } catch (_) {
      if (mounted && _requestId == id) setState(() => _error = 'failed');
    } finally {
      if (mounted && _requestId == id) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    if (_running) {
      unawaited(NirangNative.cancelConnectionDiagnosis().catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    return NirangAlertDialog(
      icon: const Icon(Icons.troubleshoot_rounded),
      title: Text(fa ? 'بررسی اتصال' : 'Connection check'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_networkInfo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _networkInfo!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            for (final name in _names)
              DiagnosticResultRow(
                name: name,
                row: _rows[name],
                loading: _running && !_done.contains(name),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error == 'stale'
                      ? (fa
                            ? 'اتصال عوض شد؛ دوباره بررسی کن.'
                            : 'Connection changed. Please retry.')
                      : (fa
                            ? 'بررسی کامل نشد؛ دوباره تلاش کن.'
                            : 'Check could not finish. Please retry.'),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: DiagnosticAction(
                    label: fa ? 'تلاش دوباره' : 'Retry',
                    icon: Icons.refresh_rounded,
                    onPressed: _running ? null : _load,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DiagnosticAction(
                    label: fa ? 'بستن' : 'Close',
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
