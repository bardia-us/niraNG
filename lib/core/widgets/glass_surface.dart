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
  static const liquidThickness = 26.0;
  static const liquidBlur = 9.0;
  static const liquidRefractiveIndex = 1.28;
  static const liquidSaturation = 1.48;

  // Kept for source compatibility with existing call sites and tests. The
  // Liquid Glass path intentionally has one visual recipe instead of separate
  // page-specific strengths.
  static const darkServersHeaderBlur = 7.0;
  static const darkServersTopMenuBlur = 7.0;
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
    this.darkBlur,
    this.saturation,
    this.tintOpacityScale = 1,
    this.visibility = 1,
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
  final double? darkBlur;
  final double? saturation;
  final double tintOpacityScale;
  final double visibility;
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
    double saturation = liquidSaturation,
    double tintOpacityScale = 1,
    double visibility = 1,
  }) {
    final dark = brightness == Brightness.dark;
    return LiquidGlassSettings(
      visibility: visibility,
      thickness: liquidThickness,
      blur: blur,
      refractiveIndex: liquidRefractiveIndex,
      saturation: saturation,
      chromaticAberration: dark ? .0035 : .0045,
      lightIntensity: dark ? 1.0 : 1.25,
      ambientStrength: dark ? .30 : .50,
      lightAngle: .7853981633974483,
      glassColor: dark
          ? Colors.white.withValues(alpha: .012 * tintOpacityScale)
          : Colors.black.withValues(alpha: .008 * tintOpacityScale),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reducedEffects = ref.watch(performanceModeProvider);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    final effectiveRadius = radius.clamp(0.0, double.infinity).toDouble();
    final effectiveVisibility =
        visibility * GlassVisibilityScope.maybeOf(context);

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

    return SizedBox(
      width: double.infinity,
      child: LiquidGlass.withOwnLayer(
        settings: settingsFor(
          theme.brightness,
          blur: theme.brightness == Brightness.dark ? darkBlur ?? blur : blur,
          saturation: saturation ?? liquidSaturation,
          tintOpacityScale: tintOpacityScale,
          visibility: effectiveVisibility,
        ),
        glassContainsChild: false,
        shape: LiquidRoundedRectangle(borderRadius: effectiveRadius),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}

/// Lets transient routes paint their final LiquidGlass geometry before making
/// it visible. Unlike wrapping the filter in Opacity, this keeps the backdrop
/// shader out of an extra saveLayer (which caused the Android black quad).
class GlassVisibilityScope extends InheritedWidget {
  const GlassVisibilityScope({
    required this.visibility,
    required super.child,
    super.key,
  });

  final double visibility;

  static double maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassVisibilityScope>()
          ?.visibility ??
      1;

  @override
  bool updateShouldNotify(GlassVisibilityScope oldWidget) =>
      visibility != oldWidget.visibility;
}
