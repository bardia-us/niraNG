import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui_lag_capture.dart';
import '../../core/widgets/live_liquid_glass.dart';
import '../vpn/app_controller.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/connection_diagnostics_dialog.dart';

// Memory-only draft: leaving Feedback to reproduce UI lag must retain the text.
// No configuration attachment consent or device data is retained here.
String _feedbackMessageDraft = '';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});
  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _message = TextEditingController();
  Map<dynamic, dynamic>? _diagnostics;
  Map<dynamic, dynamic> _subject = {};
  bool _checking = false, _sending = false, _configLoading = false;
  bool _includeDiagnostics = true, _includeConfig = false, _sent = false;
  String? _error, _contextError;
  String _reportId = _uuid();
  int _contextRevision = 0;
  bool _startingCapture = false;
  final _capture = UiLagCapture.instance;
  Map<String, Object?>? _lastUiResult;
  String t(String en, String fa) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
  static String _uuid() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  void _changed() {
    _reportId = _uuid();
    _sent = false;
    _error = null;
  }

  @override
  void initState() {
    super.initState();
    _message.text = _feedbackMessageDraft;
    _lastUiResult = _capture.result;
    _capture.addListener(_captureChanged);
    _loadSubject();
    if (_capture.active || _capture.finishing || _capture.result != null) {
      _includeDiagnostics = false;
    } else {
      _check();
    }
  }

  void _captureChanged() {
    if (!mounted) return;
    setState(() {
      if (!identical(_lastUiResult, _capture.result)) {
        _lastUiResult = _capture.result;
        _changed();
      }
    });
  }

  Future<void> _startCapture() async {
    if (_startingCapture || _capture.active || _capture.finishing) return;
    setState(() => _startingCapture = true);
    // Cancel the existing connection probe so it does not add unrelated work.
    if (_checking) {
      await NirangNative.cancelConnectionDiagnosis().catchError((_) {});
    }
    Map<dynamic, dynamic> device = {};
    try {
      device = await NirangNative.uiCaptureContext().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // Unknown native fields remain unknown; Flutter timing still works.
    }
    if (!mounted) return;
    _capture.start(
      view: View.of(context),
      device: device,
      performanceMode:
          ref
              .read(appControllerProvider)
              .asData
              ?.value
              .settings
              .performanceMode ??
          true,
      glassReady: liveGlassReadyListenable.value,
    );
    setState(() {
      _startingCapture = false;
      _includeDiagnostics = false;
      _changed();
    });
    Navigator.of(context).pop();
  }

  Future<void> _loadSubject() async {
    final revision = ++_contextRevision;
    setState(() => _configLoading = true);
    try {
      final data = await NirangNative.feedbackContext(
        includeConfig: _includeConfig,
      );
      if (!mounted || revision != _contextRevision) return;
      setState(() {
        _subject = data;
        _contextError = null;
        _changed();
      });
    } catch (_) {
      if (mounted && revision == _contextRevision) {
        setState(() {
          _contextError = 'context';
          _subject = {};
        });
      }
    } finally {
      if (mounted && revision == _contextRevision) {
        setState(() => _configLoading = false);
      }
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _changed();
    });
    try {
      final data = await NirangNative.diagnoseConnection();
      if (mounted) setState(() => _diagnostics = data);
    } catch (_) {
      if (mounted) setState(() => _diagnostics = null);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Map<String, Object?> _payload() => {
    'report_id': _reportId,
    'message': _message.text.trim(),
    if (_capture.result != null) 'ui_metrics': _capture.result,
    if (_includeDiagnostics &&
        _diagnostics != null &&
        _diagnostics!['stale'] != true)
      'diagnostics': _diagnostics,
    if (_subject['selected_server'] is Map)
      'selected_server': _subject['selected_server'],
    if (_includeConfig && _subject['selected_config'] is String)
      'selected_config': _subject['selected_config'],
  };
  String _exportText() {
    final data = _payload();
    return 'niraNG feedback\n${_message.text.trim()}\n\n${const JsonEncoder.withIndent('  ').convert(data)}';
  }

  Future<void> _send() async {
    if (_sending || _sent) return;
    final data = _payload();
    if (utf8.encode(_message.text.trim()).length > 4000) {
      setState(() => _error = 'long');
      return;
    }
    if (_message.text.trim().isEmpty &&
        !data.containsKey('diagnostics') &&
        !data.containsKey('ui_metrics')) {
      setState(() => _error = 'empty');
      return;
    }
    if (_includeConfig && _subject['selected_config'] == null) {
      setState(() => _error = 'config');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await NirangNative.submitFeedback(data);
      if (result['ok'] != true) {
        throw PlatformException(code: 'feedback_failed');
      }
      _feedbackMessageDraft = '';
      if (mounted) setState(() => _sent = true);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'feedback_failed');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    if (!_sent) {
      // Bound even unusual input containing long combining-character sequences.
      _feedbackMessageDraft = String.fromCharCodes(
        _message.text.runes.take(4000),
      );
    }
    if (_checking) {
      unawaited(NirangNative.cancelConnectionDiagnosis().catchError((_) {}));
    }
    _capture.removeListener(_captureChanged);
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = utf8.encode(_message.text.trim()).length;
    final subject = _subject['selected_server'];
    final error = switch (_error) {
      'long' => t(
        'Keep the message within 4000 UTF-8 bytes.',
        'متن را کوتاه‌تر کن؛ حداکثر ۴۰۰۰ بایت.',
      ),
      'empty' => t(
        'Write a message or attach a connection check or UI capture.',
        'توضیح بنویس یا بررسی اتصال یا گزارش لگ را پیوست کن.',
      ),
      'config' => t(
        'Selected configuration is unavailable. Retry loading it or turn off its attachment.',
        'کانفیگ انتخابی آماده نیست؛ دوباره دریافت کن یا پیوست آن را خاموش کن.',
      ),
      'feedback_unavailable' => t(
        'The server feedback feature is not available yet. Keep your text and retry after the panel update.',
        'قابلیت گزارش روی سرور هنوز آماده نیست؛ متن حفظ شده، بعد از آپدیت پنل دوباره بفرست.',
      ),
      'feedback_too_large' => t(
        'Report is too large. Turn off the configuration attachment or shorten the message.',
        'حجم گزارش زیاد است؛ پیوست کانفیگ را خاموش کن یا متن را کوتاه‌تر کن.',
      ),
      'feedback_rate_limited' => t(
        'Too many reports. Please try later; your text is kept.',
        'تعداد گزارش‌ها زیاد شده؛ کمی بعد بفرست. متن حفظ شده.',
      ),
      'feedback_conflict' => t(
        'Report changed during a retry. Edit the message and send it again.',
        'گزارش در تلاش مجدد عوض شده؛ متن را ویرایش کن و دوباره بفرست.',
      ),
      'feedback_unauthorized' => t(
        'The server did not authorize this report. Check access and retry.',
        'سرور اجازهٔ ارسال این گزارش را نداد؛ دسترسی را بررسی کن.',
      ),
      _ => t(
        'Report was not delivered. Your text is kept; retry or copy it.',
        'گزارش ارسال نشد؛ متن حفظ شده، دوباره تلاش کن یا کپی بگیر.',
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Feedback & problem report', 'ارسال فیدبک و گزارش مشکل')),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'Describe anything: a connection issue, UI problem or suggestion. Your report goes to this service’s administrator.',
                  'مشکل اتصال، ایراد ظاهر یا پیشنهادت را آزادانه بنویس؛ گزارش به مدیر همین سرویس می‌رسد.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _uiCaptureCard(),
              const SizedBox(height: 16),
              GlassSurface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t('Your message (optional)', 'توضیحات تو (اختیاری)'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _message,
                      enabled: !_sending,
                      minLines: 6,
                      maxLines: 12,
                      maxLength: 4000,
                      onChanged: (_) => setState(_changed),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: t(
                          'What happened, and what did you expect? You can describe visual issues here too.',
                          'چه اتفاقی افتاد و چه انتظاری داشتی؟ مشکل ظاهری را هم همین‌جا توضیح بده.',
                        ),
                        counterText: '$bytes / 4000 UTF-8',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        t('Attach connection check', 'پیوست بررسی اتصال'),
                      ),
                      subtitle: Text(
                        t(
                          'Version, core and network/TCP/HTTPS results.',
                          'نسخه، هسته و نتیجهٔ شبکه، TCP و HTTPS.',
                        ),
                      ),
                      value: _includeDiagnostics,
                      onChanged: _sending
                          ? null
                          : (v) => setState(() {
                              _includeDiagnostics = v;
                              _changed();
                            }),
                    ),
                    if (_includeDiagnostics) ...[
                      for (final name in const [
                        'network',
                        'core',
                        'tcp',
                        'https',
                      ])
                        DiagnosticResultRow(
                          name: name,
                          loading: _checking,
                          row: (_diagnostics?['rows'] as List? ?? [])
                              .whereType<Map>()
                              .where((r) => r['name'] == name)
                              .firstOrNull,
                        ),
                      if (!_checking &&
                          (_diagnostics == null ||
                              _diagnostics!['stale'] == true))
                        Text(
                          t(
                            'Check unavailable or connection changed. You can still send a text-only report.',
                            'بررسی آماده نیست یا اتصال عوض شده؛ می‌توانی فقط متن بفرستی.',
                          ),
                        ),
                      DiagnosticAction(
                        label: t('Refresh check', 'تازه‌کردن بررسی'),
                        icon: Icons.refresh_rounded,
                        onPressed:
                            _checking ||
                                _sending ||
                                _capture.active ||
                                _capture.finishing
                            ? null
                            : _check,
                      ),
                    ],
                    const Divider(height: 28),
                    if (subject is Map)
                      Text(
                        '${t('Selected profile', 'کانفیگ انتخابی')}: ${subject['name']}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(
                        t(
                          'Attach selected configuration',
                          'پیوست کانفیگ انتخابی',
                        ),
                      ),
                      subtitle: Text(
                        t(
                          'May include its server credentials/JSON. Only send it to your service administrator; account token and subscription URL are not included.',
                          'ممکن است اطلاعات ورود سرور یا JSON آن را داشته باشد؛ با ارسال، به مدیر سرویس می‌رسد. توکن حساب و لینک ساب پیوست نمی‌شوند.',
                        ),
                      ),
                      value: _includeConfig,
                      onChanged: _sending
                          ? null
                          : (v) {
                              setState(() {
                                _includeConfig = v;
                                _changed();
                              });
                              _loadSubject();
                            },
                    ),
                    if (_configLoading) const LinearProgressIndicator(),
                    if (_contextError != null)
                      TextButton(
                        onPressed: _sending || _configLoading
                            ? null
                            : _loadSubject,
                        child: Text(
                          t(
                            'Reload profile details',
                            'دریافت دوبارهٔ مشخصات کانفیگ',
                          ),
                        ),
                      ),
                    if (_includeConfig && _subject['selected_config'] is String)
                      ExpansionTile(
                        title: Text(
                          t(
                            'Preview attached configuration',
                            'مشاهدهٔ کانفیگ پیوست',
                          ),
                        ),
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                '${_subject['selected_config']}',
                                textDirection: TextDirection.ltr,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_sent)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    t('Report received. Thank you!', 'گزارش دریافت شد؛ ممنون!'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (_sending)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              DiagnosticAction(
                label: _sent
                    ? t('Sent', 'ارسال شد')
                    : _sending
                    ? t('Sending…', 'در حال ارسال…')
                    : t('Send to administrator', 'ارسال به مدیر'),
                icon: Icons.send_rounded,
                onPressed:
                    _sending ||
                        _startingCapture ||
                        _capture.active ||
                        _capture.finishing ||
                        (_includeDiagnostics && _checking) ||
                        _configLoading ||
                        _sent
                    ? null
                    : _send,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DiagnosticAction(
                      label: t('Copy', 'کپی'),
                      icon: Icons.copy_rounded,
                      onPressed: _sending
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _exportText()),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      t('Report copied', 'گزارش کپی شد'),
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DiagnosticAction(
                      label: t('Share', 'اشتراک‌گذاری'),
                      icon: Icons.share_rounded,
                      onPressed: _sending
                          ? null
                          : () async {
                              try {
                                await NirangNative.shareProblemReport(
                                  _exportText(),
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        t(
                                          'Sharing unavailable. Use Copy.',
                                          'اشتراک‌گذاری در دسترس نیست؛ کپی کن.',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  'Nothing is sent until you tap Send or choose a share destination. Never include passwords or personal information in your message.',
                  'تا روی ارسال نزنی یا مقصد اشتراک را انتخاب نکنی، چیزی فرستاده نمی‌شود. رمز حساب یا اطلاعات شخصی را داخل متن ننویس.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _uiCaptureCard() {
    final metrics = _capture.result;
    final phases = metrics?['phases'] as Map?;
    final all = phases?['all'] as Map?;
    String stats(String key) {
      final value = all?[key] as Map?;
      return value == null
          ? '—'
          : '${value['p50']} / ${value['p95']} / ${value['p99']} / ${value['max']} ms';
    }

    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Record UI lag — 20 seconds', 'ثبت لگ رابط کاربری — ۲۰ ثانیه'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Start, then scroll and switch between Home, Servers and Settings. Return here to review and send. Going to the background cancels the recording. No screen, text or touches are recorded.',
              'شروع کن، بعد در خانه، سرورها و تنظیمات جابه‌جا شو و اسکرول کن. برای بررسی و ارسال به همین صفحه برگرد. رفتن به پس‌زمینه ثبت را لغو می‌کند. تصویر، متن و لمس‌ها ضبط نمی‌شوند.',
            ),
          ),
          const SizedBox(height: 8),
          if (_capture.active || _capture.finishing) ...[
            Text(
              _capture.finishing
                  ? t('Preparing report…', 'آماده‌سازی گزارش…')
                  : t(
                      'Recording: ${_capture.remaining}s remaining. You can leave this page.',
                      'در حال ثبت: ${_capture.remaining} ثانیه مانده؛ می‌توانی از این صفحه خارج شوی.',
                    ),
            ),
            TextButton(
              onPressed: _capture.cancel,
              child: Text(t('Cancel recording', 'لغو ثبت')),
            ),
          ] else ...[
            if (_capture.cancelled)
              Text(
                t(
                  'Recording cancelled; no UI data attached.',
                  'ثبت لغو شد؛ دادهٔ لگ پیوست نیست.',
                ),
              ),
            DiagnosticAction(
              label: _startingCapture
                  ? t('Preparing…', 'آماده‌سازی…')
                  : t('Start 20-second capture', 'شروع ثبت ۲۰ ثانیه‌ای'),
              icon: Icons.speed_rounded,
              onPressed: _sending || _startingCapture ? null : _startCapture,
            ),
          ],
          if (metrics != null) ...[
            const SizedBox(height: 12),
            Text(
              t(
                'Ready to send • ${all?['frames']} Flutter frames • ${metrics['refresh_rate_hz'] ?? '—'} Hz',
                'آمادهٔ ارسال • ${all?['frames']} فریم Flutter • ${metrics['refresh_rate_hz'] ?? '—'} Hz',
              ),
            ),
            if (all?['frames'] == 0)
              Text(
                t(
                  'No frame samples were received. This is not evidence of smooth rendering.',
                  'نمونهٔ فریم دریافت نشد؛ این به معنی روان بودن رابط نیست.',
                ),
              ),
            Text(
              t(
                'UI p50/p95/p99/max: ${stats('build_ms')}',
                'UI صدک ۵۰/۹۵/۹۹/بیشینه: ${stats('build_ms')}',
              ),
            ),
            Text(
              t(
                'Raster p50/p95/p99/max: ${stats('raster_ms')}',
                'رستر صدک ۵۰/۹۵/۹۹/بیشینه: ${stats('raster_ms')}',
              ),
            ),
            Text(
              t(
                'Total span p50/p95/p99/max: ${stats('total_span_ms')}',
                'کل زمان فریم، صدک ۵۰/۹۵/۹۹/بیشینه: ${stats('total_span_ms')}',
              ),
            ),
            Text(
              t(
                'Flutter frame intervals include idle gaps; they are not display FPS. Raster time is not hardware GPU load. Initial 5s and the remaining 15s are separate; they do not prove shader warm-up.',
                'فاصلهٔ فریم‌های Flutter زمان بیکاری را هم دارد و FPS واقعی نمایشگر نیست. زمان رستر، بار سخت‌افزاری GPU نیست. ۵ ثانیهٔ اول و ۱۵ ثانیهٔ بعد جداست؛ این جداسازی اثبات گرم‌شدن شیدر نیست.',
              ),
            ),
            ExpansionTile(
              title: Text(
                t('Review attached UI data', 'مشاهدهٔ دادهٔ لگ پیوست'),
              ),
              children: [
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert(metrics),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            TextButton(
              onPressed: _sending ? null : _capture.clear,
              child: Text(t('Remove UI attachment', 'حذف پیوست لگ')),
            ),
          ],
        ],
      ),
    );
  }
}
