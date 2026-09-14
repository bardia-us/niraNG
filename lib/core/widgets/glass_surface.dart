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
    this.blur = 12,
    this.lightBlurLimit = 16,
    this.darkBlurLimit = 60,
    this.surfaceOpacity,
    this.liquidDepth = false,
    this.continuousEdge = false,
    this.vibrantDark = false,
    this.showShadow = true,
    this.backdrop,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final double lightBlurLimit;
  final double darkBlurLimit;
  final double? surfaceOpacity;
  final bool liquidDepth;
  final bool continuousEdge;
  final bool vibrantDark;
  final bool showShadow;
  final Widget? backdrop;

  // Matches the light vibrance pass used by Flutter's
  // CupertinoPopupSurface before its backdrop blur.
  static const _lightVibrance = ColorFilter.matrix(<double>[
    1.74,
    -0.40,
    -0.17,
    0,
    0,
    -0.26,
    1.60,
    -0.17,
    0,
    0,
    -0.26,
    -0.40,
    1.83,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  // Flutter's CupertinoPopupSurface dark saturation recipe (iOS 17).
  // It is composed with the blur in one backdrop pass so the original,
  // unblurred pixels are never painted over the glass.
  static const darkVibranceFilter = ColorFilter.matrix(<double>[
    1.39,
    -0.56,
    -0.11,
    0,
    0.30,
    -0.32,
    1.14,
    -0.11,
    0,
    0.30,
    -0.32,
    -0.56,
    1.59,
    0,
    0.30,
    0,
    0,
    0,
    1,
    0,
  ]);

  static ImageFilter backdropFilter({
    required bool dark,
    required double sigma,
    bool vibrantDark = false,
  }) {
    if (dark) {
      final blur = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      return vibrantDark
          ? ImageFilter.compose(inner: darkVibranceFilter, outer: blur)
          : blur;
    }
    final blur = ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.mirror,
    );
    return ImageFilter.compose(inner: _lightVibrance, outer: blur);
  }

  static LinearGradient lightGradient(
    ColorScheme scheme, {
    required double opacity,
  }) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      scheme.surface.withValues(alpha: opacity * .40),
      Colors.white.withValues(alpha: .045),
      scheme.primary.withValues(alpha: .022),
      scheme.surface.withValues(alpha: opacity * .26),
    ],
    stops: const [0, .30, .70, 1],
  );

  static LinearGradient darkGradient(
    ColorScheme scheme, {
    required double opacity,
    bool vibrant = false,
  }) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: vibrant
        ? [
            Colors.white.withValues(alpha: .048),
            scheme.surface.withValues(alpha: opacity * .22),
            scheme.primaryContainer.withValues(alpha: opacity * .15),
            scheme.surface.withValues(alpha: opacity * .16),
          ]
        : [
            Colors.white.withValues(alpha: .032),
            scheme.surface.withValues(alpha: opacity * .38),
            scheme.primaryContainer.withValues(alpha: opacity * .12),
            Colors.black.withValues(alpha: opacity * .34),
          ],
    stops: const [0, .28, .66, 1],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final lightOpacity = surfaceOpacity?.clamp(0.0, 1.0) ?? .22;
    final darkOpacity = surfaceOpacity?.clamp(0.0, 1.0) ?? .20;
    final content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: reducedEffects
            ? null
            : dark
            ? darkGradient(scheme, opacity: darkOpacity, vibrant: vibrantDark)
            : lightGradient(scheme, opacity: lightOpacity),
        color: reducedEffects ? scheme.surfaceContainerLow : null,
        border: reducedEffects
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: .42))
            : null,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
    final liveFilteredContent = BackdropFilter(
      filter: backdropFilter(
        dark: dark,
        vibrantDark: vibrantDark,
        sigma: dark
            ? blur.clamp(0, darkBlurLimit).toDouble()
            : blur.clamp(0, lightBlurLimit).toDouble(),
      ),
      child: content,
    );
    final capturedContent = backdrop == null
        ? content
        : Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(child: backdrop!),
              content,
            ],
          );
    final clippedSurface = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: reducedEffects
          ? content
          : backdrop == null
          ? liveFilteredContent
          : capturedContent,
    );
    if (reducedEffects) return clippedSurface;

    final edgeColor = Color.alphaBlend(
      scheme.primary.withValues(alpha: .08),
      scheme.outlineVariant.withValues(alpha: .38),
    );
    final surfaced = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: !showShadow || (!dark && !liquidDepth)
            ? null
            : dark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .28),
                  blurRadius: 18,
                  spreadRadius: -3,
                  offset: const Offset(2, 7),
                ),
              ]
            : [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: .12),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(2, 5),
                ),
              ],
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          clippedSurface,
          if (dark)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DarkLiquidFramePainter(
                    radius: radius,
                    elevated: liquidDepth,
                    continuousEdge: continuousEdge,
                    edgeColor: Color.alphaBlend(
                      scheme.primary.withValues(alpha: .10),
                      scheme.outlineVariant.withValues(alpha: .46),
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: edgeColor, width: .8),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: radius * .55,
              right: radius * .55,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: .30),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: radius * .55,
              bottom: radius * .55,
              left: 0,
              width: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: .24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return surfaced;
  }
}

class _DarkLiquidFramePainter extends CustomPainter {
  const _DarkLiquidFramePainter({
    required this.radius,
    required this.elevated,
    required this.continuousEdge,
    required this.edgeColor,
  });

  final double radius;
  final bool elevated;
  final bool continuousEdge;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final frameRect = rect.deflate(.65);
    final frame = RRect.fromRectAndRadius(
      frameRect,
      Radius.circular((radius - .65).clamp(0, radius)),
    );
    if (continuousEdge) {
      canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edgeColor,
      );
    }
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = elevated ? 1.15 : .85
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x59FFFFFF),
          Color(0x1FFFFFFF),
          Color(0x12000000),
          Color(0x3D000000),
        ],
        stops: [0, .34, .68, 1],
      ).createShader(frameRect);
    canvas.drawRRect(frame, framePaint);

    if (!elevated) return;
    final innerRect = rect.deflate(1.8);
    final inner = RRect.fromRectAndRadius(
      innerRect,
      Radius.circular((radius - 1.8).clamp(0, radius)),
    );
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .55
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x24FFFFFF), Color(0x08000000), Color(0x26000000)],
        stops: [0, .58, 1],
      ).createShader(innerRect);
    canvas.drawRRect(inner, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _DarkLiquidFramePainter oldDelegate) =>
      radius != oldDelegate.radius ||
      elevated != oldDelegate.elevated ||
      continuousEdge != oldDelegate.continuousEdge ||
      edgeColor != oldDelegate.edgeColor;
}
