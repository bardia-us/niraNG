import 'package:flutter/material.dart';

/// Painted glass-like depth, deliberately NOT a view of the content behind it.
/// No backdrop filter, optical shader, capture, listener or idle ticker.
class DecorativeGlassSurface extends StatelessWidget {
  const DecorativeGlassSurface({
    required this.child,
    this.radius = 16,
    this.compact = false,
    super.key,
  });

  final Widget child;
  final double radius;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: dark ? .025 : .018),
      theme.colorScheme.surface,
    );
    return CustomPaint(
      foregroundPainter: _PaintedRim(base, radius, dark),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, .34, .76, 1],
            colors: [
              Color.lerp(base, Colors.white, dark ? .09 : .70)!,
              Color.lerp(base, Colors.white, dark ? .025 : .24)!,
              base,
              Color.lerp(base, Colors.black, dark ? .035 : .025)!,
            ],
          ),
          boxShadow: compact
              ? const []
              : [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(
                      alpha: dark ? .025 : .045,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: child,
      ),
    );
  }
}

/// A thin, fixed lighting gradient around all sides, not scene reflection.
class _PaintedRim extends CustomPainter {
  const _PaintedRim(this.base, this.radius, this.dark);
  final Color base;
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(.45);
    if (bounds.isEmpty) return;
    final light = Color.lerp(base, Colors.white, dark ? .28 : .95)!;
    final soft = Color.lerp(base, Colors.white, dark ? .10 : .55)!;
    final shade = Color.lerp(base, Colors.black, dark ? .10 : .09)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9
        ..shader = SweepGradient(
          stops: const [0, .2, .4, .6, .8, 1],
          colors: [soft, light, soft, shade, light, soft],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_PaintedRim oldDelegate) =>
      base != oldDelegate.base ||
      radius != oldDelegate.radius ||
      dark != oldDelegate.dark;
}

/// Home does not need live optics over its plain canvas. Capture this choice
/// explicitly when lifting its dialogs into the Navigator's separate overlay.
class DecorativeGlassScope extends InheritedWidget {
  const DecorativeGlassScope({
    required super.child,
    this.enabled = true,
    super.key,
  });
  final bool enabled;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DecorativeGlassScope>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(DecorativeGlassScope oldWidget) =>
      enabled != oldWidget.enabled;
}
