import 'package:flutter/material.dart';

class NirangScrollBehavior extends MaterialScrollBehavior {
  const NirangScrollBehavior({required this.reducedEffects});

  final bool reducedEffects;

  @override
  ScrollPhysics getScrollPhysics(
    BuildContext context,
  ) => const BouncingScrollPhysics(
    // Performance Mode saves rendering work, not the user's scroll momentum.
    decelerationRate: ScrollDecelerationRate.normal,
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // BouncingScrollPhysics already provides edge feedback. Stretching the
    // compositor as well deforms circular lenses and their backdrop mapping.
    return child;
  }
}
