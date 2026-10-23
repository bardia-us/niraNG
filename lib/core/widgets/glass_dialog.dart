import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import 'glass_surface.dart';
import 'clay_surface.dart';
import 'menu_activity.dart';
import 'decorative_glass_surface.dart';

Future<T?> showNirangDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = Colors.transparent,
  VoidCallback? onShown,
}) {
  final decorative = DecorativeGlassScope.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, _, _) => MenuActivityScope(
      child: DecorativeGlassScope(
        enabled: decorative,
        child: _DialogShown(onShown: onShown, child: builder(dialogContext)),
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        glass.GlassMaterializeTransition(
          animation: animation,
          scaleFrom: MediaQuery.disableAnimationsOf(context) ? 1 : 1.04,
          contentSigma: MediaQuery.disableAnimationsOf(context) ? 0 : 2.5,
          child: child,
        ),
  );
}

// Preserve the existing post-entrance callback (update/consent prompts), while
// glass and foreground share Lab's materialize timeline on BOTH entrance/exit.
class _DialogShown extends StatefulWidget {
  const _DialogShown({required this.child, this.onShown});
  final Widget child;
  final VoidCallback? onShown;
  @override
  State<_DialogShown> createState() => _DialogShownState();
}

class _DialogShownState extends State<_DialogShown> {
  Animation<double>? _animation;
  bool _shown = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _animation) {
      _animation?.removeStatusListener(_status);
      _animation = animation;
      animation?.addStatusListener(_status);
    }
    if (animation == null || animation.isCompleted) {
      _status(AnimationStatus.completed);
    }
  }

  void _status(AnimationStatus status) {
    if (status != AnimationStatus.completed || _shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shown || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _shown = true;
      widget.onShown?.call();
    });
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_status);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class NirangAlertDialog extends StatelessWidget {
  const NirangAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(22, 14, 22, 8),
    this.scrollContent = true,
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final EdgeInsetsGeometry contentPadding;
  final bool scrollContent;

  // Paint the clay INSIDE ButtonStyleButton, using its real input states.
  // An outer decoration is covered by FilledButton's opaque Material and
  // cannot respond to keyboard, pointer cancellation or disabled state.
  ButtonStyle _actionStyle(ThemeData theme) => ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    backgroundBuilder: (context, states, child) {
      final scheme = theme.colorScheme;
      final disabled = states.contains(WidgetState.disabled);
      final button = context.widget;
      final explicitColor = button is ButtonStyleButton
          ? button.style?.backgroundColor?.resolve(states)
          : null;
      final inheritedColor = theme.filledButtonTheme.style?.backgroundColor
          ?.resolve(states);
      final base =
          explicitColor ??
          inheritedColor ??
          (disabled ? scheme.surfaceContainerHigh : scheme.primary);
      final emphasized =
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused);
      return ClayPress(
        pressed: !disabled && states.contains(WidgetState.pressed),
        child: ClaySurface(
          radius: 18,
          color: emphasized && !disabled
              ? Color.alphaBlend(scheme.onSurface.withValues(alpha: .04), base)
              : base,
          child: child ?? const SizedBox.shrink(),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * .86;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: GlassSurface(
        messageSurface: true,
        // Spread background lettering, not foreground text. Keep the clear
        // lens/tint/Clay actions and small popover menus' original material.
        backdropBlur: 11,
        radius: 28,
        blur: GlassSurface.liquidBlur,
        child: ListTileTheme.merge(
          // ListTile's InkWell uses this same shape for splash and highlight,
          // including radio choices and switches inside settings dialogs.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                    child: scrollContent
                        ? SingleChildScrollView(
                            // The app's bouncing list physics can move even a
                            // zero-extent form. Clamp here: only real overflow
                            // scrolls, including when the keyboard takes space.
                            physics: const ClampingScrollPhysics(),
                            padding: contentPadding,
                            child: DefaultTextStyle(
                              style: theme.textTheme.bodyMedium!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              child: content!,
                            ),
                          )
                        : Padding(
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
                    child: Theme(
                      data: theme.copyWith(
                        filledButtonTheme: FilledButtonThemeData(
                          style: _actionStyle(
                            theme,
                          ).merge(theme.filledButtonTheme.style),
                        ),
                      ),
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 6,
                        children: [
                          for (final action in actions)
                            if (action is FilledButton)
                              action
                            else
                              // Preserve secondary/custom actions' existing
                              // clay wrapper and clipping/input behavior.
                              ClaySurface(
                                radius: 18,
                                color: theme.colorScheme.surfaceContainerHigh,
                                child: action,
                              ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
