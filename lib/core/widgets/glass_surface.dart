import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';
import '../theme/app_theme.dart';

class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.blur,
    this.lightBlurLimit = 32,
    this.surfaceOpacity,
    this.style = NirangGlassStyle.surface,
    this.showShadow = true,
    this.showBorder = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double? blur;
  final double lightBlurLimit;
  final double? surfaceOpacity;
  final NirangGlassStyle style;
  final bool showShadow;
  final bool showBorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final effectiveBlur = blur ?? NirangGlassTokens.blur(theme, style);
    final tintStrength = switch (style) {
      NirangGlassStyle.chrome => dark ? .025 : .030,
      NirangGlassStyle.popover => dark ? .030 : .035,
      NirangGlassStyle.dialog => dark ? .035 : .040,
      NirangGlassStyle.bottomSheet => dark ? .035 : .040,
      NirangGlassStyle.surface => dark ? .025 : .030,
    };
    final base = Color.alphaBlend(
      scheme.primaryContainer.withValues(alpha: tintStrength),
      scheme.surface,
    );
    final glassColor = base.withValues(
      alpha: reducedEffects
          ? (dark
                ? NirangGlassTokens.reducedDarkAlpha
                : NirangGlassTokens.reducedLightAlpha)
          : surfaceOpacity?.clamp(0, 1) ??
                NirangGlassTokens.alpha(theme, style),
    );
    final preserveDarkGradient =
        dark &&
        !reducedEffects &&
        surfaceOpacity == null &&
        style == NirangGlassStyle.surface;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: preserveDarkGradient ? null : glassColor,
        gradient: preserveDarkGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(
                    alpha: NirangGlassTokens.darkSurfaceTopAlpha,
                  ),
                  scheme.primaryContainer.withValues(
                    alpha: NirangGlassTokens.darkSurfaceBottomAlpha,
                  ),
                ],
              )
            : null,
        border: showBorder
            ? Border.all(
                color: (dark ? scheme.outlineVariant : Colors.white).withValues(
                  alpha: NirangGlassTokens.borderAlpha(theme),
                ),
              )
            : null,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: reducedEffects || !showShadow
            ? null
            : [
                BoxShadow(
                  color: scheme.shadow.withValues(
                    alpha: NirangGlassTokens.shadowAlpha(theme),
                  ),
                  blurRadius: switch (style) {
                    NirangGlassStyle.popover => 18,
                    NirangGlassStyle.dialog => 20,
                    NirangGlassStyle.bottomSheet => 18,
                    _ => 16,
                  },
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: reducedEffects
            ? content
            : BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: dark
                      ? effectiveBlur
                      : effectiveBlur.clamp(0, lightBlurLimit),
                  sigmaY: dark
                      ? effectiveBlur
                      : effectiveBlur.clamp(0, lightBlurLimit),
                ),
                child: content,
              ),
      ),
    );
  }
}
