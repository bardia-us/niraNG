import 'package:flutter/rendering.dart';

/// Canvas fragment coordinates are local, unlike ImageFilter input pixels.
/// Canvas is explicitly scaled by 1/dpr before the optical draw, so the
/// shader works in local physical pixels and maps only its sample positions.
class GlassCaptureMapping {
  GlassCaptureMapping(
      {required Matrix4 localToScreen,
      required Offset paintOffset,
      required Offset captureOrigin,
      required double dpr,
      required double captureRatio}) {
    final s = localToScreen.storage;
    final ratio = captureRatio / dpr;
    linear = [s[0] * ratio, s[1] * ratio, s[4] * ratio, s[5] * ratio];
    final global = MatrixUtils.transformPoint(localToScreen, Offset.zero);
    translation =
        (global - captureOrigin) * captureRatio - mapVector(paintOffset * dpr);
  }
  late final List<double> linear;
  late final Offset translation;
  Offset mapVector(Offset p) => Offset(
      linear[0] * p.dx + linear[2] * p.dy, linear[1] * p.dx + linear[3] * p.dy);
  Offset mapPoint(Offset p) => mapVector(p) + translation;
}
