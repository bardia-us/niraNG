import 'package:flutter/foundation.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

/// Readiness owns the asynchronous loader and its verified cache state, not a
/// successful Future alone. The I/O boundary is injectable without a GPU.
class GlassPreparation {
  GlassPreparation({
    required this.supported,
    required this.initialize,
    required this.programsReady,
  });
  final bool Function() supported;
  final Future<void> Function(glass.GlassWarmUpMode mode) initialize;
  final bool Function() programsReady;
  final ready = ValueNotifier<bool>(false);
  Future<void>? _pending;
  // Bound the startup wait, not the loader's lifetime. A completed late load
  // must still activate the optical UI rather than lock the session to matte.
  Future<void> prepare() => _pending ??= _load().timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );
  Future<void> _load() async {
    if (!supported()) return;
    try {
      await initialize(glass.GlassWarmUpMode.always);
      ready.value = programsReady();
    } on Object {
      ready.value = false;
    }
  }
}
