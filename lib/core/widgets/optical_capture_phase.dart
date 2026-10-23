/// Synchronous scene-recording phase, not visibility or application state.
/// A decorative foreground can remain on screen without refracting itself in
/// a later glass surface's input. Always restored before the real scene builds.
abstract final class OpticalCapturePhase {
  static int _depth = 0;
  static bool get isActive => _depth > 0;

  static T record<T>(T Function() capture) {
    _depth++;
    try {
      return capture();
    } finally {
      _depth--;
    }
  }
}
