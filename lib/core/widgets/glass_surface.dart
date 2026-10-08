import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import '../../features/vpn/app_controller.dart';
import 'live_liquid_glass.dart';

/// Shared upstream material. Legacy hints preserve source compatibility, not
/// different optical recipes: all premium surfaces use the approved preset.
class GlassSurface extends ConsumerWidget {
  static const liquidBlur = 2.4;
  static const liquidSaturation = 1.4;
  static const darkServersHeaderBlur = liquidBlur;
  static const darkServersTopMenuBlur = liquidBlur;
  static const darkServerActionsBlur = liquidBlur;
  static const darkDialogBlur = liquidBlur;
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
    this.messageSurface = false,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius, blur, tintOpacityScale, visibility;
  final double lightBlurLimit, darkBlurLimit;
  final double? darkBlur, saturation, surfaceOpacity;
  final bool liquidDepth, continuousEdge, vibrantDark, showShadow;
  final bool messageSurface;

  static glass.LiquidGlassSettings settingsFor(
    Brightness brightness, {
    double blur = liquidBlur,
    double saturation = liquidSaturation,
    double tintOpacityScale = 1,
    double visibility = 1,
  }) => liquidSurfaceSettings(brightness).copyWith(visibility: visibility);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final performance = ref.watch(performanceModeProvider);
    final reduced = MediaQuery.highContrastOf(context);
    final visible = (visibility * GlassVisibilityScope.maybeOf(context)).clamp(
      0.0,
      1.0,
    );
    final settings = messageSurface
        ? liquidMessageSettings(theme.brightness, performanceMode: performance)
        : liquidSurfaceSettings(theme.brightness, performanceMode: performance);
    final content = Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) {
        if (!reduced && ready && ui.ImageFilter.isShaderFilterSupported) {
          return glass.AdaptiveGlass(
            quality: glass.GlassQuality.premium,
            allowElevation: false,
            settings: settings.copyWith(
              // AdaptiveGlass removes its optical subtree at exactly zero.
              // Keep it painting below visible precision while dialogs prime,
              // so the first visible frame already has backdrop geometry.
              visibility: visible.clamp(.000001, 1.0),
            ),
            shape: glass.LiquidRoundedRectangle(borderRadius: radius),
            child: glass.InheritedLiquidGlass(
              settings: settings,
              quality: glass.GlassQuality.premium,
              avoidsRefraction: true,
              child: content,
            ),
          );
        }
        return Opacity(
          opacity: visible,
          child: FrostedSurface(
            radius: radius,
            opaque: reduced,
            sigma: performance ? 8 : 12,
            child: content,
          ),
        );
      },
    );
  }
}

/// Ordinary translucency, never presented as optical refraction.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    required this.child,
    this.radius = 0,
    this.opaque = false,
    this.sigma = 12,
    this.tintAlpha,
    super.key,
  });
  final Widget child;
  final double radius;
  final bool opaque;
  final double sigma;
  final double? tintAlpha;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = ColoredBox(
      color: scheme.surfaceContainerHigh.withValues(
        alpha: opaque ? 1 : (tintAlpha ?? .76).clamp(0, 1),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: opaque
          ? surface
          : BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: surface,
            ),
    );
  }
}

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
