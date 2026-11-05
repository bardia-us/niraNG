import 'dart:async';
import 'package:flutter/material.dart';
import '../update_checker.dart';
import 'glass_dialog.dart';
import 'release_notes_markdown.dart';

/// Loading belongs inside the visible, dismissible dialog, never behind a
/// silent modal barrier. The startup caller records presentation independently
/// of loading or dismissal; a manual caller can open and retry it at any time.
class WhatsNewDialog extends StatefulWidget {
  const WhatsNewDialog({
    required this.persian,
    required this.loadNotes,
    super.key,
  });
  final bool persian;
  final Future<BilingualReleaseNotes> Function() loadNotes;
  @override
  State<WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewDialogState extends State<WhatsNewDialog> {
  late Future<BilingualReleaseNotes> _notes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _notes = Future<BilingualReleaseNotes>.sync(
      widget.loadNotes,
    ).timeout(const Duration(seconds: 10));
  }

  String _t(String english, String persian) =>
      widget.persian ? persian : english;

  @override
  Widget build(BuildContext context) => FutureBuilder<BilingualReleaseNotes>(
    future: _notes,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final body =
          snapshot.data?.forLanguage(widget.persian ? 'fa' : 'en').trim() ?? '';
      final ready = !loading && !snapshot.hasError && body.isNotEmpty;
      return NirangAlertDialog(
        icon: const Icon(Icons.auto_awesome_rounded),
        title: Text(_t("What's new", 'چه چیزهایی جدید است؟')),
        content: Directionality(
          textDirection: widget.persian ? TextDirection.rtl : TextDirection.ltr,
          child: ready
              ? ReleaseNotesMarkdown(data: body)
              : loading
              ? Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('Loading release notes…', 'در حال دریافت تغییرات…'),
                      ),
                    ),
                  ],
                )
              : Text(
                  _t(
                    'Could not load release notes. Try again or close this window.',
                    'تغییرات دریافت نشد. دوباره تلاش کن یا پنجره را ببند.',
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Close', 'بستن')),
          ),
          if (!loading && !ready)
            TextButton(
              onPressed: () => setState(_load),
              child: Text(_t('Retry', 'تلاش دوباره')),
            ),
          if (ready)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('Got it', 'باشه')),
            ),
        ],
      );
    },
  );
}
