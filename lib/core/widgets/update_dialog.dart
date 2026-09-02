import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../platform/nirang_native.dart';
import '../update_checker.dart';
import 'glass_dialog.dart';

Future<void> showUpdateOptionsDialog(
  BuildContext context,
  ReleaseCheckResult release,
) async {
  final supportedAbis = await NirangNative.supportedAbis();
  final asset = release.assetForAbis(supportedAbis);
  if (!context.mounted) return;
  if (asset == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.s('updateApkUnavailable'))));
    return;
  }
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: !release.mandatory,
    builder: (dialogContext) => NirangAlertDialog(
      icon: const Icon(Icons.new_releases_outlined),
      title: Text(dialogContext.s('newVersionAvailable')),
      content: Text('${release.latestVersion}\n${asset.name}'),
      actions: [
        if (!release.mandatory)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'later'),
            child: Text(dialogContext.s('later')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'browser'),
          child: Text(dialogContext.s('downloadWithBrowser')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, 'install'),
          icon: const Icon(Icons.download_rounded),
          label: Text(dialogContext.s('downloadAndInstall')),
        ),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'browser') {
    await NirangNative.openExternalUrl(asset.downloadUrl.toString());
  } else if (choice == 'install') {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDownloadDialog(asset: asset),
    );
  }
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.asset});

  final ReleaseAsset asset;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  int _received = 0;
  int _total = 0;
  bool _installing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = NirangNative.updateDownloadEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _received = (event['received'] as num?)?.toInt() ?? _received;
        _total = (event['total'] as num?)?.toInt() ?? _total;
        _installing = event['state'] == 'installing';
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _download());
  }

  Future<void> _download() async {
    try {
      await NirangNative.downloadAndInstallUpdate(
        url: widget.asset.downloadUrl.toString(),
        size: widget.asset.size,
        sha256: widget.asset.sha256,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = context.s('updateDownloadFailed'));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return PopScope(
      canPop: _error != null,
      child: NirangAlertDialog(
        icon: Icon(
          _error == null ? Icons.download_rounded : Icons.error_outline,
        ),
        title: Text(
          _error != null
              ? context.s('updateDownloadFailed')
              : _installing
              ? context.s('preparingInstaller')
              : context.s('downloadingUpdate'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Text(_error!)
            else ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 10),
              Text(
                progress == null
                    ? context.s('downloadingUpdate')
                    : '${(progress * 100).round()}%',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: _error == null
            ? const []
            : [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.s('later')),
                ),
                FilledButton(
                  onPressed: () async {
                    await NirangNative.openExternalUrl(
                      widget.asset.downloadUrl.toString(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(context.s('downloadWithBrowser')),
                ),
              ],
      ),
    );
  }
}
