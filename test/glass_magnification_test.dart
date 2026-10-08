import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  test('backdrop zoom is opt-in and survives every material transition', () {
    const original = LiquidGlassSettings();
    final zoom = original.copyWith(backdropZoom: 1.035);
    expect(original.effectiveBackdropZoom, 1);
    expect(zoom.effectiveBackdropZoom, 1.035);
    expect(zoom.copyWith(blur: 8).backdropZoom, 1.035);
    expect(zoom.copyWithPinch(.1).backdropZoom, 1.035);
    expect(
      LiquidGlassSettings.lerp(original, zoom, .5).backdropZoom,
      closeTo(1.0175, .00001),
    );
    expect(zoom.copyWith(visibility: 0).effectiveBackdropZoom, 1);
    expect(
      zoom.copyWith(visibility: .5).effectiveBackdropZoom,
      closeTo(1.0175, .00001),
    );
    expect(zoom, isNot(original));
    expect(zoom.copyWith(), zoom);
    expect(zoom.copyWith().hashCode, zoom.hashCode);
  });
}
