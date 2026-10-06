import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

final liveGlassReadyListenable = ValueNotifier<bool>(false);
Future<void>? _preparation;
glass.LiquidGlassSettings liquidSettings(ui.Brightness brightness) =>
    (brightness == ui.Brightness.dark
            ? glass.LiquidGlassSettings.ios27Dark
            : glass.LiquidGlassSettings.ios27Light)
        .copyWith(
          // The native 14px frost already supplies the broad blur. A second
          // pre-blur + luminance-weight pass per shape is especially costly
          // while two pages are live. Keep the full-mode ghost/cloud mix,
          // but sample its sharp ghost through upstream's six-tap branch.
          blur: 0,
          blurWeight: 1,
          frostWeight: 1,
          // Use upstream's curved Snell bevel and actual normal-driven light
          // lobes, rather than only the thin-prism band/hairline preset.
          lensModel: glass.GlassLensModel.spherical,
          lightIntensity: .35,
          fresnelStrength: .18,
        );

glass.LiquidGlassSettings liquidControlSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) => _performanceOptics(liquidSettings(brightness), performanceMode);

glass.LiquidGlassSettings _performanceOptics(
  glass.LiquidGlassSettings settings,
  bool performanceMode,
) => !performanceMode
    ? settings
    : settings.copyWith(
        frostOpacity: 1,
        // At full cloud opacity the upstream sampler never reads its ghost.
        // Its Gaussian frost still supplies the visible blur; a separate
        // pre-blur and weighted-alpha read would just add compositor passes.
        blur: 0,
        blurWeight: 1,
        frostWeight: 1,
      );

/// Panel bodies differ from small controls; refraction and rims stay upstream.
glass.LiquidGlassSettings liquidSurfaceSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) {
  var settings = liquidSettings(brightness);
  settings = _performanceOptics(settings, performanceMode).copyWith(
    // One continuous native Gaussian feeds the optical shader in both themes.
    // Replace the interleaved frost/ghost path, which preserves sharp detail;
    // do not stack another blur pass or change the small-control material.
    frost: 0,
    blur: performanceMode ? 6 : 8,
    frostClamp: 0,
  );
  if (brightness == ui.Brightness.dark) {
    settings = settings.copyWith(
      bodyMode: glass.GlassBodyMode.clear,
      // Neutral transmission without washing the entire dark canvas grey.
      glassColor: const ui.Color(0x0FFFFFFF),
      rimShadeEnds: .2,
    );
  }
  // Light tint and all lens/rim/motion settings stay unchanged.
  return settings;
}

/// Large messages need a narrower, quieter bevel than small controls.
/// The body remains neutral/transparent; no dark backer or whitening veil.
glass.LiquidGlassSettings liquidMessageSettings(
  ui.Brightness brightness, {
  bool performanceMode = false,
}) {
  final settings = liquidSurfaceSettings(
    brightness,
    performanceMode: performanceMode,
  );
  if (brightness != ui.Brightness.dark) return settings;
  return settings.copyWith(
    thickness: 18,
    refractiveIndex: 1.12,
    lightIntensity: .12,
    fresnelStrength: .08,
    rimLight: .55,
  );
}

/// Does not delay the first frame or any access-policy check. Failure/timeout
/// locks this session to the visible shader-free fallback.
Future<void> prepareLiveGlass() => _preparation ??= _prepare();
Future<void> _prepare() async {
  if (!ui.ImageFilter.isShaderFilterSupported) return;
  try {
    await glass.LiquidGlassWidgets.initialize(
      warmUpMode: glass.GlassWarmUpMode.always,
      enablePerformanceMonitor: false,
    ).timeout(const Duration(seconds: 2));
    liveGlassReadyListenable.value =
        glass.LiquidGlassWidgets.premiumShadersReady;
  } on Object {
    liveGlassReadyListenable.value = false;
  }
}
