import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';

class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.blur = 11,
    this.lightBlurLimit = 14,
    this.surfaceOpacity,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final double lightBlurLimit;
  final double? surfaceOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final lightTop = scheme.surface.withValues(alpha: .84);
    final lightBottom = Color.alphaBlend(
      scheme.primaryContainer.withValues(alpha: .065),
      scheme.surface,
    ).withValues(alpha: .80);
    final overriddenSurface = surfaceOpacity == null
        ? null
        : Color.alphaBlend(
            scheme.primaryContainer.withValues(alpha: dark ? .035 : .025),
            scheme.surface,
          ).withValues(alpha: surfaceOpacity!.clamp(0, 1));
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: reducedEffects || overriddenSurface != null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dark ? scheme.surface.withValues(alpha: .66) : lightTop,
                  dark
                      ? scheme.primaryContainer.withValues(alpha: .38)
                      : lightBottom,
                ],
              ),
        color:
            overriddenSurface ??
            (reducedEffects
                ? scheme.surfaceContainerLow.withValues(alpha: dark ? .94 : .97)
                : null),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .48)),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: reducedEffects
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: dark ? blur : blur.clamp(0, lightBlurLimit),
                sigmaY: dark ? blur : blur.clamp(0, lightBlurLimit),
              ),
              child: content,
            ),
    );
  }
}
