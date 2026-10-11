import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/clay_surface.dart';

void main() {
  testWidgets('clay press reverses surface lighting and releases its depth', (
    tester,
  ) async {
    Widget surface(bool pressed) => MaterialApp(
      theme: ThemeData.dark(),
      home: ClayPress(
        pressed: pressed,
        child: const Center(child: ClayNavigationIcon(Icons.home)),
      ),
    );
    BoxDecoration decoration() =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(ClaySurface),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    await tester.pumpWidget(surface(false));
    final raised = decoration();
    final raisedColors = (raised.gradient! as LinearGradient).colors;
    expect(
      raisedColors.first.computeLuminance(),
      greaterThan(raisedColors.last.computeLuminance()),
    );
    await tester.pumpWidget(surface(true));
    final pressed = decoration();
    final pressedColors = (pressed.gradient! as LinearGradient).colors;
    expect(
      pressedColors.first.computeLuminance(),
      lessThan(pressedColors.last.computeLuminance()),
    );
    expect(
      pressed.boxShadow!.first.offset.distance,
      lessThan(raised.boxShadow!.first.offset.distance),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(surface(false));
    expect(decoration(), raised);
  });
}
