import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../vpn/app_controller.dart';

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
        if (field.value.text.trim() != _initial[field.key])
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s('profileSaved'))));
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s('profileSaveFailed'))));
    }
  }

  String? _validateMask(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      if (jsonDecode(raw) is Map<String, dynamic>) return null;
    } catch (_) {
      // Native validation is authoritative; catch obvious JSON errors here.
    }
    return context.s('profileInvalid');
  }

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
              TextFormField(
                key: ValueKey('profile-${field.key}'),
                controller: field.value,
                enabled: !_saving,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                minLines: field.key == 'fm' ? 3 : 1,
                maxLines: field.key == 'fm' ? 8 : 1,
                decoration: InputDecoration(
                  labelText: switch (field.key) {
                    'sni' => 'SNI',
                    'fp' => 'Fingerprint',
                    'cs' => 'Cipher suites',
                    'fm' => 'FinalMask JSON',
                    _ => 'ALPN',
                  },
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
