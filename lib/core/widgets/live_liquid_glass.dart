import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'glass_preparation.dart';

final _preparation = GlassPreparation(
  supported: () => ui.ImageFilter.isShaderFilterSupported,
  initialize: (mode) => glass.LiquidGlassWidgets.initialize(
    warmUpMode: mode,
    enablePerformanceMonitor: false,
  ),
  programsReady: () => glass.LiquidGlassWidgets.premiumShadersReady,
);
final liveGlassReadyListenable = _preparation.ready;
final liveGlassPreparationProvider = Provider<Future<void> Function()>(
  (_) => prepareLiveGlass,
);

// The exact approved Lab clear material: no frost, backer, saturation wash or
// extra backdrop zoom. Only blur differs by surface role, not optical depth.
glass.LiquidGlassSettings liquidSettings(ui.Brightness brightness) =>
    (brightness == ui.Brightness.dark
            ? glass.LiquidGlassSettings.ios27Dark
            : glass.LiquidGlassSettings.ios27Light)
        .copyWith(
          bodyMode: glass.GlassBodyMode.clear,
          glassColor: const ui.Color(0x00000000),
          saturation: 1,
          frost: 0,
          blur: 4.5,
          blurWeight: 1,
          thickness: 40,
          rimLight: 1.3,
          rimShade: .30,
          rimShadeEnds: .12,
          edgeAbsorption: 0,
          lightIntensity: .18,
          fresnelStrength: .3,
          lensModel: glass.GlassLensModel.paraxial,
          backdropZoom: 1,
          shadow: const [],
          shadowElevation: 0,
        );

glass.LiquidGlassSettings _forMode(
  glass.LiquidGlassSettings settings,
  bool performance,
) => performance
    ? settings.copyWith(
        blur: 0,
        frost: 0,
        thickness: 0,
        lightIntensity: 0,
        rimLight: 0,
        rimShade: 0,
        fresnelStrength: 0,
      )
    : settings;

glass.LiquidGlassSettings liquidControlSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) => _forMode(liquidSettings(brightness).copyWith(blur: 2.4), performanceMode);

glass.LiquidGlassSettings liquidServerControlSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) => liquidControlSettings(brightness, performanceMode: performanceMode);

/// Header-specific lighting; does not change optical depth, index or blur.
glass.LiquidGlassSettings liquidServerHeaderSettings(
  ui.Brightness brightness, {
  bool trigger = false,
}) =>
    (trigger
            ? liquidControlSettings(brightness)
            : liquidSurfaceSettings(brightness))
        .copyWith(rimLight: trigger ? .8 : 1.0);

glass.LiquidGlassSettings liquidSurfaceSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) => _forMode(liquidSettings(brightness), performanceMode);

// Settings/dialog menus deliberately have less blur than headers. The bevel,
// normal map, refraction, rim and depth remain the same approved clear lens.
glass.LiquidGlassSettings liquidMessageSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) => _forMode(liquidSettings(brightness).copyWith(blur: 3.5), performanceMode);

/// Shares one local load, bounds startup to two seconds and keeps the visible
/// fallback only until verified premium programs are ready. No network work.
Future<void> prepareLiveGlass() => _preparation.prepare();
