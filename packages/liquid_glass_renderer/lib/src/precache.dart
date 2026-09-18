import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Loads the programs used by [LiquidGlass] before a surface becomes visible.
///
/// Without this, [ShaderBuilder] deliberately renders only its child while the
/// programs are loaded, which makes dynamically opened dialogs briefly appear
/// as plain transparent panels.
Future<void> precacheLiquidGlassShaders() => Future.wait([
      ShaderBuilder.precacheShader(ShaderKeys.liquidGlassRender),
      ShaderBuilder.precacheShader(ShaderKeys.blendedGeometry),
    ]);
