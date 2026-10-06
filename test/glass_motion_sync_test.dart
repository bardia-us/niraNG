import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:liquid_glass_widgets/src/engine/internal/transform_tracking_repaint_boundary_mixin.dart';

class _TrackedProbe extends SingleChildRenderObjectWidget {
  const _TrackedProbe({super.key})
    : super(child: const SizedBox.square(dimension: 40));
  @override
  _RenderTrackedProbe createRenderObject(BuildContext context) =>
      _RenderTrackedProbe();
}

class _RenderTrackedProbe extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  int paints = 0;
  int visits = 0;
  @override
  void visitChildren(RenderObjectVisitor visitor) {
    visits++;
    super.visitChildren(visitor);
  }

  @override
  void onTransformChanged() => markNeedsPaint();
  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    super.paint(context, offset);
  }
}

void main() {
  testWidgets('invisible retained glass skips the motion tree walk', (
    tester,
  ) async {
    final motion = ValueNotifier<int>(0);
    addTearDown(motion.dispose);
    var visible = false;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: glass.GlassMotionSync(
          motion: motion,
          shouldRefresh: () => visible,
          child: RepaintBoundary(child: _TrackedProbe(key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final probe = key.currentContext!.findRenderObject() as _RenderTrackedProbe;
    final before = probe.paints;
    probe.visits = 0;
    motion.value++;
    // Inspect traversal before a frame: layout/paint also visit children.
    expect(probe.visits, 0);
    await tester.pump();
    expect(probe.paints, before);
    visible = true;
    motion.value++;
    expect(probe.visits, greaterThan(0));
    await tester.pump();
    expect(probe.paints, greaterThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden offstage descendants are not walked during motion', (
    tester,
  ) async {
    final motion = ValueNotifier<int>(0);
    addTearDown(motion.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: glass.GlassMotionSync(
          motion: motion,
          child: Offstage(child: _TrackedProbe(key: key)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final probe = key.currentContext!.findRenderObject() as _RenderTrackedProbe;
    probe.visits = 0;
    motion.value++;
    expect(probe.visits, 0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing the visibility predicate keeps the motion listener live',
    (tester) async {
      final motion = ValueNotifier<int>(0);
      addTearDown(motion.dispose);
      final key = GlobalKey();
      Future<void> mount(bool visible) => tester.pumpWidget(
        MaterialApp(
          home: glass.GlassMotionSync(
            motion: motion,
            shouldRefresh: () => visible,
            child: RepaintBoundary(child: _TrackedProbe(key: key)),
          ),
        ),
      );
      await mount(false);
      await tester.pumpAndSettle();
      await mount(true);
      await tester.pumpAndSettle();
      final probe =
          key.currentContext!.findRenderObject() as _RenderTrackedProbe;
      final before = probe.paints;
      motion.value++;
      await tester.pump();
      expect(probe.paints, greaterThan(before));
      await tester.pumpWidget(const SizedBox.shrink());
      motion.value++;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewport motion refreshes shader coordinates in the current paint',
    (tester) async {
      final motion = ValueNotifier<int>(0);
      addTearDown(motion.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: glass.GlassMotionSync(
            motion: motion,
            child: RepaintBoundary(child: _TrackedProbe(key: key)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final probe =
          key.currentContext!.findRenderObject() as _RenderTrackedProbe;
      final before = probe.paints;
      motion.value++;
      await tester.pump();
      expect(probe.paints, greaterThan(before));
      await tester.pumpWidget(const SizedBox.shrink());
      motion.value++;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replacing viewport listener disconnects the old controller', (
    tester,
  ) async {
    final oldMotion = ValueNotifier<int>(0);
    final newMotion = ValueNotifier<int>(0);
    addTearDown(oldMotion.dispose);
    addTearDown(newMotion.dispose);
    final key = GlobalKey();
    Future<void> mount(Listenable motion) => tester.pumpWidget(
      MaterialApp(
        home: glass.GlassMotionSync(
          motion: motion,
          child: RepaintBoundary(child: _TrackedProbe(key: key)),
        ),
      ),
    );
    await mount(oldMotion);
    await tester.pumpAndSettle();
    await mount(newMotion);
    await tester.pumpAndSettle();
    final probe = key.currentContext!.findRenderObject() as _RenderTrackedProbe;
    final before = probe.paints;
    oldMotion.value++;
    await tester.pump();
    expect(probe.paints, before);
    newMotion.value++;
    await tester.pump();
    expect(probe.paints, greaterThan(before));
    expect(tester.takeException(), isNull);
  });
}
