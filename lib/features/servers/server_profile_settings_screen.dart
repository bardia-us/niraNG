import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/status_toast.dart';
import '../vpn/app_controller.dart';
import 'tls_profile_choices.dart';

class ServerProfileSettingsScreen extends ConsumerStatefulWidget {
  const ServerProfileSettingsScreen({required this.server, super.key});

  final ServerInfo server;

  @override
  ConsumerState<ServerProfileSettingsScreen> createState() =>
      _ServerProfileSettingsScreenState();
}

class _ServerProfileSettingsScreenState
    extends ConsumerState<ServerProfileSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late final Map<String, String> _initial;
  bool _saving = false;
  static const _customFingerprint = '__custom__';
  late String _fingerprintSelection;

  bool get _tls => widget.server.security.toLowerCase() == 'tls';

  @override
  void initState() {
    super.initState();
    _initial = {
      'sni': widget.server.sni,
      'fp': widget.server.fingerprint,
      if (_tls) ...{
        'cs': widget.server.cipherSuites,
        'fm': widget.server.finalMask,
        'alpn': widget.server.alpn,
      },
    };
    _fields = _initial.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
    _fingerprintSelection =
        _initial['fp']!.isEmpty ||
            ((profileFingerprintPresets.contains(_initial['fp']) ||
                    profileAdvancedFingerprints.contains(_initial['fp'])) &&
                (_tls || _initial['fp'] != 'unsafe'))
        ? _initial['fp']!
        : _customFingerprint;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final changes = <String, Object?>{
      for (final field in _fields.entries)
        if (field.value.text != _initial[field.key])
          field.key: field.value.text.trim(),
    };
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .updateServerProfile(widget.server.id, changes);
      if (!mounted) return;
      showSuccessToast(context, context.s('profileSaved'));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorToast(context, context.s('profileSaveFailed'));
    }
  }

  String? _validateMask(String? raw) {
    if (raw == _initial['fm']) return null;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      if (jsonDecode(raw) is Map<String, dynamic>) return null;
    } catch (_) {
      // Native validation is authoritative; catch obvious JSON errors here.
    }
    return context.s('profileInvalid');
  }

  String? _validateFingerprint(String? _) {
    final raw = _fields['fp']!.text;
    final value = raw.trim().toLowerCase();
    if (!_tls && value == 'unsafe') {
      return context.s('profileInvalidFingerprint');
    }
    if (raw == _initial['fp'] || value.isEmpty) return null;
    return profileFingerprintPresets.contains(value) ||
            profileAdvancedFingerprints.contains(value)
        ? null
        : context.s('profileInvalidFingerprint');
  }

  Future<void> _selectChoices(String key) async {
    final isAlpn = key == 'alpn';
    final separator = isAlpn ? ',' : ':';
    final controller = _fields[key]!;
    final original = controller.text;
    final selected = original
        .split(separator)
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final choices = <String>{
      ...(isAlpn ? profileAlpnChoices : profileCipherChoices),
      ...selected,
    }.toList();
    var customText = '';
    var selectionEdited = false;
    final dialogForm = GlobalKey<FormState>();
    final result = await showNirangDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => NirangAlertDialog(
          title: Text(isAlpn ? 'ALPN' : context.s('cipherSuites')),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: dialogForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.s('profileSelectionHint')),
                  for (final choice in choices)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          choice,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      value: selected.contains(choice),
                      onChanged: (checked) => updateDialog(() {
                        selectionEdited = true;
                        if (checked == true) {
                          selected.add(choice);
                        } else {
                          selected.remove(choice);
                        }
                      }),
                    ),
                  if (isAlpn)
                    TextFormField(
                      key: const ValueKey('profile-custom-alpn'),
                      onChanged: (value) => customText = value,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: context.s('profileCustom'),
                      ),
                      validator: (raw) {
                        if (raw == null || raw.trim().isEmpty) return null;
                        final protocols = raw.split(',').map((v) => v.trim());
                        return protocols.every(
                              (v) =>
                                  v.isNotEmpty &&
                                  utf8.encode(v).length <= 255 &&
                                  v.codeUnits.every((c) => c >= 33 && c <= 126),
                            )
                            ? null
                            : context.s('profileInvalid');
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.s('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: Text(context.s('profileDefault')),
            ),
            FilledButton(
              key: const ValueKey('apply-profile-choices'),
              onPressed: () {
                if (!dialogForm.currentState!.validate()) return;
                final additions = customText
                    .split(',')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty);
                final values = <String>{...selected, ...additions}.toList();
                final initialValues = original
                    .split(separator)
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList();
                // Opening and confirming a selector never rewrites imports.
                final unchanged =
                    (!selectionEdited && customText.trim().isEmpty) ||
                    (values.length == initialValues.length &&
                        List.generate(
                          values.length,
                          (i) => values[i] == initialValues[i],
                        ).every((v) => v));
                Navigator.pop(
                  dialogContext,
                  unchanged ? original : values.join(separator),
                );
              },
              child: Text(context.s('apply')),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) setState(() => controller.text = result);
  }

  Widget _fingerprintField() => Column(
    children: [
      DropdownButtonFormField<String>(
        key: const ValueKey('profile-fp'),
        initialValue: _fingerprintSelection,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.s('fingerprint')),
        items: [
          DropdownMenuItem(value: '', child: Text(context.s('profileDefault'))),
          for (final choice in [
            ...profileFingerprintPresets,
            ...profileAdvancedFingerprints,
          ])
            if (_tls || choice != 'unsafe')
              DropdownMenuItem(
                value: choice,
                child: Text(choice, textDirection: TextDirection.ltr),
              ),
          DropdownMenuItem(
            value: _customFingerprint,
            child: Text(context.s('profileCustom')),
          ),
        ],
        validator: _fingerprintSelection == _customFingerprint
            ? null
            : _validateFingerprint,
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _fingerprintSelection = value!;
                if (value != _customFingerprint) _fields['fp']!.text = value;
              }),
      ),
      if (_fingerprintSelection == _customFingerprint) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('profile-custom-fp'),
          controller: _fields['fp'],
          enabled: !_saving,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: context.s('profileCustom'),
            helperText: context.s('profileChoiceHint'),
          ),
          validator: _validateFingerprint,
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.s('serverProfileSettings'))),
    body: Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.server.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(context.s('profileReconnectHint')),
            if (!_tls) ...[
              const SizedBox(height: 8),
              Text(context.s('profileTlsOnlyHint')),
            ],
            for (final field in _fields.entries) ...[
              const SizedBox(height: 16),
              if (field.key == 'fp')
                _fingerprintField()
              else
                TextFormField(
                  key: ValueKey('profile-${field.key}'),
                  controller: field.value,
                  enabled: !_saving,
                  readOnly: field.key == 'cs' || field.key == 'alpn',
                  onTap: field.key == 'cs' || field.key == 'alpn'
                      ? () => _selectChoices(field.key)
                      : null,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  minLines: field.key == 'fm' ? 3 : 1,
                  maxLines: field.key == 'fm' ? 8 : 1,
                  decoration: InputDecoration(
                    labelText: switch (field.key) {
                      'sni' => 'SNI',
                      'fp' => 'Fingerprint',
                      'cs' => context.s('cipherSuites'),
                      'fm' => context.s('finalMask'),
                      _ => 'ALPN',
                    },
                    suffixIcon: field.key == 'cs' || field.key == 'alpn'
                        ? const Icon(Icons.tune_rounded)
                        : null,
                    helperText: field.key == 'cs'
                        ? context.s('profileCipherHint')
                        : null,
                    helperMaxLines: 4,
                  ),
                  validator: field.key == 'fm' ? _validateMask : null,
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('save-server-profile'),
              onPressed: _saving || !widget.server.profileEditable
                  ? null
                  : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(context.s('profileSave')),
            ),
          ],
        ),
      ),
    ),
  );
}
