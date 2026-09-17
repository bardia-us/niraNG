import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../features/vpn/app_controller.dart';

/// The single glass renderer used by niraNG chrome, cards, menus and dialogs.
///
/// Visual hints from the previous BackdropFilter implementation remain in the
/// constructor so existing call sites keep their layout and behavior. Normal
/// mode deliberately uses one Liquid Glass recipe everywhere; Performance
/// Mode replaces it with a fully opaque Material surface.
class GlassSurface extends ConsumerWidget {
  static const liquidThickness = 17.0;
  static const liquidBlur = 9.0;
  static const liquidRefractiveIndex = 1.21;
  static const liquidSaturation = 1.25;
  static const liquidChromaticAberration = .002;

  // Kept for source compatibility with existing call sites and tests. The
  // Liquid Glass path intentionally has one visual recipe instead of separate
  // page-specific strengths.
  static const darkServersHeaderBlur = 22.0;
  static const darkServersTopMenuBlur = 20.0;
  static const darkServerActionsBlur = 14.0;
  static const darkDialogBlur = 18.0;
  static const darkInteractiveOpacity = .24;
  static const lightInteractiveOpacity = .11;

  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.blur = liquidBlur,
    this.lightBlurLimit = 16,
    this.darkBlurLimit = 60,
    this.surfaceOpacity,
    this.liquidDepth = false,
    this.continuousEdge = false,
    this.vibrantDark = false,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final double lightBlurLimit;
  final double darkBlurLimit;
  final double? surfaceOpacity;
  final bool liquidDepth;
  final bool continuousEdge;
  final bool vibrantDark;
  final bool showShadow;

  static LiquidGlassSettings settingsFor(
    Brightness brightness, {
    double blur = liquidBlur,
  }) {
    final dark = brightness == Brightness.dark;
    return LiquidGlassSettings(
      thickness: liquidThickness,
      blur: blur,
      refractiveIndex: liquidRefractiveIndex,
      saturation: liquidSaturation,
      chromaticAberration: liquidChromaticAberration,
      lightIntensity: dark ? .72 : .95,
      ambientStrength: dark ? .20 : .34,
      lightAngle: .7853981633974483,
      glassColor: dark
          ? Colors.white.withValues(alpha: .025)
          : Colors.black.withValues(alpha: .015),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reducedEffects = ref.watch(performanceModeProvider);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    final effectiveRadius = radius.clamp(0.0, double.infinity).toDouble();

    if (reducedEffects) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(effectiveRadius),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .56),
          ),
        ),
        child: content,
      );
    }

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        // The non-positioned foreground below establishes the surface's final
        // size. The renderer receives exactly those finite bounds, matching
        // the proven Glass Test Lab structure instead of relying on intrinsic
        // geometry inside menus, dialogs, and scrolling lists.
        Positioned.fill(
          child: IgnorePointer(
            child: LiquidGlassLayer(
              settings: settingsFor(theme.brightness, blur: blur),
              useBackdropGroup: true,
              child: LiquidGlass(
                glassContainsChild: false,
                shape: LiquidRoundedRectangle(borderRadius: effectiveRadius),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        // Paint controls once, above the glass, so they stay sharp and retain
        // their original semantics and hit testing.
        content,
      ],
    );
  }
}
