import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/platform/psiphon_regions.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/psiphon_brand_icon.dart';

/// Edits typed, device-local settings; subscription presets stay authoritative.
class AetherProfileScreen extends StatefulWidget {
  const AetherProfileScreen({this.server, super.key});
  final ServerInfo? server;

  @override
  State<AetherProfileScreen> createState() => _AetherProfileScreenState();
}

class _AetherProfileScreenState extends State<AetherProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _values = <String, Object?>{
    'mode': 'masque',
    'psiphon': 'off',
    'scan': 'balanced',
    'carrier': 'h2',
    'ipFamily': 'v4',
    'psiphonMode': 'auto',
    'psiphonRegion': 'auto',
  };
  bool _loading = false;
  bool _available = false;
  bool _busy = false;
  bool _preparing = false;
  bool _advanced = false;
  bool _renewing = false;
  bool _copy = false;
  String? _error;
  String? _preparedState;
  String _savedEndpoint = '';
  String _savedName = '';
  Map<String, Object?> _savedValues = {};

  bool get _hasUnsavedChanges =>
      widget.server != null &&
      (_name.text.trim() != _savedName ||
          _endpoint.text.trim() != _savedEndpoint ||
          _values.entries.any((e) => _savedValues[e.key] != e.value));

  bool get _readOnly =>
      widget.server != null && widget.server!.origin != 'local' && !_copy;
  String _t(String en, String fa) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;

  @override
  void initState() {
    super.initState();
    _name.text = widget.server?.name ?? 'Aether';
    _available = widget.server == null;
    if (widget.server != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await NirangNative.getAetherProfile(widget.server!.id);
      if (!mounted) return;
      final values = result['values'];
      if (values is Map) {
        for (final key in _values.keys.toList()) {
          if (values.containsKey(key)) _values[key] = values[key];
        }
        _savedEndpoint = '${values['endpoint'] ?? ''}'.trim();
        _endpoint.text = _savedEndpoint;
      }
      _name.text = '${result['name'] ?? widget.server!.name}';
      _savedName = _name.text.trim();
      _savedValues = Map.of(_values);
      _available = true;
    } catch (error) {
      if (mounted) _error = _message(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => userFacingError(
    error,
    persian: Localizations.localeOf(context).languageCode == 'fa',
  ).combined;

  @override
  void dispose() {
    if (_preparing || _renewing) {
      unawaited(
        NirangNative.cancelAetherPreparation().catchError((_) => false),
      );
    }
    _name.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await NirangNative.saveAetherProfile(
        id: _copy ? null : widget.server?.id,
        name: _name.text.trim(),
        values: {..._values, 'endpoint': _endpoint.text.trim()},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare({required bool rescan}) async {
    if (_busy || widget.server == null || _copy || _hasUnsavedChanges) return;
    // Preparation uses the saved profile. Unsaved edits never silently connect.
    setState(() {
      _busy = true;
      _preparing = true;
      _error = null;
    });
    try {
      final result = await NirangNative.prepareAetherProfile(
        widget.server!.id,
        rescan: rescan,
      );
      if (!mounted) return;
      final state = '${result['state'] ?? ''}';
      if (state != 'ready' && state != 'prepared') {
        throw StateError(
          _t('Path preparation did not complete.', 'آماده‌سازی مسیر کامل نشد.'),
        );
      }
      setState(() => _preparedState = state);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      _preparing = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renewIdentity() async {
    if (_busy ||
        _readOnly ||
        widget.server == null ||
        _copy ||
        _hasUnsavedChanges) {
      return;
    }
    final confirmed = await showNirangDialog<bool>(
      context: context,
      builder: (context) => NirangAlertDialog(
        title: Text(
          _t('Renew connection identity?', 'کلید اتصال جدید ساخته بشه؟'),
        ),
        content: Text(
          _t(
            'Refresh this device’s connection identity for this connection mode. Other profiles using this mode share the identity. The existing key is retained if renewal fails. This is normally unnecessary. A VPN or another network may help, but is not required.',
            'کلید اتصال این دستگاه برای این نوع اتصال تازه می‌شه؛ پروفایل‌های هم‌نوع هم از همین کلید استفاده می‌کنن. اگر ساخت کلید جدید شکست بخوره، کلید قبلی حفظ می‌شه. معمولاً نیازی به این کار نیست. VPN یا یه شبکه دیگه ممکنه کمک کنه، ولی اجباری نیست.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Renew', 'ساخت کلید جدید')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _renewing = true;
      _error = null;
    });
    try {
      final result = await NirangNative.renewAetherIdentity(widget.server!.id);
      if (!mounted) return;
      if (result['state'] != 'prepared' && result['state'] != 'ready') {
        throw StateError(
          _t('Identity renewal did not complete.', 'ساخت کلید جدید کامل نشد.'),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('Connection identity renewed.', 'کلید اتصال جدید ساخته شد.'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _renewing = false;
        });
      }
    }
  }

  String? _validateEndpoint(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(
      r'^(?:\[([^\]]+)\]|([^:]+)):(\d{1,5})$',
    ).firstMatch(raw);
    if (match != null) {
      final address = InternetAddress.tryParse(
        match.group(1) ?? match.group(2)!,
      );
      final port = int.tryParse(match.group(3)!);
      if (address != null && port != null && port > 0 && port <= 65535) {
        return null;
      }
    }
    return _t(
      'Enter an IP:port or [IPv6]:port.',
      'IP:port یا [IPv6]:port وارد کن.',
    );
  }

  Future<void> _choose(
    String key,
    String title,
    Map<String, String> options,
  ) async {
    final selected = await showNirangDialog<String>(
      context: context,
      builder: (context) => NirangAlertDialog(
        title: Text(title),
        // The dialog normally scrolls its content. A second unbounded bouncing
        // viewport steals drags then springs back to zero; this list owns the
        // single bounded scroll position instead.
        scrollContent: false,
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .58,
          ),
          child: ListView(
            shrinkWrap: true,
            primary: false,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final entry in options.entries)
                ListTile(
                  title: Text(entry.value),
                  trailing: _values[key] == entry.key
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(context).pop(entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _values[key] = selected);
  }

  Widget _choice(
    String key,
    String title,
    Map<String, String> options, {
    bool enabled = true,
  }) => ListTile(
    key: ValueKey('aether-$key'),
    title: Text(title),
    subtitle: Text(options[_values[key]] ?? '${_values[key]}'),
    trailing: const Icon(Icons.chevron_right_rounded),
    enabled: enabled && !_readOnly && !_busy,
    onTap: () => _choose(key, title, options),
  );

  Widget _sectionDivider() => Divider(
    height: 18,
    thickness: .6,
    indent: 16,
    endIndent: 16,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55),
  );

  Widget _sectionHeading(String label, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: Row(
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: Text(_t('Aether settings', 'تنظیمات Aether')),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FrostedSurface(
        sigma: 8,
        tintAlpha: Theme.of(context).brightness == Brightness.dark ? .45 : .64,
        child: const SizedBox.expand(),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                16,
                // Scaffold already resizes above the keyboard; padding becomes
                // zero there, while gesture/three-button navigation stays clear.
                28 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const ValueKey('aether-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (widget.server != null)
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: Text(_t('Retry', 'تلاش دوباره')),
                    ),
                ],
                if (_readOnly) ...[
                  Text(
                    _t(
                      'This preset is managed by your subscription. Create a local copy to edit it.',
                      'این پروفایل از اشتراک میاد. برای ویرایش، یه کپی محلی بساز.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('aether-create-copy'),
                    onPressed: _busy || !_available
                        ? null
                        : () => setState(() => _copy = true),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(_t('Create local copy', 'ساخت کپی محلی')),
                  ),
                  const SizedBox(height: 12),
                ],
                FrostedSurface(
                  radius: 22,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextFormField(
                          key: const ValueKey('aether-name'),
                          controller: _name,
                          onChanged: (_) => setState(() {}),
                          enabled: !_readOnly && !_busy,
                          decoration: InputDecoration(
                            labelText: context.s('name'),
                          ),
                          maxLength: 100,
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? _t('Enter a name.', 'اسم رو وارد کن.')
                              : null,
                        ),
                        _choice(
                          'mode',
                          _t('Connection mode', 'نوع اتصال'),
                          const {
                            'masque': 'MASQUE (Aether)',
                            'wireguard': 'WireGuard (WARP)',
                            'wireguard-over-masque': 'WireGuard over MASQUE',
                          },
                        ),
                        _sectionDivider(),
                        SwitchListTile(
                          key: const ValueKey('aether-psiphon'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          secondary: const PsiphonBrandIcon(size: 26),
                          title: const Text('Psiphon'),
                          value: _values['psiphon'] == 'chain',
                          onChanged: _readOnly || _busy
                              ? null
                              : (on) => setState(
                                  () =>
                                      _values['psiphon'] = on ? 'chain' : 'off',
                                ),
                        ),
                        _choice(
                          'psiphonRegion',
                          _t('Psiphon exit region', 'منطقه خروج Psiphon'),
                          psiphonRegions,
                          enabled: _values['psiphon'] != 'off',
                        ),
                        if (_values['psiphon'] != 'off')
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Text(
                              _t(
                                'Supported region selection does not guarantee an available exit.',
                                'انتخاب منطقه به معنی تضمین وجود خروجی فعال در اون کشور نیست.',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        Text(
                          _t(
                            'Psiphon may improve access, but can increase latency and reduce speed. A fixed IP or clean reputation is not guaranteed.',
                            'Psiphon ممکنه دسترسی رو بهتر کنه، ولی تأخیر بیشتر و سرعت کمتر هم ممکنه. IP ثابت یا اعتبار تمیز تضمین نمی‌شه.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FrostedSurface(
                  radius: 22,
                  child: Column(
                    children: [
                      ListTile(
                        key: const ValueKey('aether-advanced'),
                        title: Text(
                          _t('Advanced', 'پیشرفته'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: AnimatedRotation(
                          turns: _advanced ? .5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          curve: Curves.easeInOutCubic,
                          child: const Icon(Icons.expand_more_rounded),
                        ),
                        onTap: () => setState(() => _advanced = !_advanced),
                      ),
                      AnimatedSize(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: !_advanced
                            ? const SizedBox(width: double.infinity)
                            : Column(
                                children: [
                                  _sectionDivider(),
                                  _sectionHeading(
                                    _t('Path discovery', 'جست‌وجوی مسیر'),
                                    Icons.travel_explore_rounded,
                                  ),
                                  _choice(
                                    'scan',
                                    _t('Scan strategy', 'روش جست‌وجو'),
                                    const {
                                      'balanced': 'Balanced',
                                      'turbo': 'Turbo',
                                      'stealth': 'Stealth',
                                      'ironclad': 'Ironclad',
                                    },
                                  ),
                                  _choice(
                                    'carrier',
                                    _t('Carrier', 'حامل'),
                                    const {'h2': 'HTTP/2', 'h3': 'HTTP/3'},
                                    enabled: _values['mode'] != 'wireguard',
                                  ),
                                  _choice(
                                    'ipFamily',
                                    _t('IP family', 'خانواده IP'),
                                    const {'v4': 'IPv4', 'v6': 'IPv6'},
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          key: const ValueKey(
                                            'aether-endpoint',
                                          ),
                                          controller: _endpoint,
                                          onChanged: (_) => setState(() {}),
                                          enabled: !_readOnly && !_busy,
                                          textDirection: TextDirection.ltr,
                                          decoration: InputDecoration(
                                            labelText: _t(
                                              'Endpoint (optional)',
                                              'نقطه اتصال (اختیاری)',
                                            ),
                                          ),
                                          validator: _validateEndpoint,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            6,
                                            12,
                                            8,
                                          ),
                                          child: Text(
                                            _t(
                                              'Clear this address and save for automatic IP discovery.',
                                              'برای جست‌وجوی خودکار IP، آدرس رو پاک و ذخیره کن.',
                                            ),
                                            softWrap: true,
                                            overflow: TextOverflow.visible,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _sectionDivider(),
                                  _sectionHeading(
                                    _t('Connection identity', 'کلید اتصال'),
                                    Icons.key_rounded,
                                  ),
                                  ListTile(
                                    key: const ValueKey(
                                      'aether-renew-identity',
                                    ),
                                    leading: const Icon(Icons.key_rounded),
                                    title: Text(
                                      _t(
                                        'Renew connection identity',
                                        'ساخت کلید اتصال جدید',
                                      ),
                                    ),
                                    subtitle: Text(
                                      _t(
                                        'Optional; normally unnecessary. A VPN may help but is not required.',
                                        'اختیاری؛ معمولاً لازم نیست. VPN ممکنه کمک کنه، ولی اجباری نیست.',
                                      ),
                                    ),
                                    enabled:
                                        !_busy &&
                                        !_readOnly &&
                                        widget.server != null &&
                                        !_copy &&
                                        _available &&
                                        !_hasUnsavedChanges,
                                    trailing: _renewing
                                        ? const SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.chevron_right_rounded,
                                          ),
                                    onTap: _renewIdentity,
                                  ),
                                  _sectionDivider(),
                                  _sectionHeading(
                                    'Psiphon',
                                    Icons.alt_route_rounded,
                                  ),
                                  _choice(
                                    'psiphonMode',
                                    _t('Psiphon transport', 'مسیر Psiphon'),
                                    const {
                                      'auto': 'Auto',
                                      'cdn': 'CDN',
                                      'direct': 'Direct',
                                    },
                                    enabled: _values['psiphon'] != 'off',
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _t(
                    'Path actions use the saved profile. Save changes first; the current connection stays active.',
                    'آماده‌سازی و تست با پروفایل ذخیره‌شده انجام می‌شه. اول تغییرات رو ذخیره کن؛ اتصال فعلی فعال می‌مونه.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_savedEndpoint.isNotEmpty)
                  Text(
                    _t(
                      'An explicit endpoint tests that address only. Clear the endpoint and save to discover another IP automatically.',
                      'با آدرس مشخص، فقط همون آدرس تست می‌شه. برای جست‌وجوی خودکار IP دیگه، آدرس رو پاک و ذخیره کن.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                if (_busy) const LinearProgressIndicator(),
                if (_preparedState != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _preparedState == 'ready'
                          ? _t('Path is ready.', 'مسیر آماده‌ست.')
                          : _t(
                              'Profile prepared. Connectivity is verified when connecting.',
                              'پروفایل آماده شد. اتصال هنگام وصل‌شدن بررسی می‌شه.',
                            ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('aether-prepare'),
                  onPressed:
                      _busy ||
                          widget.server == null ||
                          _copy ||
                          !_available ||
                          _hasUnsavedChanges
                      ? null
                      : () => _prepare(rescan: false),
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text(
                    _savedEndpoint.isEmpty
                        ? _t('Find endpoint IP', 'پیداکردن IP اتصال')
                        : _t('Prepare / test path', 'آماده‌سازی / تست مسیر'),
                  ),
                ),
                TextButton(
                  key: const ValueKey('aether-rescan'),
                  onPressed:
                      _busy ||
                          widget.server == null ||
                          _copy ||
                          !_available ||
                          _hasUnsavedChanges
                      ? null
                      : () => _prepare(rescan: true),
                  child: Text(
                    _savedEndpoint.isEmpty
                        ? _t('Find a new endpoint IP', 'پیداکردن IP جدید')
                        : _t('Test path again', 'تست دوباره مسیر'),
                  ),
                ),
                if (!_readOnly)
                  FilledButton.icon(
                    key: const ValueKey('aether-save'),
                    onPressed: _busy || !_available ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.s('save')),
                  ),
              ],
            ),
          ),
  );
}
