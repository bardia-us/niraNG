import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Mounted rows retain their menu widget. Only viewport lenses enter the GPU
/// stage, matching the Lab's visible range rather than the list's larger cache.
class OpticalPortalRegistry extends ChangeNotifier {
  final _entries = <String, OpticalPortalEntry>{};
  final motion = ChangeNotifier();
  bool _queued = false;
  bool _motionQueued = false;
  bool _disposed = false;
  List<OpticalPortalEntry> get entries =>
      _entries.values.toList(growable: false);

  void _put(String id, OpticalAnchorLink anchor, Widget child) {
    if (_disposed) return;
    final previous = _entries[id];
    if (previous?.anchor == anchor && identical(previous?.child, child)) return;
    _entries[id] = OpticalPortalEntry(id, anchor, child);
    _queue();
  }

  void _remove(String id, OpticalAnchorLink anchor) {
    if (_disposed || _entries[id]?.anchor != anchor) return;
    _entries.remove(id);
    _queue();
  }

  void _queue() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _anchorPainted() {
    // RenderFlow's listener calls markNeedsPaint: never notify during paint.
    if (_disposed || _motionQueued) return;
    _motionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _motionQueued = false;
      if (!_disposed) motion.notifyListeners();
    });
  }

  void notifyAnchorMotion() {
    if (!_disposed) motion.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _entries.clear();
    motion.dispose();
    super.dispose();
  }
}

class OpticalPortalEntry {
  const OpticalPortalEntry(this.id, this.anchor, this.child);
  final String id;
  final OpticalAnchorLink anchor;
  final Widget child;
}

/// Attach/detach owns this reference. A recycled list element may still be
/// mounted but inactive: GlobalKey.currentContext.findRenderObject is illegal
/// then, while a direct, attached render link remains safe to inspect.
class OpticalAnchorLink {
  RenderBox? box;
}

/// Reserves the original row's hit/layout area. Its real control is painted
/// above the unclipped list, before the header's capture/optical stage.
class OpticalPortal extends StatefulWidget {
  const OpticalPortal({
    required this.registry,
    required this.id,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final OpticalPortalRegistry registry;
  final String id;
  final Widget child;
  final bool enabled;
  @override
  State<OpticalPortal> createState() => _OpticalPortalState();
}

class _OpticalPortalState extends State<OpticalPortal> {
  final _anchor = OpticalAnchorLink();
  @override
  void initState() {
    super.initState();
    if (widget.enabled) widget.registry._put(widget.id, _anchor, widget.child);
  }

  @override
  void didUpdateWidget(OpticalPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled &&
        (oldWidget.registry != widget.registry ||
            oldWidget.id != widget.id ||
            !widget.enabled)) {
      oldWidget.registry._remove(oldWidget.id, _anchor);
    }
    if (widget.enabled) widget.registry._put(widget.id, _anchor, widget.child);
  }

  @override
  void dispose() {
    widget.registry._remove(widget.id, _anchor);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.enabled
      ? widget.child
      : _PortalAnchor(
          anchor: _anchor,
          onPaint: widget.registry._anchorPainted,
          child: const SizedBox.square(dimension: 40),
        );
}

class _PortalAnchor extends SingleChildRenderObjectWidget {
  const _PortalAnchor({
    required this.anchor,
    this.onPaint,
    required super.child,
  });
  final OpticalAnchorLink anchor;
  final VoidCallback? onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _AnchorBox(anchor, onPaint);
  @override
  void updateRenderObject(BuildContext context, covariant _AnchorBox box) {
    box.onPaint = onPaint;
  }
}

class _AnchorBox extends RenderProxyBox {
  _AnchorBox(this.anchor, this.onPaint);
  final OpticalAnchorLink anchor;
  VoidCallback? onPaint;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    anchor.box = this;
  }

  @override
  void detach() {
    if (identical(anchor.box, this)) anchor.box = null;
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint?.call();
  }
}

class OpticalPortalFlow extends StatefulWidget {
  const OpticalPortalFlow({
    required this.registry,
    required this.scroll,
    super.key,
  });
  final OpticalPortalRegistry registry;
  final Listenable scroll;
  @override
  State<OpticalPortalFlow> createState() => _OpticalPortalFlowState();
}

class _OpticalPortalFlowState extends State<OpticalPortalFlow> {
  final _flowSpace = OpticalAnchorLink();

  List<OpticalPortalEntry> _visibleEntries() {
    final flow = _flowSpace.box;
    final entries = widget.registry.entries;
    if (flow == null || !flow.attached || !flow.hasSize) return entries;
    // Layout follows build. One control's guard band covers that frame's scroll
    // delta and lets a stretched control cross both viewport rims freely.
    return entries
        .where((entry) {
          final anchor = entry.anchor.box;
          if (anchor == null || !anchor.attached || !anchor.hasSize) {
            return false;
          }
          final rect = MatrixUtils.transformRect(
            anchor.getTransformTo(flow),
            Offset.zero & anchor.size,
          );
          return rect.isFinite &&
              rect.bottom >= -64 &&
              rect.top <= flow.size.height + 64;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.registry,
      widget.scroll,
      widget.registry.motion,
    ]),
    builder: (context, _) {
      final entries = _visibleEntries();
      return _PortalAnchor(
        anchor: _flowSpace,
        child: _LivePortalFlow(
          entries: entries,
          delegate: _PortalFlowDelegate(
            _flowSpace,
            entries,
            Listenable.merge([widget.scroll, widget.registry.motion]),
          ),
          children: [
            for (final entry in entries)
              SizedBox(
                key: ValueKey(entry.id),
                width: 40,
                height: 40,
                child: entry.child,
              ),
          ],
        ),
      );
    },
  );
}

/// Shared optics query transforms before child paint. Standard Flow exposes
/// only its last painted matrix; use the same live anchor as paintChildren.
class _LivePortalFlow extends Flow {
  _LivePortalFlow({
    required this.entries,
    required super.delegate,
    required super.children,
  }) : super(clipBehavior: Clip.none);
  final List<OpticalPortalEntry> entries;

  @override
  RenderFlow createRenderObject(BuildContext context) => _LivePortalRender(
    entries: entries,
    delegate: delegate,
    clipBehavior: clipBehavior,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LivePortalRender renderObject,
  ) {
    renderObject.entries = entries;
    super.updateRenderObject(context, renderObject);
  }
}

class _LivePortalRender extends RenderFlow {
  _LivePortalRender({
    required this.entries,
    required super.delegate,
    required super.clipBehavior,
  });
  List<OpticalPortalEntry> entries;
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final index = getChildrenAsList().indexOf(child);
    final anchor = index >= 0 && index < entries.length
        ? entries[index].anchor.box
        : null;
    if (anchor != null && anchor.attached && anchor.hasSize) {
      transform.multiply(anchor.getTransformTo(this));
    } else {
      super.applyPaintTransform(child, transform);
    }
  }
}

class _PortalFlowDelegate extends FlowDelegate {
  _PortalFlowDelegate(this.flowSpace, this.entries, Listenable motion)
    : super(repaint: motion);
  final OpticalAnchorLink flowSpace;
  final List<OpticalPortalEntry> entries;
  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(width: 40, height: 40);
  @override
  void paintChildren(FlowPaintingContext context) {
    final flow = flowSpace.box;
    if (flow == null || !flow.attached) return;
    for (var i = 0; i < entries.length; i++) {
      final anchor = entries[i].anchor.box;
      if (anchor == null || !anchor.attached || !anchor.hasSize) continue;
      final transform = anchor.getTransformTo(flow);
      final rect = MatrixUtils.transformRect(
        transform,
        Offset.zero & anchor.size,
      );
      if (!rect.isFinite) continue;
      context.paintChild(i, transform: transform);
    }
  }

  @override
  bool shouldRepaint(covariant _PortalFlowDelegate oldDelegate) => true;
}
