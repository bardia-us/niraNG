import 'package:flutter/material.dart';

class NirangScrollBehavior extends MaterialScrollBehavior {
  const NirangScrollBehavior({required this.reducedEffects});

  final bool reducedEffects;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => BouncingScrollPhysics(
    decelerationRate: reducedEffects
        ? ScrollDecelerationRate.fast
        : ScrollDecelerationRate.normal,
    parent: const AlwaysScrollableScrollPhysics(),
  );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (reducedEffects) return child;
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
