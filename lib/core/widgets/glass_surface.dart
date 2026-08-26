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
    this.blur = 10,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final lightTop = scheme.surface.withValues(alpha: .88);
    final lightBottom = Color.alphaBlend(
      scheme.primaryContainer.withValues(alpha: .065),
      scheme.surface,
    ).withValues(alpha: .84);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: reducedEffects
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dark ? scheme.surface.withValues(alpha: .74) : lightTop,
                  dark
                      ? scheme.primaryContainer.withValues(alpha: .12)
                      : lightBottom,
                ],
              ),
        color: reducedEffects
            ? scheme.surfaceContainerLow.withValues(alpha: dark ? .94 : .97)
            : null,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .52)),
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
                sigmaX: dark ? blur : blur.clamp(0, 14),
                sigmaY: dark ? blur : blur.clamp(0, 14),
              ),
              child: content,
            ),
    );
  }
}
