import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
// Pinned vendor: an animating trigger needs its own visibility uniform.
// ignore: implementation_imports
import 'package:liquid_glass_widgets/src/renderer/glass_materialize_scope.dart';
import '../../features/vpn/app_controller.dart';
import 'live_liquid_glass.dart';
import 'menu_activity.dart';
import 'decorative_glass_surface.dart';

class LiquidActionItem<T> {
  const LiquidActionItem({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
  });
  final T value;
  final String label;
  final IconData icon;
  final bool enabled, destructive;
}

/// Keeps the original safe fallback but uses upstream's anchored spring morph
/// on shader-capable devices. No fixed menuHeight: short menus do not scroll.
class LiquidActionMenu<T> extends ConsumerStatefulWidget {
  const LiquidActionMenu({
    required this.items,
    required this.onSelected,
    required this.tooltip,
    required this.fallback,
    this.icon = const Icon(Icons.more_vert_rounded),
    this.serverActions = false,
    this.reuseParentGlass = false,
    this.triggerDecorator,
    this.triggerSettings,
    super.key,
  });
  final List<LiquidActionItem<T>> items;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Widget fallback, icon;
  final bool serverActions;

  /// A control on an optical panel uses the panel's computed backdrop and
  /// upstream vibrancy/rim, rather than refracting the same glass twice.
  /// Standalone controls and popup overlays retain independent premium optics.
  final bool reuseParentGlass;
  // Decorate only the anchored control; the popup lives in its own overlay.
  final Widget Function(Widget trigger)? triggerDecorator;
  final glass.LiquidGlassSettings? triggerSettings;

  @override
  ConsumerState<LiquidActionMenu<T>> createState() =>
      _LiquidActionMenuState<T>();
}

class _LiquidActionMenuState<T> extends ConsumerState<LiquidActionMenu<T>> {
  Object? _menuLease;
  void _visibilityChanged(bool visible) {
    if (visible) {
      _menuLease ??= MenuActivity.begin();
    } else if (_menuLease case final lease?) {
      _menuLease = null;
      MenuActivity.end(lease);
    }
  }

  @override
  void dispose() {
    _visibilityChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final performance = ref.watch(performanceModeProvider);
    final reduced = MediaQuery.highContrastOf(context);
    final theme = Theme.of(context);
    if (performance) {
      final trigger = LayoutBuilder(
        builder: (context, constraints) {
          final side = math.min(
            44.0,
            math.min(constraints.maxWidth, constraints.maxHeight),
          );
          return Align(
            widthFactor: 1,
            heightFactor: 1,
            child: SizedBox.square(
              dimension: side,
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: _ControlDragBoundary(child: widget.fallback),
              ),
            ),
          );
        },
      );
      return widget.triggerDecorator?.call(trigger) ?? trigger;
    }
    final feedbackMode = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.settings.feedbackMode ?? 'haptic',
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) {
        if (reduced || !ready) {
          return widget.triggerDecorator?.call(widget.fallback) ??
              widget.fallback;
        }
        return glass.GlassMenu(
          useRootOverlay: widget.serverActions,
          useGlassTriggerFade: true,
          onVisibilityChanged: _visibilityChanged,
          enableHaptics: feedbackMode == 'haptic',
          autoAdjustToScreen: true,
          menuWidth: (MediaQuery.sizeOf(context).width - 24).clamp(
            160.0,
            280.0,
          ),
          menuPadding: const EdgeInsets.symmetric(vertical: 8),
          menuBorderRadius: 24,
          selectionColor: theme.colorScheme.onSurface.withValues(alpha: .08),
          settings: liquidMessageSettings(
            theme.brightness,
            performanceMode: performance,
          ),
          quality: glass.GlassQuality.premium,
          triggerBuilder: (context, toggle) {
            final reuseHost =
                widget.reuseParentGlass &&
                (context
                        .dependOnInheritedWidgetOfExactType<
                          glass.InheritedLiquidGlass
                        >()
                        ?.avoidsRefraction ??
                    false);
            final trigger = _ControlDragBoundary(
              child: Tooltip(
                message: widget.tooltip,
                // A held row control is an elastic gesture, not a tooltip
                // request. A tooltip in the captured drag overlay also feeds
                // its every-frame layout back into the header capture.
                triggerMode: widget.serverActions
                    ? TooltipTriggerMode.manual
                    : null,
                child: widget.serverActions
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          // Dense ListTile + compact visual density caps trailing
                          // height at 40. Fit both axes, not only the requested height,
                          // or a nominal 44x44 lens is painted as a flattened 44x40 oval.
                          final side = math.min(
                            44.0,
                            math.min(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          );
                          final control = glass.GlassButton.custom(
                            onTap: toggle,
                            label: widget.tooltip,
                            width: side,
                            height: side,
                            shape: const glass.LiquidOval(),
                            stretch: .32,
                            resistance: .012,
                            anchorStretch: false,
                            interactionScale: 1.08,
                            isStationary: false,
                            ambientBaseLight: 0,
                            glowOpacity: 0,
                            glowBlurRadius: 0,
                            canRequestFocus: false,
                            // Keep the proven spring/input, not its optical pass.
                            style: glass.GlassButtonStyle.transparent,
                            useOwnLayer: false,
                            quality: glass.GlassQuality.minimal,
                            child: Builder(
                              builder: (context) {
                                // Treat circle and glyph as one ordinary row:
                                // both pass under the header and into its input.
                                // No animated header mask or capture exclusion.
                                const background = DecorativeGlassSurface(
                                  radius: 100,
                                  compact: true,
                                  child: SizedBox.expand(),
                                );
                                final fade = GlassMaterializeScope.maybeOf(
                                  context,
                                );
                                return Opacity(
                                  opacity: fade?.contentOpacity ?? 1,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    alignment: Alignment.center,
                                    children: [
                                      IgnorePointer(child: background),
                                      Center(
                                        child: IconTheme(
                                          data: IconThemeData(
                                            size: 22,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                          child: widget.icon,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                          return control;
                        },
                      )
                    : glass.GlassButton.custom(
                        onTap: toggle,
                        label: widget.tooltip,
                        width: 44,
                        height: 44,
                        shape: const glass.LiquidOval(),
                        stretch: .32,
                        resistance: .012,
                        anchorStretch: false,
                        interactionScale: 1.08,
                        ambientBaseLight: 0,
                        glowOpacity: 0,
                        glowBlurRadius: 0,
                        canRequestFocus: false,
                        // Only an actual optical host can supply the nested
                        // vibrancy path. BackdropGroup alone is not such a host.
                        useOwnLayer: !reuseHost,
                        settings:
                            widget.triggerSettings ??
                            liquidControlSettings(theme.brightness),
                        quality: glass.GlassQuality.premium,
                        child: IconTheme(
                          data: IconThemeData(
                            color: theme.colorScheme.onSurface,
                            size: 22,
                          ),
                          child: widget.icon,
                        ),
                      ),
              ),
            );
            return widget.triggerDecorator?.call(trigger) ?? trigger;
          },
          items: [
            for (final item in widget.items)
              glass.GlassMenuItem(
                title: item.label,
                icon: Icon(item.icon),
                enabled: item.enabled,
                isDestructive: item.destructive,
                height: 48,
                maxLines: 2,
                titleStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: item.destructive
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                ),
                iconColor: item.destructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
                onTap: () => widget.onSelected(item.value),
              ),
          ],
        );
      },
    );
  }
}

class LiquidConnectButton extends ConsumerWidget {
  const LiquidConnectButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final performance = ref.watch(performanceModeProvider);
    final decorative = DecorativeGlassScope.of(context);
    if (performance) {
      return _ControlDragBoundary(
        child: SizedBox(
          height: 46,
          child: FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: icon,
            label: Text(label),
            style: FilledButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              side: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: .22),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      );
    }
    if (MediaQuery.highContrastOf(context)) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) => _ControlDragBoundary(
        child: glass.GlassButton.custom(
          onTap: onPressed ?? () {},
          enabled: onPressed != null,
          useOwnLayer: true,
          style: decorative
              ? glass.GlassButtonStyle.transparent
              : glass.GlassButtonStyle.filled,
          height: 46,
          width: null,
          shape: const glass.LiquidRoundedRectangle(borderRadius: 18),
          settings: liquidControlSettings(theme.brightness),
          quality: decorative
              ? glass.GlassQuality.minimal
              : ready
              ? glass.GlassQuality.premium
              : glass.GlassQuality.minimal,
          stretch: .25,
          interactionScale: 1.04,
          child: decorative
              ? SizedBox(
                  height: 46,
                  child: DecorativeGlassSurface(
                    radius: 18,
                    compact: true,
                    child: _connectContent(theme),
                  ),
                )
              : _connectContent(theme),
        ),
      ),
    );
  }

  Widget _connectContent(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    ),
  );
}

/// Claim drags on an elastic control without swallowing taps. Upstream tracks
/// deformation with raw pointer events, which alone do not win Flutter's gesture
/// arena against a surrounding list or pager. The control keeps those events;
/// its existing inner tap recognizer still handles a tap normally.
class _ControlDragBoundary extends StatelessWidget {
  const _ControlDragBoundary({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    // Match Scrollable's axis recognizers/slop. Pan's larger slop would let
    // the outer scrollable claim the gesture first on a straight drag.
    onHorizontalDragUpdate: (_) {},
    onVerticalDragUpdate: (_) {},
    child: child,
  );
}

class ConnectionShield extends StatelessWidget {
  const ConnectionShield({
    required this.state,
    required this.color,
    required this.connected,
    required this.reducedEffects,
    super.key,
  });
  final String state;
  final Color color;
  final bool connected, reducedEffects;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(state),
    tween: Tween(begin: reducedEffects ? 1 : 0, end: 1),
    duration: Duration(milliseconds: reducedEffects ? 0 : 420),
    builder: (context, value, child) => Transform.rotate(
      angle: math.sin(value * math.pi) * .13,
      child: Transform.scale(scale: .9 + .1 * value, child: child),
    ),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        connected ? Icons.shield_rounded : Icons.shield_outlined,
        color: color,
        size: 23,
      ),
    ),
  );
}
