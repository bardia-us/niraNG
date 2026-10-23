import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Measured dense ListTile: 58px + 2px card border + 5px row gap.
// The source list and lens stage deliberately share this layout contract.
const serverRowExtent = 65.0;

/// Lab's fixed-extent scene: positions exist during layout, before shared glass
/// geometry paints. Never derive optical geometry from Flow's previous paint.
class OpticalListControls extends StatelessWidget {
  const OpticalListControls({
    required this.scroll,
    required this.paddingTop,
    required this.controls,
    required this.stageBuilder,
    this.retainedControlKey,
    super.key,
  });

  final ScrollController scroll;
  final double paddingTop;
  final List<Widget> controls;
  final Widget Function(Widget controls) stageBuilder;

  /// A proxy can cross the viewport while its original slot scrolls away.
  /// Keep its one existing lens mounted until the drop animation completes.
  final Key? retainedControlKey;

  @override
  Widget build(BuildContext context) {
    final retained = retainedControlKey == null
        ? -1
        : controls.indexWhere((control) => control.key == retainedControlKey);
    return LayoutBuilder(
      builder: (context, constraints) {
        (int, int, double)? cachedLayout;
        Widget? cachedStage;
        return AnimatedBuilder(
          animation: scroll,
          builder: (context, _) {
            final offset = scroll.hasClients ? scroll.offset : 0.0;
            // Keep free stretch through header/dock edges. Retain bounded batches
            // of four slots: entering one overscan row must not rebuild the whole
            // shared GPU matte every 65px. Visible positions/pixels do not change.
            const batch = 4;
            final requiredFirst = math.max(
              0,
              ((offset - paddingTop - 64) / serverRowExtent).floor(),
            );
            final requiredEnd =
                ((offset + constraints.maxHeight - paddingTop + 64) /
                        serverRowExtent)
                    .ceil();
            final first = requiredFirst ~/ batch * batch;
            final end = math.min(
              controls.length,
              ((requiredEnd + batch - 1) ~/ batch) * batch,
            );
            // Keep Stack layout stable within a batch. The fractional scroll
            // delta is a paint transform, not new parent-data/layout for every
            // visible trigger on every pointer tick. The two offsets cancel
            // exactly: no rounding/snapping is applied to the visible position.
            final batchExtent = batch * serverRowExtent;
            final layoutOffset = (offset / batchExtent).floor() * batchExtent;
            final layout = (first, end, layoutOffset);
            if (layout == cachedLayout) return cachedStage!;
            Widget positioned(int index) => PositionedDirectional(
              key: controls[index].key,
              top: paddingTop + index * serverRowExtent - layoutOffset + 8,
              end: 21,
              child: _ScrollControlTranslation(
                scroll: scroll,
                layoutOffset: layoutOffset,
                child: controls[index],
              ),
            );
            cachedLayout = layout;
            return cachedStage = stageBuilder(
              Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: [
                  if (retained >= 0 && retained < first) positioned(retained),
                  for (var i = first; i < end; i++) positioned(i),
                  if (retained >= end && retained >= 0) positioned(retained),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Follow the list's current fractional offset in the render tree. Static
/// Positioned/menu widgets only change when the visible batch changes, not
/// once per pointer tick. Flutter's RenderTransform retains hit-test semantics.
class _ScrollControlTranslation extends SingleChildRenderObjectWidget {
  const _ScrollControlTranslation({
    required this.scroll,
    required this.layoutOffset,
    required super.child,
  });
  final ScrollController scroll;
  final double layoutOffset;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ScrollControlTransform(scroll, layoutOffset);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ScrollControlTransform renderObject,
  ) => renderObject.update(scroll, layoutOffset);
}

class _ScrollControlTransform extends RenderTransform {
  _ScrollControlTransform(this._scroll, this._layoutOffset)
    : super(transform: Matrix4.identity()) {
    _moved();
  }
  ScrollController _scroll;
  double _layoutOffset;
  void _moved() {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    transform = Matrix4.translationValues(0, _layoutOffset - offset, 0);
  }

  void update(ScrollController scroll, double layoutOffset) {
    if (!identical(scroll, _scroll)) {
      if (attached) _scroll.removeListener(_moved);
      _scroll = scroll;
      if (attached) _scroll.addListener(_moved);
    }
    _layoutOffset = layoutOffset;
    _moved();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scroll.addListener(_moved);
    _moved();
  }

  @override
  void detach() {
    _scroll.removeListener(_moved);
    super.detach();
  }
}
