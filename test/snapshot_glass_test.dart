import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/snapshot_glass.dart';

void main() {
  test('snapshot crop keeps a fully visible region mapped one-to-one', () {
    final mapping = SnapshotGlassGeometry.mapCrop(
      imageSize: const Size(100, 100),
      snapshotLogicalSize: const Size(200, 200),
      snapshotGlobalOrigin: const Offset(10, 20),
      surfaceGlobalOrigin: const Offset(30, 60),
      surfaceSize: const Size(80, 40),
    );

    expect(mapping, isNotNull);
    expect(mapping!.source, const Rect.fromLTWH(10, 20, 40, 20));
    expect(mapping.destination, const Rect.fromLTWH(0, 0, 80, 40));
  });

  test('snapshot crop does not stretch a clipped edge over the surface', () {
    final mapping = SnapshotGlassGeometry.mapCrop(
      imageSize: const Size(100, 100),
      snapshotLogicalSize: const Size(200, 200),
      snapshotGlobalOrigin: const Offset(10, 10),
      surfaceGlobalOrigin: Offset.zero,
      surfaceSize: const Size(40, 40),
    );

    expect(mapping, isNotNull);
    expect(mapping!.source, const Rect.fromLTWH(0, 0, 15, 15));
    expect(mapping.destination, const Rect.fromLTWH(10, 10, 30, 30));
  });
}
