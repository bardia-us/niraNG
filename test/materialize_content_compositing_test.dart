// Exercise the materialize content path, including real Gaussian pixels.
// ignore_for_file: implementation_imports
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/src/renderer/glass_materialize_scope.dart';

void main() {
  testWidgets('visibility and content fade use one opacity around the filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassMaterializeScope(
          glassProgress: .4,
          contentOpacity: .5,
          contentSigma: 2,
          child: Builder(
            builder: (context) => GlassMaterializeScope.wrapContent(
              context,
              const SizedBox(width: 60, height: 40),
              visibility: .4,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .2);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('visibility still fades content outside a materialize scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => GlassMaterializeScope.wrapContent(
            context,
            const SizedBox(width: 60, height: 40),
            visibility: .4,
          ),
        ),
      ),
    );
    expect(find.byType(Opacity), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .4);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('merged fade preserves premultiplied Gaussian output', (
    tester,
  ) async {
    final key = GlobalKey();
    const content = Center(
      child: SizedBox(
        width: 32,
        height: 24,
        child: ColoredBox(color: Color(0xAA8030FF)),
      ),
    );
    Future<List<int>> pixels(bool merged) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 60,
                height: 50,
                child: GlassMaterializeScope(
                  glassProgress: .4,
                  contentOpacity: .5,
                  contentSigma: 2,
                  child: Builder(
                    builder: (context) => merged
                        ? GlassMaterializeScope.wrapContent(
                            context,
                            content,
                            visibility: .4,
                          )
                        : Opacity(
                            opacity: .5,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: 2,
                                sigmaY: 2,
                              ),
                              child: const Opacity(opacity: .4, child: content),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        final copy = bytes.toList();
        image.dispose();
        return copy;
      }))!;
    }

    final before = await pixels(false);
    final after = await pixels(true);
    var worst = 0;
    for (var i = 0; i < before.length; i++) {
      final difference = (before[i] - after[i]).abs();
      if (difference > worst) worst = difference;
    }
    expect(worst, lessThanOrEqualTo(2));
    expect(after[(25 * 60 + 30) * 4 + 3], inInclusiveRange(32, 35));
  });
}
