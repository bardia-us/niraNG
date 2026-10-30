import 'package:flutter/material.dart';

/// The unmodified modern official mark, clipped to match the app's rounded icons.
class PsiphonBrandIcon extends StatelessWidget {
  const PsiphonBrandIcon({this.size = 23, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .24),
    child: Image.asset(
      'assets/branding/psiphon-official.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      semanticLabel: 'Psiphon',
    ),
  );
}
