import 'package:flutter/material.dart';

/// Local press state; only the small clay control needs to repaint.
class ClayPress extends InheritedWidget {
  const ClayPress({required this.pressed, required super.child, super.key});
  final bool pressed;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClayPress>()?.pressed ?? false;

  @override
  bool updateShouldNotify(ClayPress oldWidget) => pressed != oldWidget.pressed;
}

/// Small, painted visual trial. Never captures or refracts its backdrop.
class ClaySurface extends StatelessWidget {
  const ClaySurface({
    required this.child,
    this.radius = 20,
    this.color,
    this.showBorder = true,
    super.key,
  });
  final Widget child;
  final double radius;
  final Color? color;
  final bool showBorder;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = color ?? theme.colorScheme.surfaceContainerHigh;
    final pressed = ClayPress.of(context);
    // Convex/concave lighting and opposing, base-tinted shadows follow the
    // material model used by clay_containers and Flutter-Neumorphic. No
    // backdrop capture or extra liquid layer is needed for this small surface.
    final light = Color.lerp(base, Colors.white, dark ? .09 : .24)!;
    final shade = Color.lerp(base, Colors.black, dark ? .12 : .06)!;
    final depth = pressed ? .65 : 2.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pressed ? [shade, light] : [light, shade],
        ),
        border: showBorder
            ? Border.all(
                color: theme.colorScheme.onSurface.withValues(
                  alpha: dark ? .08 : .05,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Color.lerp(
              base,
              Colors.black,
              .35,
            )!.withValues(alpha: dark ? .32 : .18),
            blurRadius: pressed ? 2 : 4,
            offset: Offset(depth, depth),
          ),
          BoxShadow(
            color: Color.lerp(
              base,
              Colors.white,
              .35,
            )!.withValues(alpha: dark ? .10 : .45),
            blurRadius: pressed ? 2 : 4,
            offset: Offset(-depth, -depth),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ClayNavigationIcon extends StatelessWidget {
  const ClayNavigationIcon(this.icon, {this.selected = false, super.key});
  final IconData icon;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClaySurface(
      radius: 12,
      showBorder: false,
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: SizedBox(
        width: 46,
        height: 38,
        child: Icon(
          icon,
          size: 28,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
