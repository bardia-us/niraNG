import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import '../../features/vpn/app_controller.dart';
import 'live_liquid_glass.dart';
import 'menu_activity.dart';

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
    super.key,
  });
  final List<LiquidActionItem<T>> items;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Widget fallback, icon;
  final bool serverActions;
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
    final feedbackMode = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.settings.feedbackMode ?? 'haptic',
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) {
        if (reduced || !ready) return widget.fallback;
        return glass.GlassMenu(
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
          settings: liquidSurfaceSettings(
            theme.brightness,
            performanceMode: performance,
          ),
          quality: glass.GlassQuality.premium,
          triggerBuilder: (context, toggle) => Tooltip(
            message: widget.tooltip,
            child: widget.serverActions
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      // Dense ListTile + compact visual density caps trailing
                      // height at 40. Fit both axes, not only the requested height,
                      // or a nominal 44x44 lens is painted as a flattened 44x40 oval.
                      final side = math.min(
                        44.0,
                        math.min(constraints.maxWidth, constraints.maxHeight),
                      );
                      return glass.GlassButton.custom(
                        onTap: toggle,
                        label: widget.tooltip,
                        width: side,
                        height: side,
                        shape: const glass.LiquidOval(),
                        stretch: 0,
                        interactionScale: 1,
                        isStationary: true,
                        useOwnLayer: true,
                        settings: liquidControlSettings(
                          theme.brightness,
                          performanceMode: performance,
                        ),
                        quality: glass.GlassQuality.premium,
                        child: IconTheme(
                          data: IconThemeData(
                            size: 22,
                            color: theme.colorScheme.onSurface,
                          ),
                          child: widget.icon,
                        ),
                      );
                    },
                  )
                : glass.GlassIconButton(
                    icon: widget.icon,
                    onPressed: toggle,
                    semanticLabel: widget.tooltip,
                    size: 44,
                    // A BackdropGroup is not a geometry/render layer. Standalone
                    // row triggers must provision one; nested triggers need their
                    // own lens to retain the requested raised optical control.
                    useOwnLayer: true,
                    settings: liquidControlSettings(
                      theme.brightness,
                      performanceMode: performance,
                    ),
                    quality: glass.GlassQuality.premium,
                  ),
          ),
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
    if (MediaQuery.highContrastOf(context)) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: Text(label),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) => glass.GlassButton.custom(
        onTap: onPressed ?? () {},
        enabled: onPressed != null,
        useOwnLayer: true,
        height: 46,
        width: null,
        shape: const glass.LiquidRoundedRectangle(borderRadius: 18),
        settings: liquidControlSettings(
          theme.brightness,
          performanceMode: ref.watch(performanceModeProvider),
        ),
        quality: ready
            ? glass.GlassQuality.premium
            : glass.GlassQuality.minimal,
        stretch: .25,
        interactionScale: 1.04,
        child: Padding(
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
        ),
      ),
    );
  }
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
