import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';
import 'glass_surface.dart';
import 'snapshot_glass.dart';

class NirangAlertDialog extends ConsumerStatefulWidget {
  const NirangAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(22, 14, 22, 8),
    this.blur,
    this.surfaceOpacity,
    this.backdrop,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final EdgeInsetsGeometry contentPadding;
  final double? blur;
  final double? surfaceOpacity;
  final Widget? backdrop;

  @override
  ConsumerState<NirangAlertDialog> createState() => _NirangAlertDialogState();
}

class _NirangAlertDialogState extends ConsumerState<NirangAlertDialog> {
  GlassSnapshot? _snapshot;
  bool _captureScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleSnapshotCapture();
  }

  void _scheduleSnapshotCapture() {
    if (_captureScheduled ||
        widget.backdrop != null ||
        Theme.of(context).brightness != Brightness.dark ||
        ref.read(performanceModeProvider)) {
      return;
    }
    _captureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureSnapshot());
  }

  Future<void> _captureSnapshot() async {
    try {
      final snapshot = await GlassSnapshotRenderer.capture(
        boundaryKey: nirangGlassBackdropBoundaryKey,
        background: Theme.of(context).scaffoldBackgroundColor,
      );
      if (snapshot == null) {
        _captureScheduled = false;
        return;
      }
      if (!mounted) {
        snapshot.dispose();
        return;
      }
      final old = _snapshot;
      setState(() => _snapshot = snapshot);
      old?.dispose();
    } catch (error, stackTrace) {
      _captureScheduled = false;
      debugPrint('Dialog glass capture failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void didUpdateWidget(covariant NirangAlertDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backdrop != widget.backdrop) {
      _snapshot?.dispose();
      _snapshot = null;
      _captureScheduled = false;
      _scheduleSnapshotCapture();
    }
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final maxHeight = MediaQuery.sizeOf(context).height * .78;
    final snapshotBackdrop = _snapshot == null
        ? null
        : GlassSnapshotBackdrop(snapshot: _snapshot!);
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: GlassSurface(
        radius: 22,
        blur: widget.blur ?? (dark ? 16 : 14),
        lightBlurLimit: 16,
        darkBlurLimit: 18,
        surfaceOpacity:
            widget.surfaceOpacity ??
            (dark ? SnapshotGlassTokens.darkSurfaceOpacity : .24),
        liquidDepth: true,
        continuousEdge: dark,
        vibrantDark: dark,
        backdrop: widget.backdrop ?? snapshotBackdrop,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.icon != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
                  child: IconTheme(
                    data: IconThemeData(
                      color: theme.colorScheme.secondary,
                      size: 28,
                    ),
                    child: Center(child: widget.icon),
                  ),
                ),
              ],
              if (widget.title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    widget.icon == null ? 20 : 8,
                    22,
                    0,
                  ),
                  child: DefaultTextStyle(
                    style: theme.textTheme.headlineSmall!.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    child: widget.title!,
                  ),
                ),
              if (widget.content != null)
                Flexible(
                  child: SingleChildScrollView(
                    padding: widget.contentPadding,
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: widget.content!,
                    ),
                  ),
                ),
              if (widget.actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 6,
                    children: widget.actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
