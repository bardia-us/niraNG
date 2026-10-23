import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
// Pinned vendor's materialize channels also drive the shader-free fallback.
// ignore: implementation_imports
import 'package:liquid_glass_widgets/src/renderer/glass_materialize_scope.dart';

import '../../features/vpn/app_controller.dart';
import 'live_liquid_glass.dart';
import 'decorative_glass_surface.dart';

/// Shared upstream material. Legacy hints preserve source compatibility, not
/// different optical recipes: normal mode uses the approved preset, while
/// Performance Mode uses opaque surfaces without any optical passes.
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
    this.backdropBlur,
    this.opticalSettings,
  });
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius, blur, tintOpacityScale, visibility;
  final double lightBlurLimit, darkBlurLimit;
  final double? darkBlur, saturation, surfaceOpacity;
  final bool liquidDepth, continuousEdge, vibrantDark, showShadow;
  final bool messageSurface;

  /// A local diffusion override for text-rich dialogs, not a tint/backer.
  final double? backdropBlur;
  final glass.LiquidGlassSettings? opticalSettings;

  static glass.LiquidGlassSettings settingsFor(
    Brightness brightness, {
    double blur = liquidBlur,
    double saturation = liquidSaturation,
    double tintOpacityScale = 1,
    double visibility = 1,
    bool messageSurface = false,
    double? backdropBlur,
  }) =>
      (messageSurface
              ? liquidMessageSettings(brightness)
              : liquidSurfaceSettings(brightness))
          .copyWith(visibility: visibility, blur: backdropBlur);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final performance = ref.watch(performanceModeProvider);
    final reduced = MediaQuery.highContrastOf(context);
    final visible = (visibility * GlassVisibilityScope.maybeOf(context)).clamp(
      0.0,
      1.0,
    );
    final settings =
        opticalSettings ??
        settingsFor(
          theme.brightness,
          messageSurface: messageSurface,
          backdropBlur: backdropBlur,
        );
    final fallbackVisibility =
        visible * (GlassMaterializeScope.maybeOf(context)?.glassProgress ?? 1);
    final content = Material(
      type: MaterialType.transparency,
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    if (performance) {
      return Opacity(
        opacity: fallbackVisibility,
        child: FrostedSurface(radius: radius, opaque: true, child: content),
      );
    }
    if (DecorativeGlassScope.of(context)) {
      return Opacity(
        opacity: fallbackVisibility,
        child: DecorativeGlassSurface(radius: radius, child: content),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      builder: (context, ready, _) {
        if (!reduced && ready && ui.ImageFilter.isShaderFilterSupported) {
          final foreground = glass.InheritedLiquidGlass(
            settings: settings,
            quality: glass.GlassQuality.premium,
            avoidsRefraction: true,
            child: content,
          );
          // Only non-overlapping Home cards with the exact same material join
          // this owner. Menus and surfaces fading independently keep a layer.
          final shared =
              !messageSurface &&
              visible == 1 &&
              (GlassMaterializeScope.maybeOf(context)?.glassProgress ?? 1) ==
                  1 &&
              _SharedSurfaceScope.maybeOf(context)?.settings == settings;
          return glass.AdaptiveGlass(
            quality: glass.GlassQuality.premium,
            allowElevation: false,
            useOwnLayer: !shared,
            settings: settings.copyWith(
              visibility: visible.clamp(.000001, 1.0),
            ),
            shape: glass.LiquidRoundedRectangle(borderRadius: radius),
            child: foreground,
          );
        }
        return Opacity(
          opacity: fallbackVisibility,
          child: FrostedSurface(
            radius: radius,
            opaque: reduced,
            sigma: backdropBlur ?? 12,
            child: content,
          ),
        );
      },
    );
  }
}

/// One native optical pass for non-overlapping surfaces of one material.
/// This is deliberately opt-in: layered cards/menus must not be batched.
class SharedGlassSurfaces extends ConsumerWidget {
  const SharedGlassSurfaces({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(performanceModeProvider) ||
        MediaQuery.highContrastOf(context) ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return child;
    }
    final settings = liquidSurfaceSettings(Theme.of(context).brightness);
    return ValueListenableBuilder<bool>(
      valueListenable: liveGlassReadyListenable,
      child: child,
      builder: (context, ready, child) => !ready
          ? child!
          : ClipRect(
              child: glass.LiquidGlassLayer(
                settings: settings,
                child: _SharedSurfaceScope(settings: settings, child: child!),
              ),
            ),
    );
  }
}

class _SharedSurfaceScope extends InheritedWidget {
  const _SharedSurfaceScope({required this.settings, required super.child});
  final glass.LiquidGlassSettings settings;
  static _SharedSurfaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SharedSurfaceScope>();
  @override
  bool updateShouldNotify(_SharedSurfaceScope oldWidget) =>
      settings != oldWidget.settings;
}

/// Ordinary translucency, never presented as optical refraction.
class FrostedSurface extends ConsumerWidget {
  const FrostedSurface({
    required this.child,
    this.radius = 0,
    this.opaque = false,
    this.sigma = 12,
    this.tintAlpha,
    this.backdropKey,
    super.key,
  });
  final Widget child;
  final double radius;
  final bool opaque;
  final double sigma;
  final double? tintAlpha;
  final BackdropKey? backdropKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final solid = opaque || ref.watch(performanceModeProvider);
    final surface = ColoredBox(
      color: scheme.surfaceContainerHigh.withValues(
        alpha: solid ? 1 : (tintAlpha ?? .76).clamp(0, 1),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: solid
          ? surface
          : BackdropFilter(
              backdropGroupKey: backdropKey,
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
