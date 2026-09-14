import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

abstract final class SnapshotGlassTokens {
  static const pixelRatio = .5;
  static const blurRadius = 5;
  static const blurPasses = 3;
  static const saturation = 1.32;
  static const brightness = 2.0;
  static const darkSurfaceOpacity = .18;
}

@immutable
class SnapshotCropMapping {
  const SnapshotCropMapping({required this.source, required this.destination});

  final Rect source;
  final Rect destination;
}

abstract final class SnapshotGlassGeometry {
  static SnapshotCropMapping? mapCrop({
    required Size imageSize,
    required Size snapshotLogicalSize,
    required Offset snapshotGlobalOrigin,
    required Offset surfaceGlobalOrigin,
    required Size surfaceSize,
  }) {
    if (imageSize.isEmpty ||
        snapshotLogicalSize.isEmpty ||
        surfaceSize.isEmpty) {
      return null;
    }
    final scaleX = imageSize.width / snapshotLogicalSize.width;
    final scaleY = imageSize.height / snapshotLogicalSize.height;
    final relative = surfaceGlobalOrigin - snapshotGlobalOrigin;
    final desiredSource = Rect.fromLTWH(
      relative.dx * scaleX,
      relative.dy * scaleY,
      surfaceSize.width * scaleX,
      surfaceSize.height * scaleY,
    );
    final imageBounds = Offset.zero & imageSize;
    final clippedSource = desiredSource.intersect(imageBounds);
    if (clippedSource.isEmpty) return null;
    final destination = Rect.fromLTWH(
      (clippedSource.left - desiredSource.left) / scaleX,
      (clippedSource.top - desiredSource.top) / scaleY,
      clippedSource.width / scaleX,
      clippedSource.height / scaleY,
    );
    return SnapshotCropMapping(source: clippedSource, destination: destination);
  }
}

class GlassSnapshot {
  GlassSnapshot({
    required this.image,
    required this.logicalSize,
    required this.globalOrigin,
  });

  final ui.Image image;
  final Size logicalSize;
  final Offset globalOrigin;

  void dispose() => image.dispose();
}

abstract final class GlassSnapshotRenderer {
  static Future<GlassSnapshot?> capture({
    required GlobalKey boundaryKey,
    required Color background,
  }) async {
    final boundary = boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
      return null;
    }
    final origin = boundary.localToGlobal(Offset.zero);
    final source = await boundary.toImage(
      pixelRatio: SnapshotGlassTokens.pixelRatio,
    );
    try {
      final image = await _blur(source, background);
      return GlassSnapshot(
        image: image,
        logicalSize: boundary.size,
        globalOrigin: origin,
      );
    } catch (_) {
      source.dispose();
      rethrow;
    }
  }

  static Future<ui.Image> _blur(ui.Image source, Color background) async {
    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('Unable to read glass snapshot pixels.');
    }
    final width = source.width;
    final height = source.height;
    var pixels = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final backgroundRed = (background.r * 255).round();
    final backgroundGreen = (background.g * 255).round();
    final backgroundBlue = (background.b * 255).round();

    // The source surface can be translucent. Flatten it before blurring so
    // sharp live pixels cannot leak through the cached image's alpha channel.
    for (var index = 0; index < pixels.length; index += 4) {
      final alpha = pixels[index + 3];
      if (alpha < 255) {
        final inverseAlpha = 255 - alpha;
        pixels[index] =
            (pixels[index] * alpha + backgroundRed * inverseAlpha) ~/ 255;
        pixels[index + 1] =
            (pixels[index + 1] * alpha + backgroundGreen * inverseAlpha) ~/ 255;
        pixels[index + 2] =
            (pixels[index + 2] * alpha + backgroundBlue * inverseAlpha) ~/ 255;
        pixels[index + 3] = 255;
      }
    }

    for (var pass = 0; pass < SnapshotGlassTokens.blurPasses; pass++) {
      pixels = _boxBlurRgba(
        pixels,
        width,
        height,
        SnapshotGlassTokens.blurRadius,
      );
    }
    for (var index = 0; index < pixels.length; index += 4) {
      final red = pixels[index].toDouble();
      final green = pixels[index + 1].toDouble();
      final blue = pixels[index + 2].toDouble();
      final luminance = red * .2126 + green * .7152 + blue * .0722;
      pixels[index] =
          (luminance +
                  (red - luminance) * SnapshotGlassTokens.saturation +
                  SnapshotGlassTokens.brightness)
              .clamp(0, 255)
              .round();
      pixels[index + 1] =
          (luminance +
                  (green - luminance) * SnapshotGlassTokens.saturation +
                  SnapshotGlassTokens.brightness)
              .clamp(0, 255)
              .round();
      pixels[index + 2] =
          (luminance +
                  (blue - luminance) * SnapshotGlassTokens.saturation +
                  SnapshotGlassTokens.brightness)
              .clamp(0, 255)
              .round();
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final blurred = await completer.future;
    source.dispose();
    return blurred;
  }

  static Uint8List _boxBlurRgba(
    Uint8List source,
    int width,
    int height,
    int radius,
  ) {
    final horizontal = Uint8List(source.length);
    final output = Uint8List(source.length);
    final diameter = radius * 2 + 1;
    for (var y = 0; y < height; y++) {
      var red = 0;
      var green = 0;
      var blue = 0;
      var alpha = 0;
      for (var delta = -radius; delta <= radius; delta++) {
        final sampleX = delta.clamp(0, width - 1);
        final sourceIndex = (y * width + sampleX) * 4;
        red += source[sourceIndex];
        green += source[sourceIndex + 1];
        blue += source[sourceIndex + 2];
        alpha += source[sourceIndex + 3];
      }
      for (var x = 0; x < width; x++) {
        final targetIndex = (y * width + x) * 4;
        horizontal[targetIndex] = red ~/ diameter;
        horizontal[targetIndex + 1] = green ~/ diameter;
        horizontal[targetIndex + 2] = blue ~/ diameter;
        horizontal[targetIndex + 3] = alpha ~/ diameter;
        final removeX = (x - radius).clamp(0, width - 1);
        final addX = (x + radius + 1).clamp(0, width - 1);
        final removeIndex = (y * width + removeX) * 4;
        final addIndex = (y * width + addX) * 4;
        red += source[addIndex] - source[removeIndex];
        green += source[addIndex + 1] - source[removeIndex + 1];
        blue += source[addIndex + 2] - source[removeIndex + 2];
        alpha += source[addIndex + 3] - source[removeIndex + 3];
      }
    }
    for (var x = 0; x < width; x++) {
      var red = 0;
      var green = 0;
      var blue = 0;
      var alpha = 0;
      for (var delta = -radius; delta <= radius; delta++) {
        final sampleY = delta.clamp(0, height - 1);
        final sourceIndex = (sampleY * width + x) * 4;
        red += horizontal[sourceIndex];
        green += horizontal[sourceIndex + 1];
        blue += horizontal[sourceIndex + 2];
        alpha += horizontal[sourceIndex + 3];
      }
      for (var y = 0; y < height; y++) {
        final targetIndex = (y * width + x) * 4;
        output[targetIndex] = red ~/ diameter;
        output[targetIndex + 1] = green ~/ diameter;
        output[targetIndex + 2] = blue ~/ diameter;
        output[targetIndex + 3] = alpha ~/ diameter;
        final removeY = (y - radius).clamp(0, height - 1);
        final addY = (y + radius + 1).clamp(0, height - 1);
        final removeIndex = (removeY * width + x) * 4;
        final addIndex = (addY * width + x) * 4;
        red += horizontal[addIndex] - horizontal[removeIndex];
        green += horizontal[addIndex + 1] - horizontal[removeIndex + 1];
        blue += horizontal[addIndex + 2] - horizontal[removeIndex + 2];
        alpha += horizontal[addIndex + 3] - horizontal[removeIndex + 3];
      }
    }
    return output;
  }
}

class GlassSnapshotBackdrop extends LeafRenderObjectWidget {
  const GlassSnapshotBackdrop({required this.snapshot, super.key});

  final GlassSnapshot snapshot;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      GlassSnapshotRenderBox(snapshot);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant GlassSnapshotRenderBox renderObject,
  ) {
    renderObject.snapshot = snapshot;
  }
}

class SnapshotGlassFallback extends StatelessWidget {
  const SnapshotGlassFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = Color.alphaBlend(
      scheme.primary.withValues(alpha: .055),
      scheme.surface,
    );
    final bottom = Color.alphaBlend(
      Colors.black.withValues(alpha: .08),
      scheme.surface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, scheme.surface, bottom],
        ),
      ),
    );
  }
}

class GlassSnapshotRenderBox extends RenderBox {
  GlassSnapshotRenderBox(this._snapshot);

  GlassSnapshot _snapshot;

  set snapshot(GlassSnapshot value) {
    if (identical(_snapshot, value)) return;
    _snapshot = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final globalOffset = localToGlobal(Offset.zero);
    final mapping = SnapshotGlassGeometry.mapCrop(
      imageSize: Size(
        _snapshot.image.width.toDouble(),
        _snapshot.image.height.toDouble(),
      ),
      snapshotLogicalSize: _snapshot.logicalSize,
      snapshotGlobalOrigin: _snapshot.globalOrigin,
      surfaceGlobalOrigin: globalOffset,
      surfaceSize: size,
    );
    if (mapping == null) return;
    context.canvas.drawImageRect(
      _snapshot.image,
      mapping.source,
      mapping.destination,
      Paint()..filterQuality = FilterQuality.high,
    );
  }
}
