import 'package:flutter/material.dart';
import '../formatters.dart';
import 'country_flag_badge.dart';

/// All remaining flags use the same clean bitmap badges as the primary slot.
/// Subscription names/IDs are not changed by this presentation widget.
class ServerNameText extends StatelessWidget {
  const ServerNameText(
    this.name, {
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    super.key,
  });
  final String name;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  @override
  Widget build(BuildContext context) {
    final label = displayServerName(name);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final flag in countryFlagPattern.allMatches(label)) {
      if (flag.start > offset) {
        spans.add(TextSpan(text: label.substring(offset, flag.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: CountryFlagBadge(
              countryCode: countryCodeFromFlag(flag.group(0)!),
              width: 25,
              height: 18,
            ),
          ),
        ),
      );
      offset = flag.end;
    }
    if (offset < label.length) {
      spans.add(TextSpan(text: label.substring(offset)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
