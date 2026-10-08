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
  Offset? lastPaintOrigin;
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
    lastPaintOrigin = localToGlobal(Offset.zero);
    super.paint(context, offset);
  }
}

void main() {
  testWidgets(
    'cached scrolling lens paints at its new position in the same frame',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: glass.GlassMotionSync(
              motion: scroll,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 100),
                    RepaintBoundary(child: _TrackedProbe(key: key)),
                    const SizedBox(height: 1200),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final probe =
          key.currentContext!.findRenderObject() as _RenderTrackedProbe;
      for (final offset in [17.0, 38.5, 6.0, 52.0]) {
        final before = probe.lastPaintOrigin!;
        scroll.jumpTo(offset);
        await tester.pump();
        expect(
          probe.lastPaintOrigin,
          probe.localToGlobal(Offset.zero),
          reason: 'The optical paint must not trail the viewport by one frame',
        );
        expect(probe.lastPaintOrigin, isNot(before));
        final currentPaints = probe.paints;
        await tester.pump();
        expect(
          probe.paints,
          currentPaints,
          reason:
              'A lens painted at the current transform must not request a redundant trailing repaint',
        );
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a cached lens without a motion notifier still refreshes after translation',
    (tester) async {
      final motion = ValueNotifier<double>(0);
      addTearDown(motion.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: AnimatedBuilder(
              animation: motion,
              child: RepaintBoundary(child: _TrackedProbe(key: key)),
              builder: (_, child) => Transform.translate(
                offset: Offset(0, motion.value),
                child: child,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final probe =
          key.currentContext!.findRenderObject() as _RenderTrackedProbe;
      final before = probe.paints;
      motion.value = 19.5;
      await tester.pump();
      await tester.pump();
      expect(probe.paints, greaterThan(before));
      expect(probe.lastPaintOrigin, probe.localToGlobal(Offset.zero));
      await tester.pumpWidget(const SizedBox());
    },
  );
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
