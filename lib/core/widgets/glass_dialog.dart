import 'package:flutter/material.dart';

import 'glass_surface.dart';

Future<T?> showNirangDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = Colors.transparent,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: barrierColor,
  transitionDuration: const Duration(milliseconds: 130),
  pageBuilder: (dialogContext, _, _) =>
      _PrimedDialogEntrance(child: builder(dialogContext)),
  transitionBuilder: (context, animation, secondaryAnimation, child) {
    // Keep the route painted while opening so LiquidGlass can register its
    // geometry before the first visible frame. Only the exit uses the route
    // animation; the entrance is controlled by _PrimedDialogEntrance.
    if (animation.status != AnimationStatus.reverse) return child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInCubic),
      child: child,
    );
  },
);

class _PrimedDialogEntrance extends StatefulWidget {
  const _PrimedDialogEntrance({required this.child});

  final Widget child;

  @override
  State<_PrimedDialogEntrance> createState() => _PrimedDialogEntranceState();
}

class _PrimedDialogEntranceState extends State<_PrimedDialogEntrance> {
  bool _glassReady = false;

  @override
  void initState() {
    super.initState();
    _primeGlass();
  }

  Future<void> _primeGlass() async {
    // LiquidGlass needs a completed paint to create its shape/backdrop layer.
    // Paint the final geometry invisibly, then reveal that same widget instance.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _glassReady = true);
  }

  @override
  Widget build(BuildContext context) => GlassVisibilityScope(
    visibility: _glassReady ? 1 : 0,
    child: widget.child,
  );
}

class NirangAlertDialog extends StatelessWidget {
  const NirangAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(22, 14, 22, 8),
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * .78;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: GlassSurface(
        radius: 28,
        blur: GlassSurface.liquidBlur,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
                  child: IconTheme(
                    data: IconThemeData(
                      color: theme.colorScheme.secondary,
                      size: 28,
                    ),
                    child: Center(child: icon),
                  ),
                ),
              ],
              if (title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    icon == null ? 20 : 8,
                    22,
                    0,
                  ),
                  child: DefaultTextStyle(
                    style: theme.textTheme.headlineSmall!.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    child: title!,
                  ),
                ),
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    padding: contentPadding,
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: content!,
                    ),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 6,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
