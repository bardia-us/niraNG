// The app pins this renderer; exercise its real capture-coordinate adapter.
// ignore_for_file: implementation_imports
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/engine/capture_mapping.dart';

void main() {
  test('captured backdrop retains 1:1 logical scale at phone DPR', () {
    const dpr = 2.625;
    final transform = Matrix4.translationValues(21, 147, 0);
    final mapping = GlassCaptureMapping(
      localToScreen: transform,
      paintOffset: const Offset(7, 13),
      captureOrigin: const Offset(0, 24),
      dpr: dpr,
      captureRatio: 1,
    );
    final origin = mapping.mapPoint(const Offset(7, 13) * dpr);
    expect(origin.dx, closeTo(21, .0001));
    expect(origin.dy, closeTo(123, .0001));
    // Ten logical pixels of text must occupy ten capture pixels, not a
    // scaled-to-fit menu/lens image. Rim refraction is separate from mapping.
    final delta = mapping.mapPoint(const Offset(17, 23) * dpr) - origin;
    expect(delta.dx, closeTo(10, .0001));
    expect(delta.dy, closeTo(10, .0001));
  });
}
