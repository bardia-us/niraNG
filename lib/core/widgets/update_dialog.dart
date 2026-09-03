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
      barrierDismissible: true,
      builder: (_) => _UpdateDownloadDialog(
        asset: asset,
        version: release.latestVersion.toString(),
      ),
    );
  }
}

class UpdateDownloadSettingsTile extends StatefulWidget {
  const UpdateDownloadSettingsTile({super.key});

  @override
  State<UpdateDownloadSettingsTile> createState() =>
      _UpdateDownloadSettingsTileState();
}

class _UpdateDownloadSettingsTileState
    extends State<UpdateDownloadSettingsTile> {
  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  _DownloadSnapshot _download = const _DownloadSnapshot();

  @override
  void initState() {
    super.initState();
    _subscription = NirangNative.updateDownloadEvents.listen(_apply);
    unawaited(NirangNative.getUpdateDownload().then(_apply));
  }

  void _apply(Map<dynamic, dynamic> event) {
    if (mounted) setState(() => _download = _DownloadSnapshot.fromMap(event));
  }

  Future<void> _action(Future<Map<dynamic, dynamic>> Function() action) async {
    try {
      _apply(await action());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('operationFailed'))));
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _download;
    final progress = d.total > 0
        ? (d.received / d.total).clamp(0.0, 1.0)
        : null;
    return ListTile(
      leading: Icon(
        d.complete ? Icons.download_done_rounded : Icons.downloading_rounded,
      ),
      title: Text(context.s('updateDownloads')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_statusText(context, d)),
          if (d.active || d.canResume) ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text('${_bytes(d.received)} / ${_bytes(d.total)}'),
          ],
        ],
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          if (d.active)
            IconButton(
              tooltip: context.s('cancel'),
              onPressed: () => _action(NirangNative.cancelUpdateDownload),
              icon: const Icon(Icons.pause_rounded),
            )
          else if (d.canResume)
            IconButton(
              tooltip: context.s('resumeDownload'),
              onPressed: () => _action(NirangNative.resumeUpdateDownload),
              icon: const Icon(Icons.play_arrow_rounded),
            )
          else if (d.complete)
            IconButton(
              tooltip: context.s('install'),
              onPressed: NirangNative.installDownloadedUpdate,
              icon: const Icon(Icons.install_mobile_rounded),
            ),
          if (d.failed && d.url.isNotEmpty)
            IconButton(
              tooltip: context.s('downloadWithBrowser'),
              onPressed: () => NirangNative.openExternalUrl(d.url),
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
          if (!d.idle)
            IconButton(
              tooltip: context.s('delete'),
              onPressed: () => _action(NirangNative.deleteUpdateDownload),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.asset, required this.version});
  final ReleaseAsset asset;
  final String version;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  StreamSubscription<Map<dynamic, dynamic>>? _subscription;
  _DownloadSnapshot _download = const _DownloadSnapshot(state: 'downloading');
  bool _installerOpened = false;

  @override
  void initState() {
    super.initState();
    _subscription = NirangNative.updateDownloadEvents.listen(_apply);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      _apply(
        await NirangNative.startUpdateDownload(
          url: widget.asset.downloadUrl.toString(),
          size: widget.asset.size,
          name: widget.asset.name,
          version: widget.version,
          sha256: widget.asset.sha256,
        ),
      );
    } catch (_) {
      _apply(const {'state': 'failed'});
    }
  }

  void _apply(Map<dynamic, dynamic> event) {
    if (!mounted) return;
    final next = _DownloadSnapshot.fromMap(event);
    setState(() => _download = next);
    if (next.complete && !_installerOpened) {
      _installerOpened = true;
      unawaited(NirangNative.installDownloadedUpdate());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _download;
    final progress = d.total > 0
        ? (d.received / d.total).clamp(0.0, 1.0)
        : null;
    return NirangAlertDialog(
      icon: Icon(d.failed ? Icons.error_outline : Icons.download_rounded),
      title: Text(
        d.failed
            ? context.s('updateDownloadFailed')
            : context.s('downloadingUpdate'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 10),
          Text('${_bytes(d.received)} / ${_bytes(d.total)}'),
          const SizedBox(height: 6),
          Text(context.s('downloadContinuesInBackground')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.s('hide')),
        ),
        if (d.failed)
          TextButton(
            onPressed: () async {
              await NirangNative.openExternalUrl(
                widget.asset.downloadUrl.toString(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(context.s('downloadWithBrowser')),
          ),
      ],
    );
  }
}

class _DownloadSnapshot {
  const _DownloadSnapshot({
    this.state = 'idle',
    this.received = 0,
    this.total = 0,
    this.name = '',
    this.version = '',
    this.url = '',
    this.canResume = false,
    this.canInstall = false,
  });

  factory _DownloadSnapshot.fromMap(Map<dynamic, dynamic> map) =>
      _DownloadSnapshot(
        state: '${map['state'] ?? 'idle'}',
        received: (map['received'] as num?)?.toInt() ?? 0,
        total: (map['total'] as num?)?.toInt() ?? 0,
        name: '${map['name'] ?? ''}',
        version: '${map['version'] ?? ''}',
        url: '${map['url'] ?? ''}',
        canResume: map['canResume'] == true,
        canInstall: map['canInstall'] == true,
      );

  final String state;
  final int received;
  final int total;
  final String name;
  final String version;
  final String url;
  final bool canResume;
  final bool canInstall;
  bool get active => state == 'downloading';
  bool get complete => state == 'complete' && canInstall;
  bool get failed => state == 'failed';
  bool get idle => state == 'idle' && received == 0;
}

String _statusText(BuildContext context, _DownloadSnapshot d) {
  if (d.active) return context.s('downloadingUpdate');
  if (d.complete) return '${context.s('readyToInstall')} ${d.version}'.trim();
  if (d.canResume) return context.s('downloadPaused');
  if (d.failed) return context.s('updateDownloadFailed');
  return context.s('noUpdateDownload');
}

String _bytes(int value) {
  if (value <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var amount = value.toDouble();
  var unit = 0;
  while (amount >= 1024 && unit < units.length - 1) {
    amount /= 1024;
    unit++;
  }
  return '${amount >= 100 || unit == 0 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(1)} ${units[unit]}';
}
