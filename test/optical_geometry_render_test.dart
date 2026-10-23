// Exercise the real optical-matte cache even on the desktop test backend.
// AdaptiveGlass otherwise takes its shader-free fallback in widget tests.
// ignore_for_file: implementation_imports
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_list_controls.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_blend_group.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_glass_settings.dart';
import 'package:liquid_glass_widgets/src/engine/liquid_shape.dart';
import 'package:liquid_glass_widgets/src/engine/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_widgets/src/engine/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_widgets/src/renderer/liquid_glass_renderer.dart'
    show debugPaintLiquidGlassGeometry;

const _settings = LiquidGlassSettings(thickness: 40, rimShade: .3);

class _MatteOwner extends SingleChildRenderObjectWidget {
  const _MatteOwner(this.link, {required super.child, super.key});
  final GeometryRenderLink link;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMatteOwner(link);
}

class _RenderMatteOwner extends LiquidGlassRenderObject {
  _RenderMatteOwner(GeometryRenderLink link)
    : super(link: link, settings: _settings, devicePixelRatio: 1);
  ui.Image? get matte => geometryImage;
  Offset get matteOrigin => geometryLocalBounds.topLeft;
  @override
  Size get desiredMatteSize => size;
  @override
  Matrix4 get matteTransform => getTransformTo(null);
  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) => throw StateError('Test paints the actual SDF matte');
}

class _Blend extends SingleChildRenderObjectWidget {
  const _Blend(
    this.owner,
    this.shapes,
    this.shader, {
    required super.child,
    super.key,
  });
  final GeometryRenderLink owner;
  final GlassGroupLink shapes;
  final ui.FragmentShader shader;
  @override
  RenderObject createRenderObject(BuildContext context) => _CountingBlend(
    renderLink: owner,
    devicePixelRatio: 1,
    geometryShader: shader,
    settings: _settings,
    link: shapes,
    blend: 0,
  );
}

class _CountingBlend extends RenderLiquidGlassBlendGroup {
  _CountingBlend({
    required super.renderLink,
    required super.devicePixelRatio,
    required super.geometryShader,
    required super.settings,
    required super.link,
    required super.blend,
  });
  int gathers = 0;
  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    gathers++;
    return super.gatherShapeData();
  }
}

class _Shape extends SingleChildRenderObjectWidget {
  _Shape(this.link, {super.key, Widget? content})
    : super(child: SizedBox.square(dimension: 40, child: content));
  final GlassGroupLink link;
  @override
  RenderObject createRenderObject(BuildContext context) => RenderLiquidGlass(
    shape: const LiquidOval(),
    glassContainsChild: false,
    blendGroupLink: link,
  );
}

Future<ui.FragmentProgram> _shader(
  WidgetTester tester,
) async => (await tester.runAsync(
  () => ui.FragmentProgram.fromAsset(
    'packages/liquid_glass_widgets/shaders/liquid_glass_geometry_blended.frag',
  ),
))!;

void main() {
  testWidgets('ordinary capture clears the prior atlas sampling clamp', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff123456), BlendMode.src);
    final picture = recorder.endRecording();
    final atlas = picture.toImageSync(8, 16);
    final ordinary = picture.toImageSync(12, 12);
    picture.dispose();
    final owner = _RenderMatteOwner(GeometryRenderLink());
    owner.bindCapturedBackdropForPaint(
      atlas,
      origin: Offset.zero,
      pixelRatio: 1,
      sampleBounds: const Rect.fromLTWH(0, 8, 8, 8),
    );
    expect(owner.captureSamplingBounds, const Rect.fromLTWH(0, 8, 8, 8));
    owner.captureImage = ordinary;
    expect(
      owner.captureSamplingBounds,
      const Rect.fromLTWH(0, 0, 12, 12),
      reason: 'A non-atlas caller must not inherit the prior recipe clamp',
    );
    owner.bindCapturedBackdropForPaint(
      atlas,
      origin: Offset.zero,
      pixelRatio: 1,
      sampleBounds: const Rect.fromLTWH(0, 8, 8, 8),
    );
    owner.captureImage = atlas;
    expect(
      owner.captureSamplingBounds,
      const Rect.fromLTWH(0, 0, 8, 16),
      reason:
          'The ordinary setter restores full-image sampling even for the same handle',
    );
    owner.dispose();
    atlas.dispose();
    ordinary.dispose();
  });
  setUp(() => debugPaintLiquidGlassGeometry = true);
  tearDown(() => debugPaintLiquidGlassGeometry = false);
  for (final textChange in [false, true]) {
    testWidgets(
      'shared foreground updates across a viewport without motion (text=$textChange)',
      (tester) async {
        final program = await _shader(tester);
        final shader = program.fragmentShader();
        final link = GeometryRenderLink();
        final shapes = GlassGroupLink();
        final value = ValueNotifier(false);
        final sceneKey = GlobalKey();
        final ownerKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: sceneKey,
                child: SizedBox(
                  width: 160,
                  height: 100,
                  child: _MatteOwner(
                    link,
                    key: ownerKey,
                    child: ListView(
                      addRepaintBoundaries: false,
                      children: [
                        SizedBox(
                          height: 100,
                          child: _Blend(
                            link,
                            shapes,
                            shader,
                            child: Center(
                              child: _Shape(
                                shapes,
                                content: ValueListenableBuilder<bool>(
                                  valueListenable: value,
                                  builder: (_, next, _) => textChange
                                      ? Text(
                                          next ? '42 ms' : '99 ms',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: next
                                                ? const Color(0xFF0000FF)
                                                : const Color(0xFFFF0000),
                                          ),
                                        )
                                      : ColoredBox(
                                          color: next
                                              ? const Color(0xFF0000FF)
                                              : const Color(0xFFFF0000),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final owner =
            ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
        final matte = owner.matte;
        Future<List<int>> pixels() async => (await tester.runAsync(() async {
          final boundary =
              sceneKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData())!.buffer
              .asUint8List()
              .toList();
          image.dispose();
          return bytes;
        }))!;
        final before = await pixels();
        value.value = true;
        await tester.pumpAndSettle();
        if (textChange) expect(find.text('42 ms'), findsOneWidget);
        expect(
          await pixels(),
          isNot(orderedEquals(before)),
          reason:
              'The actual displayed frame must update, not only the '
              'widget text; no scroll or pointer event was sent',
        );
        expect(
          identical(owner.matte, matte),
          isTrue,
          reason: 'Foreground changes do not require rebuilding lens geometry',
        );
        value.value = false;
        await tester.pumpAndSettle();
        expect(await pixels(), orderedEquals(before));
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        value.dispose();
        shapes.dispose();
        link.dispose();
        shader.dispose();
      },
    );
  }
  testWidgets(
    'retained Offstage row does not contribute a ghost lens to shared matte',
    (tester) async {
      final program = await _shader(tester);
      final ownerLink = GeometryRenderLink();
      final links = [GlassGroupLink(), GlassGroupLink()];
      final shaders = [program.fragmentShader(), program.fragmentShader()];
      final hidden = ValueNotifier(false);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 80,
              child: _MatteOwner(
                ownerLink,
                key: key,
                child: Stack(
                  children: [
                    for (var i = 0; i < 2; i++)
                      Positioned(
                        left: 20 + i * 60,
                        top: 20,
                        child: ValueListenableBuilder(
                          valueListenable: hidden,
                          builder: (_, value, child) => Offstage(
                            offstage: i == 1 && value,
                            child: child!,
                          ),
                          child: _Blend(
                            ownerLink,
                            links[i],
                            shaders[i],
                            child: _Shape(links[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner = key.currentContext!.findRenderObject() as _RenderMatteOwner;
      expect(owner.matte!.width, 110);
      hidden.value = true;
      owner.markCapturedGeometryMoved();
      await tester.pump();
      expect(
        owner.matte!.width,
        lessThan(60),
        reason: 'Retaining widget state must not retain its hidden SDF',
      );
      hidden.value = false;
      owner.markCapturedGeometryMoved();
      await tester.pump();
      expect(owner.matte!.width, 110);
      await tester.pumpWidget(const SizedBox());
      hidden.dispose();
      ownerLink.dispose();
      for (final link in links) {
        link.dispose();
      }
      for (final shader in shaders) {
        shader.dispose();
      }
    },
  );
  testWidgets(
    'diagonal lens mask follows the ellipse, not its bounding rectangle',
    (tester) async {
      final program = await _shader(tester);
      final shader = program.fragmentShader();
      final ownerLink = GeometryRenderLink();
      final shapes = GlassGroupLink();
      final ownerKey = GlobalKey();
      final direction = ValueNotifier(1.0);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: _MatteOwner(
                ownerLink,
                key: ownerKey,
                child: Center(
                  child: _Blend(
                    ownerLink,
                    shapes,
                    shader,
                    child: AnimatedBuilder(
                      animation: direction,
                      child: _Shape(shapes),
                      builder: (_, child) => Transform(
                        transform: Matrix4.identity()
                          ..setEntry(0, 0, 1.075)
                          ..setEntry(1, 1, 1.075)
                          ..setEntry(0, 1, .175 * direction.value)
                          ..setEntry(1, 0, .175 * direction.value),
                        alignment: Alignment.center,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner =
          ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
      final matte = owner.matte!;
      final bytes = (await tester.runAsync(() => matte.toByteData()))!;
      int alpha(Offset p) {
        final q = p - owner.matteOrigin;
        return bytes.getUint8(
          (q.dy.round() * matte.width + q.dx.round()) * 4 + 3,
        );
      }

      expect(
        alpha(const Offset(65.56, 34.44)),
        lessThan(20),
        reason: '22px across the pull is outside the 18px minor radius',
      );
      expect(
        alpha(const Offset(66.26, 66.26)),
        greaterThan(230),
        reason: '23px along the pull remains inside the 25px major radius',
      );
      direction.value = -1;
      owner.markCapturedGeometryMoved();
      await tester.pump();
      expect(
        owner.matte,
        isNot(same(matte)),
        reason:
            'Opposite diagonal pulls have identical enclosing bounds but different optical masks',
      );
      final flipped = (await tester.runAsync(() => owner.matte!.toByteData()))!;
      final p = const Offset(66.26, 66.26) - owner.matteOrigin;
      expect(
        flipped.getUint8(
          (p.dy.round() * owner.matte!.width + p.dx.round()) * 4 + 3,
        ),
        lessThan(20),
      );
      await tester.pumpWidget(const SizedBox());
      direction.dispose();
      shapes.dispose();
      ownerLink.dispose();
      shader.dispose();
    },
  );
  testWidgets(
    'perspective movement is not treated as a uniform mask translation',
    (tester) async {
      final program = await _shader(tester);
      final shader = program.fragmentShader();
      final ownerLink = GeometryRenderLink();
      final shapes = GlassGroupLink();
      final motion = ValueNotifier(0.0);
      final ownerKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: _MatteOwner(
                ownerLink,
                key: ownerKey,
                child: AnimatedBuilder(
                  animation: motion,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _Blend(
                      ownerLink,
                      shapes,
                      shader,
                      child: _Shape(shapes),
                    ),
                  ),
                  builder: (context, child) => Align(
                    alignment: Alignment.topLeft,
                    child: Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 0, .01)
                        ..setEntry(0, 3, motion.value),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner =
          ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
      final old = owner.matte;
      motion.value = 20;
      owner.markCapturedGeometryMoved();
      await tester.pump();
      expect(
        identical(owner.matte, old),
        isFalse,
        reason:
            'With w=1+.01*x, a matrix translation changes projected size too',
      );
      await tester.pumpWidget(const SizedBox());
      motion.dispose();
      shapes.dispose();
      ownerLink.dispose();
      shader.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('scrolling a fixed lens batch reuses its composed GPU matte', (
    tester,
  ) async {
    final program = await _shader(tester);
    final shaders = List.generate(5, (_) => program.fragmentShader());
    final ownerLink = GeometryRenderLink();
    final links = List.generate(5, (_) => GlassGroupLink());
    final motion = ValueNotifier(0.0);
    final ownerKey = GlobalKey();
    final controls = [
      for (var i = 0; i < 5; i++)
        _Blend(
          ownerLink,
          links[i],
          shaders[i],
          key: ValueKey(i),
          child: _Shape(links[i]),
        ),
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 180,
            height: 360,
            child: _MatteOwner(
              ownerLink,
              key: ownerKey,
              child: AnimatedBuilder(
                animation: motion,
                builder: (context, _) => Stack(
                  children: [
                    for (var i = 0; i < controls.length; i++)
                      Positioned(
                        left: 20,
                        top: 20 + i * 60 - motion.value,
                        child: controls[i],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final owner =
        ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
    final original = owner.matte!;
    final origin = owner.matteOrigin;
    for (final offset in [10.0, 25.0, 7.5, 0.0]) {
      motion.value = offset;
      // The product capture adapter signals this when the scroll moves.
      owner.markCapturedGeometryMoved();
      await tester.pump();
      expect(
        identical(owner.matte, original),
        isTrue,
        reason:
            'Uniform scrolling must move the cached optical mask, not rasterize it again',
      );
      expect(owner.matteOrigin, origin - Offset(0, offset));
      // Include compositor transform notifications: an already-current mask
      // must not be rebuilt by the trailing frame either.
      await tester.pumpAndSettle();
      expect(identical(owner.matte, original), isTrue);
    }
    owner.devicePixelRatio = 2;
    await tester.pump();
    expect(
      identical(owner.matte, original),
      isFalse,
      reason:
          'A different physical pixel density must not reuse the old raster',
    );
    await tester.pumpWidget(const SizedBox());
    motion.dispose();
    for (final link in links) {
      link.dispose();
    }
    ownerLink.dispose();
    for (final shader in shaders) {
      shader.dispose();
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a short viewport scroll reuses the lens batch without re-rasterizing it',
    (tester) async {
      final program = await _shader(tester);
      final ownerLink = GeometryRenderLink();
      final links = List.generate(30, (_) => GlassGroupLink());
      final shaders = List.generate(30, (_) => program.fragmentShader());
      final scroll = ScrollController();
      final ownerKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 180,
              height: 360,
              child: Stack(
                children: [
                  ListView(
                    controller: scroll,
                    itemExtent: 65,
                    children: List.generate(30, (_) => const SizedBox()),
                  ),
                  Positioned.fill(
                    child: OpticalListControls(
                      scroll: scroll,
                      paddingTop: 0,
                      controls: [
                        for (var i = 0; i < 30; i++)
                          _Blend(
                            ownerLink,
                            links[i],
                            shaders[i],
                            key: ValueKey(i),
                            child: _Shape(links[i]),
                          ),
                      ],
                      stageBuilder: (controls) => _MatteOwner(
                        ownerLink,
                        key: ownerKey,
                        child: controls,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner =
          ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
      final original = owner.matte!;
      final origin = owner.matteOrigin;
      scroll.jumpTo(40);
      owner.markCapturedGeometryMoved();
      await tester.pumpAndSettle();
      expect(
        identical(owner.matte, original),
        isTrue,
        reason:
            'A single extra overscan row must not force a new whole-column GPU mask',
      );
      expect(owner.matteOrigin, origin - const Offset(0, 40));
      // Crossing the bounded batch must still materialize the next visible rows.
      scroll.jumpTo(500);
      owner.markCapturedGeometryMoved();
      await tester.pumpAndSettle();
      expect(identical(owner.matte, original), isFalse);
      expect(find.byType(_Blend).evaluate().length, lessThan(20));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      ownerLink.dispose();
      for (final link in links) {
        link.dispose();
      }
      for (final shader in shaders) {
        shader.dispose();
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a shape-only drag updates the optical matte in its first frame', (
    tester,
  ) async {
    final program = await _shader(tester);
    final shaders = [program.fragmentShader(), program.fragmentShader()];
    final ownerLink = GeometryRenderLink();
    final links = [GlassGroupLink(), GlassGroupLink()];
    final motion = ValueNotifier(0.0);
    final ownerKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: _MatteOwner(
              ownerLink,
              key: ownerKey,
              child: Stack(
                children: [
                  Positioned(
                    left: 20,
                    top: 20,
                    child: _Blend(
                      ownerLink,
                      links[0],
                      shaders[0],
                      child: _Shape(links[0]),
                    ),
                  ),
                  Positioned(
                    left: 80,
                    top: 20,
                    child: _Blend(
                      ownerLink,
                      links[1],
                      shaders[1],
                      child: AnimatedBuilder(
                        animation: motion,
                        child: _Shape(links[1]),
                        builder: (context, child) => Transform.translate(
                          offset: Offset(motion.value, 0),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final owner =
        ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
    expect(owner.matte!.width, 110);
    final draggedGroup = tester.renderObject<_CountingBlend>(
      find.byType(_Blend).last,
    );
    draggedGroup.gathers = 0;
    motion.value = 20;
    await tester.pump();
    expect(
      owner.matte!.width,
      130,
      reason:
          'The lens must follow its glyph before a trailing compositor callback',
    );
    expect(
      draggedGroup.gathers,
      1,
      reason:
          'A geometry rebuild must not gather every shape twice in one paint',
    );
    motion.value = 0;
    await tester.pump();
    expect(owner.matte!.width, 110);
    await tester.pumpWidget(const SizedBox());
    motion.dispose();
    for (final link in links) {
      link.dispose();
    }
    ownerLink.dispose();
    for (final shader in shaders) {
      shader.dispose();
    }
    expect(tester.takeException(), isNull);
  });
  for (final removeLastShape in [false, true]) {
    testWidgets(
      'shared matte drops an inactive geometry (empty group=$removeLastShape)',
      (tester) async {
        final program = await _shader(tester);
        final shaders = [program.fragmentShader(), program.fragmentShader()];
        final ownerLink = GeometryRenderLink();
        final shapeLinks = [GlassGroupLink(), GlassGroupLink()];
        final ownerKey = GlobalKey();
        final groupKey = GlobalKey();
        final shapeKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 160,
                height: 80,
                child: _MatteOwner(
                  ownerLink,
                  key: ownerKey,
                  child: Stack(
                    children: [
                      for (var i = 0; i < 2; i++)
                        Positioned(
                          left: 20 + i * 60,
                          top: 20,
                          child: _Blend(
                            ownerLink,
                            shapeLinks[i],
                            shaders[i],
                            key: i == 1 ? groupKey : null,
                            child: _Shape(
                              shapeLinks[i],
                              key: i == 1 ? shapeKey : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final owner =
            ownerKey.currentContext!.findRenderObject() as _RenderMatteOwner;
        final original = owner.matte!;
        expect(original.width, greaterThan(100));
        // Switching grouped/own-layer triggers may leave parent layout unchanged.
        if (removeLastShape) {
          final shape =
              shapeKey.currentContext!.findRenderObject() as RenderLiquidGlass;
          shape.blendGroupLink = null;
        } else {
          final group =
              groupKey.currentContext!.findRenderObject()
                  as RenderLiquidGlassBlendGroup;
          group.renderLink = null;
        }
        owner.markNeedsPaint();
        await tester.pump();
        expect(
          owner.matte,
          isNot(same(original)),
          reason: 'The old cached mask must not retain the removed trigger',
        );
        expect(owner.matte!.width, lessThan(60));
        // The reverse handoff must restore the full mask, not keep the hole
        // left by a now-closed menu's temporarily independent trigger.
        if (removeLastShape) {
          (shapeKey.currentContext!.findRenderObject() as RenderLiquidGlass)
                  .blendGroupLink =
              shapeLinks[1];
        } else {
          (groupKey.currentContext!.findRenderObject()
                      as RenderLiquidGlassBlendGroup)
                  .renderLink =
              ownerLink;
        }
        owner.markNeedsPaint();
        await tester.pump();
        expect(owner.matte!.width, greaterThan(100));
        await tester.pumpWidget(const SizedBox());
        for (final link in shapeLinks) {
          link.dispose();
        }
        ownerLink.dispose();
        for (final shader in shaders) {
          shader.dispose();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
