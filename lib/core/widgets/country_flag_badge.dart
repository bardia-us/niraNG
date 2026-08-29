import 'package:flutter/material.dart';

class CountryFlagBadge extends StatelessWidget {
  const CountryFlagBadge({
    required this.countryCode,
    super.key,
    this.width = 29,
    this.height = 21,
  });

  final String countryCode;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final normalized = countryCode.trim().toUpperCase();
    final valid = RegExp(r'^[A-Z]{2}$').hasMatch(normalized);
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .55),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: valid
          ? Image.asset(
              _twemojiAsset(normalized),
              width: width,
              height: height,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              isAntiAlias: true,
              errorBuilder: (_, _, _) => _fallback(context, height),
            )
          : _fallback(context, height),
    );
  }

  static String _twemojiAsset(String countryCode) {
    final codepoints = countryCode.codeUnits
        .map((unit) => (unit + 127397).toRadixString(16))
        .join('-');
    return 'assets/flags/twemoji/$codepoints.png';
  }

  static Widget _fallback(BuildContext context, double height) => Icon(
    Icons.public_rounded,
    size: height * .7,
    color: Theme.of(context).colorScheme.primary,
  );
}
