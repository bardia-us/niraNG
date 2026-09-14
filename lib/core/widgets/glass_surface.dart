import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';

enum GlassSurfaceRole { generic, chrome, popover, dialog, sheet }

@immutable
class GlassRecipe {
  const GlassRecipe({
    required this.blur,
    required this.opacity,
    required this.borderOpacity,
  });

  final double blur;
  final double opacity;
  final double borderOpacity;

  static GlassRecipe resolve(GlassSurfaceRole role, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (role) {
      GlassSurfaceRole.chrome => GlassRecipe(
        blur: dark ? 13 : 12,
        opacity: dark ? .42 : .16,
        borderOpacity: dark ? .17 : .11,
      ),
      GlassSurfaceRole.popover => GlassRecipe(
        blur: dark ? 13 : 12,
        opacity: dark ? .42 : .18,
        borderOpacity: dark ? .17 : .12,
      ),
      GlassSurfaceRole.dialog => GlassRecipe(
        blur: dark ? 13 : 14,
        opacity: dark ? .42 : .24,
        borderOpacity: dark ? .17 : .13,
      ),
      GlassSurfaceRole.sheet => GlassRecipe(
        blur: dark ? 13 : 12,
        opacity: dark ? .42 : .20,
        borderOpacity: dark ? .17 : .13,
      ),
      GlassSurfaceRole.generic => GlassRecipe(
        blur: dark ? 14 : 12,
        opacity: dark ? .42 : .22,
        borderOpacity: dark ? .15 : .10,
      ),
    };
  }
}

class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.role = GlassSurfaceRole.generic,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final GlassSurfaceRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final recipe = GlassRecipe.resolve(role, theme.brightness);
    final borderRadius = BorderRadius.circular(radius);
    final body = Padding(padding: padding ?? EdgeInsets.zero, child: child);

    if (reducedEffects) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .42),
            ),
            borderRadius: borderRadius,
          ),
          child: body,
        ),
      );
    }

    final tint = (dark ? const Color(0xFF1C1C20) : const Color(0xFFF8F8FA))
        .withValues(alpha: recipe.opacity);
    final border = (dark ? Colors.white : Colors.black).withValues(
      alpha: recipe.borderOpacity,
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: recipe.blur, sigmaY: recipe.blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            border: Border.all(color: border, width: .8),
            borderRadius: borderRadius,
          ),
          child: body,
        ),
      ),
    );
  }
}
