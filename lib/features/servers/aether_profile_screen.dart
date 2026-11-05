import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../vpn/app_controller.dart';
import '../vpn/connection_path_card.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/platform/psiphon_regions.dart';
import '../../core/user_facing_error.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/psiphon_brand_icon.dart';
import '../../core/widgets/clay_surface.dart';
import '../../core/widgets/country_flag_badge.dart';

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
  final _outerEndpoint = TextEditingController();
  final _innerEndpoint = TextEditingController();
  final _values = <String, Object?>{
    'mode': 'masque',
    'psiphon': 'off',
    'scan': 'balanced',
    'carrier': 'h2',
    'ipFamily': 'v4',
    'psiphonMode': 'auto',
    'psiphonRegion': 'auto',
    'fingerprint': 'native',
    'endpointHistory': <String, dynamic>{},
  };
  bool _loading = false;
  bool _available = false;
  bool _busy = false;
  bool _preparing = false;
  bool _renewing = false;
  bool _copy = false;
  String? _error;
  String? _preparedState;
  String _savedEndpoint = '';
  String _savedOuter = '';
  String _savedInner = '';
  Map<dynamic, dynamic>? _suggestion;
  bool _suggestionLoading = false;
  bool _suggestionFailed = false;
  int _suggestionRevision = 0;
  String _savedName = '';
  Map<String, Object?> _savedValues = {};

  bool get _hasUnsavedChanges =>
      widget.server != null &&
      (_name.text.trim() != _savedName ||
          _outerEndpoint.text.trim() != _savedOuter ||
          _innerEndpoint.text.trim() != _savedInner ||
          _endpoint.text.trim() != _savedEndpoint ||
          _values.entries.any((e) => _savedValues[e.key] != e.value));

  bool get _rawWireguard =>
      const {'wireguard', 'warp-in-warp'}.contains(_values['mode']);
  bool get _nested => const {
    'wireguard-over-masque',
    'warp-in-warp',
    'masque-in-masque',
  }.contains(_values['mode']);
  Map<String, Object?> get _formValues =>
      {
        ..._values,
        'endpoint': _nested ? '' : _endpoint.text.trim(),
        'outerEndpoint': _nested ? _outerEndpoint.text.trim() : '',
        'innerEndpoint': _nested ? _innerEndpoint.text.trim() : '',
      }..removeWhere(
        (key, value) =>
            const {
              'endpoint',
              'outerEndpoint',
              'innerEndpoint',
            }.contains(key) &&
            value == '',
      );

  void _changeOption(String key, String selected) {
    if (_values[key] == selected) return;
    if (key == 'mode') {
      final history = Map<String, dynamic>.from(
        _values['endpointHistory'] as Map? ?? {},
      );
      history['${_values['mode']}'] = {
        if (!_nested) 'endpoint': _endpoint.text.trim(),
        if (_nested) 'outerEndpoint': _outerEndpoint.text.trim(),
        if (_nested) 'innerEndpoint': _innerEndpoint.text.trim(),
      }..removeWhere((key, value) => value == '');
      _values['endpointHistory'] = history;
      final restored = history[selected] as Map? ?? {};
      _endpoint.text = '${restored['endpoint'] ?? ''}';
      _outerEndpoint.text = '${restored['outerEndpoint'] ?? ''}';
      _innerEndpoint.text = '${restored['innerEndpoint'] ?? ''}';
    }
    _values[key] = selected;
    if (_rawWireguard) {
      _values['carrier'] = 'h3';
      _values['fingerprint'] = 'native';
      if (_values['psiphon'] == 'reverse') _values['psiphon'] = 'chain';
    }
    _preparedState = null;
    _suggestion = null;
    _suggestionRevision++;
  }

  bool get _readOnly =>
      widget.server != null && widget.server!.origin != 'local' && !_copy;
  String _t(String en, String fa) =>
      Localizations.localeOf(context).languageCode == 'fa' ? fa : en;

  @override
  void initState() {
    super.initState();
    _name.text = widget.server?.name ?? 'Aether';
    _available = widget.server == null;
    if (widget.server != null) {
      _load();
    } else {
      unawaited(_loadSuggestion());
    }
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
        _savedOuter = '${values['outerEndpoint'] ?? ''}';
        _savedInner = '${values['innerEndpoint'] ?? ''}';
        _outerEndpoint.text = _savedOuter;
        _innerEndpoint.text = _savedInner;
        _savedEndpoint = '${values['endpoint'] ?? ''}'.trim();
        if (_nested && _savedOuter.isEmpty) {
          _savedOuter = _savedEndpoint;
          _outerEndpoint.text = _savedOuter;
          _savedEndpoint = '';
        }
        _endpoint.text = _savedEndpoint;
      }
      _name.text = '${result['name'] ?? widget.server!.name}';
      _savedName = _name.text.trim();
      _savedValues = Map.of(_values);
      _available = true;
      unawaited(_loadSuggestion());
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
    _outerEndpoint.dispose();
    _innerEndpoint.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    final revision = ++_suggestionRevision;
    setState(() {
      _suggestionLoading = true;
      _suggestionFailed = false;
      _suggestion = null;
    });
    try {
      final value = await NirangNative.aetherEndpointSuggestion(_formValues);
      if (mounted && revision == _suggestionRevision) {
        setState(() => _suggestion = value);
      }
    } catch (_) {
      if (mounted && revision == _suggestionRevision) {
        setState(() => _suggestionFailed = true);
      }
    } finally {
      if (mounted && revision == _suggestionRevision) {
        setState(() => _suggestionLoading = false);
      }
    }
  }

  Future<void> _applySuggestion() async {
    final shown = _suggestion;
    if (shown == null || _readOnly || _busy) return;
    setState(() => _busy = true);
    try {
      // Recheck locally when applying: a network switch must not silently apply
      // a recommendation displayed for a different network category/operator.
      final fresh = await NirangNative.aetherEndpointSuggestion(_formValues);
      if (!mounted) return;
      final old = shown['endpoints'] as Map? ?? {};
      final endpoints = fresh['endpoints'] as Map? ?? {};
      final same =
          fresh['available'] == true &&
          fresh['kind'] == shown['kind'] &&
          fresh['carrier'] == shown['carrier'] &&
          endpoints.length == old.length &&
          endpoints.entries.every((entry) => old[entry.key] == entry.value);
      setState(() {
        _suggestion = fresh;
        if (!same) {
          _error = _t(
            'Network or suggestion changed. Review the refreshed suggestion and choose it again.',
            'شبکه یا پیشنهاد تغییر کرده؛ پیشنهاد تازه را ببین و دوباره انتخاب کن.',
          );
          return;
        }
        if (!_nested && endpoints['endpoint'] is String) {
          _endpoint.text = endpoints['endpoint'] as String;
        }
        if (_nested && endpoints['outerEndpoint'] is String) {
          _outerEndpoint.text = endpoints['outerEndpoint'] as String;
        }
        if (_nested && endpoints['innerEndpoint'] is String) {
          _innerEndpoint.text = endpoints['innerEndpoint'] as String;
        }
        _preparedState = null;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _suggestionPanel() {
    final suggestion = _suggestion;
    final endpoints = suggestion?['endpoints'] as Map?;
    final available = suggestion?['available'] == true && endpoints != null;
    final network = switch (suggestion?['kind']) {
      'wifi' => 'Wi-Fi',
      'mobile' => _t('Mobile data', 'دادهٔ همراه'),
      _ => _t('network', 'شبکه'),
    };
    final carrier = '${suggestion?['carrier'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t('Endpoint suggestion', 'پیشنهاد IP اتصال'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: _suggestionLoading ? null : _loadSuggestion,
                icon: _suggestionLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                tooltip: _t('Refresh suggestion', 'تازه‌کردن پیشنهاد'),
              ),
            ],
          ),
          Text(
            _suggestionFailed
                ? _t(
                    'History is unavailable. Manual entry and scan still work.',
                    'سابقه در دسترس نیست؛ ورود دستی و اسکن همچنان کار می‌کنند.',
                  )
                : available
                ? _t(
                    'Last successful endpoint on $network${carrier.isEmpty ? '' : ' · $carrier'}. A suggestion, not a connectivity guarantee.',
                    'آخرین IP موفق روی $network${carrier.isEmpty ? '' : ' · $carrier'}. پیشنهاد است؛ اتصال تضمین نمی‌شود.',
                  )
                : _t(
                    'No successful endpoint recorded for these settings and network category yet. It is learned after a successful IP check or connection check.',
                    'برای این تنظیمات و نوع شبکه هنوز IP موفقی ثبت نشده؛ بعد از بررسی موفق IP یا بررسی اتصال یاد گرفته می‌شود.',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (available) ...[
            const SizedBox(height: 8),
            for (final entry in endpoints.entries)
              SelectableText(
                '${entry.value}',
                textDirection: TextDirection.ltr,
              ),
            const SizedBox(height: 8),
            _AetherAction(
              onPressed: _readOnly || _busy ? null : _applySuggestion,
              icon: Icons.south_west_rounded,
              label: _t('Use this IP', 'استفاده از این IP'),
            ),
          ],
        ],
      ),
    );
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
        values: _formValues,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare({required bool rescan}) async {
    if (_busy || _readOnly || !_available || !_form.currentState!.validate()) {
      return;
    }
    // Scan the draft in isolation; only Save applies it to a live profile.
    setState(() {
      _busy = true;
      _preparing = true;
      _error = null;
    });
    try {
      final result = await NirangNative.scanAetherDraft(_formValues);
      if (!mounted) return;
      final state = '${result['state'] ?? ''}';
      if (state != 'ready' && state != 'prepared') {
        throw StateError(
          _t('Path preparation did not complete.', 'آماده‌سازی مسیر کامل نشد.'),
        );
      }
      final scan = result['scan'];
      if (scan is! Map) {
        throw const FormatException('The core did not report an endpoint');
      }
      final endpoint = '${scan['endpoint'] ?? ''}';
      final inner = '${scan['innerEndpoint'] ?? ''}';
      if (endpoint.isEmpty ||
          _validateEndpoint(endpoint) != null ||
          (_nested && (inner.isEmpty || _validateEndpoint(inner) != null))) {
        throw const FormatException('Invalid scan endpoint');
      }
      setState(() {
        if (_nested) {
          _outerEndpoint.text = endpoint;
          _innerEndpoint.text = inner;
        } else {
          _endpoint.text = endpoint;
        }
        _preparedState = '$endpoint${inner.isEmpty ? '' : ' → $inner'}';
      });
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
            physics: key == 'psiphonRegion'
                ? const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (final entry in options.entries)
                ListTile(
                  leading: key == 'psiphonRegion'
                      ? CountryFlagBadge(
                          countryCode: entry.key == 'auto' ? '' : entry.key,
                        )
                      : null,
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
    if (selected != null && mounted) {
      setState(() => _changeOption(key, selected));
      unawaited(_loadSuggestion());
    }
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

  Widget _card(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ClaySurface(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _endpointField(
    TextEditingController controller,
    String key,
    String label,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      onChanged: (_) => setState(() {}),
      enabled: !_readOnly && !_busy,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label),
      validator: _validateEndpoint,
    ),
  );

  Widget _footer() => FrostedSurface(
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              child: !_preparing && _preparedState == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          if (_preparing)
                            const LinearProgressIndicator(
                              minHeight: 3,
                              borderRadius: BorderRadius.all(
                                Radius.circular(4),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                _preparing
                                    ? Icons.travel_explore_rounded
                                    : Icons.check_circle_rounded,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _preparing
                                      ? _t(
                                          'Finding an endpoint…',
                                          'در حال یافتن IP…',
                                        )
                                      : _t(
                                          'IP found: $_preparedState',
                                          'IP پیدا شد: $_preparedState',
                                        ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              textDirection: TextDirection.ltr,
              children: [
                Expanded(
                  child: _AetherAction(
                    key: const ValueKey('aether-prepare'),
                    onPressed: _preparing
                        ? () => NirangNative.cancelAetherPreparation()
                        : _busy || !_available || _readOnly
                        ? null
                        : () => _prepare(rescan: true),
                    icon: _preparing
                        ? Icons.close_rounded
                        : Icons.travel_explore_rounded,
                    label: _preparing
                        ? _t('Cancel scan', 'لغو اسکن')
                        : _t('Scan IP', 'اسکن IP'),
                  ),
                ),
                if (!_readOnly) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AetherAction(
                      key: const ValueKey('aether-save'),
                      selected: true,
                      onPressed: _busy || !_available ? null : _save,
                      icon: Icons.save_outlined,
                      label: context.s('save'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    extendBody: true,
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
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _footer(),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                16,
                (_preparing || _preparedState != null ? 192 : 112) +
                    MediaQuery.paddingOf(context).bottom,
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
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final connection =
                            ref.watch(
                              appControllerProvider.select(
                                (value) => value.asData?.value.connection,
                              ),
                            ) ??
                            const ConnectionInfo();
                        return ConnectionPathCard(
                          compact: true,
                          server: ServerInfo.fromMap({
                            'id': _copy
                                ? 'draft'
                                : widget.server?.id ?? 'draft',
                            'name': _name.text,
                            'profileKind': 'aether',
                            'engine': 'aether',
                            'aetherMode': _values['mode'],
                            'psiphonPlacement': _values['psiphon'],
                          }),
                          connection: _copy || _hasUnsavedChanges
                              ? const ConnectionInfo()
                              : connection,
                        );
                      },
                    ),
                  ),
                ),
                if (_readOnly) ...[
                  Text(
                    _t(
                      'This preset is managed by your subscription. Create a local copy to edit it.',
                      'این پروفایل از اشتراک میاد. برای ویرایش، یه کپی محلی بساز.',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('aether-create-copy'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _copy = true),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(_t('Create local copy', 'ساخت کپی محلی')),
                  ),
                  const SizedBox(height: 12),
                ],
                _card([
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextFormField(
                      key: const ValueKey('aether-name'),
                      controller: _name,
                      enabled: !_readOnly && !_busy,
                      onChanged: (_) => setState(() {}),
                      maxLength: 100,
                      decoration: InputDecoration(labelText: context.s('name')),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? _t('Enter a name.', 'اسم رو وارد کن.')
                          : null,
                    ),
                  ),
                  _choice('mode', _t('Connection mode', 'نوع اتصال'), const {
                    'masque': 'MASQUE (Aether)',
                    'wireguard': 'WireGuard (WARP)',
                    'wireguard-over-masque': 'WireGuard over MASQUE',
                    'warp-in-warp': 'WARP-in-WARP',
                    'masque-in-masque': 'MASQUE-in-MASQUE',
                  }),
                ]),
                _card([
                  SwitchListTile(
                    key: const ValueKey('aether-psiphon'),
                    secondary: const PsiphonBrandIcon(size: 26),
                    title: const Text('Psiphon'),
                    value: _values['psiphon'] == 'chain',
                    onChanged: _busy || _readOnly
                        ? null
                        : (v) {
                            setState(
                              () =>
                                  _changeOption('psiphon', v ? 'chain' : 'off'),
                            );
                            unawaited(_loadSuggestion());
                          },
                  ),
                  _choice(
                    'psiphonRegion',
                    _t('Psiphon exit region', 'منطقه خروج سایفون'),
                    psiphonRegions,
                    enabled: _values['psiphon'] != 'off',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _t(
                        'Speed and exit availability depend on your network. A fixed IP is not guaranteed.',
                        'سرعت و کشور خروجی به شبکه بستگی دارند؛ IP ثابت تضمین نمی‌شود.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _choice(
                    'psiphonMode',
                    _t('Psiphon transport', 'مسیر سایفون'),
                    const {'auto': 'Auto', 'cdn': 'CDN', 'direct': 'Direct'},
                    enabled: _values['psiphon'] != 'off',
                  ),
                ]),
                _card([
                  _sectionHeading(
                    _t('Path discovery', 'جست‌وجوی مسیر'),
                    Icons.travel_explore_rounded,
                  ),
                  _suggestionPanel(),
                  _choice('scan', _t('Scan strategy', 'روش جست‌وجو'), const {
                    'balanced': 'Balanced',
                    'turbo': 'Turbo',
                    'stealth': 'Stealth',
                    'ironclad': 'Ironclad',
                  }),
                  _choice(
                    'carrier',
                    _t('Carrier', 'حامل'),
                    _rawWireguard
                        ? const {'h3': 'UDP'}
                        : const {'h2': 'HTTP/2', 'h3': 'HTTP/3'},
                    enabled: !_rawWireguard,
                  ),
                  _choice('ipFamily', _t('IP family', 'خانواده IP'), const {
                    'v4': 'IPv4',
                    'v6': 'IPv6',
                    'both': 'IPv4 + IPv6',
                  }),
                  if (!_nested)
                    _endpointField(
                      _endpoint,
                      'aether-endpoint',
                      _t('Endpoint (optional)', 'نقطه اتصال (اختیاری)'),
                    ),
                  if (_nested) ...[
                    _endpointField(
                      _outerEndpoint,
                      'aether-outer-endpoint',
                      _t(
                        'Outer endpoint (optional)',
                        'نقطه اتصال بیرونی (اختیاری)',
                      ),
                    ),
                    _endpointField(
                      _innerEndpoint,
                      'aether-inner-endpoint',
                      _t(
                        'Inner endpoint (optional)',
                        'نقطه اتصال داخلی (اختیاری)',
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _t(
                        'Leave empty for automatic discovery. Scan fills this draft; Save applies it.',
                        'برای انتخاب خودکار خالی بگذار. اسکن، فرم را پر می‌کند؛ ذخیره تغییرات را اعمال می‌کند.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ]),
                _card([
                  _sectionHeading(
                    _t('TLS profile', 'مشخصات TLS'),
                    Icons.fingerprint_rounded,
                  ),
                  _choice(
                    'fingerprint',
                    _t('TLS fingerprint', 'اثر انگشت TLS'),
                    const {
                      'native': 'Native (BoringSSL)',
                      'chrome': 'Chrome',
                      'chrome-120': 'Chrome 120',
                      'firefox': 'Firefox',
                      'semi-python': 'Semi-Python',
                      'go': 'Go',
                    },
                    enabled: !_rawWireguard,
                  ),
                  if (_rawWireguard)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _t(
                          'WireGuard has no TLS handshake.',
                          'وایرگارد دست‌دهی TLS ندارد.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ]),
                _card([
                  _sectionHeading(
                    _t('Connection identity', 'کلید اتصال'),
                    Icons.key_rounded,
                  ),
                  ListTile(
                    key: const ValueKey('aether-renew'),
                    title: Text(
                      _t('Renew connection identity', 'ساخت کلید اتصال جدید'),
                    ),
                    subtitle: Text(
                      _t(
                        'Optional; normally unnecessary.',
                        'اختیاری؛ معمولاً نیازی نیست.',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    enabled:
                        !_busy &&
                        !_readOnly &&
                        widget.server != null &&
                        !_copy &&
                        !_hasUnsavedChanges,
                    onTap: _renewIdentity,
                  ),
                ]),
              ],
            ),
          ),
  );
}

class _AetherAction extends StatefulWidget {
  const _AetherAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.selected = false,
  });
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool selected;
  @override
  State<_AetherAction> createState() => _AetherActionState();
}

class _AetherActionState extends State<_AetherAction> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.onPressed == null
        ? null
        : (_) => setState(() => pressed = true),
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: ClayPress(
      pressed: pressed,
      child: ClaySurface(
        radius: 16,
        color: widget.selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: TextButton.icon(
          onPressed: widget.onPressed,
          style: TextButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            overlayColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(widget.icon, size: 20),
          label: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
  );
}
