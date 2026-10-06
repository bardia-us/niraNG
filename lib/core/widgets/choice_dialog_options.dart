import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Natural-height choices; only a genuinely overflowing list can scroll.
class ChoiceDialogOptions extends StatelessWidget {
  const ChoiceDialogOptions({
    required this.values,
    required this.current,
    required this.onSelected,
    this.descriptions,
    this.previewColors,
    super.key,
  });

  final Map<String, String> values;
  final String current;
  final ValueChanged<String> onSelected;
  final Map<String, String>? descriptions;
  final Map<String, Color>? previewColors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final titleStyle = theme.textTheme.bodyLarge!;
      final subtitleStyle = theme.textTheme.bodyMedium!;
      final scaler = MediaQuery.textScalerOf(context);
      double textHeight(String text, TextStyle style, double width) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: math.max(1, width));
        final height = painter.height;
        painter.dispose();
        return height;
      }

      var totalHeight = 0.0;
      final rows = <Widget>[];
      for (final entry in values.entries) {
        final preview = previewColors?[entry.key];
        final subtitle = descriptions?[entry.key];
        // Matches the explicit tile padding, leading width and title gaps.
        final width = constraints.maxWidth - 88 - (preview == null ? 0 : 40);
        final height = math.max(
          56.0,
          textHeight(entry.value, titleStyle, width) +
              (subtitle == null
                  ? 0
                  : textHeight(subtitle, subtitleStyle, width)) +
              16,
        );
        totalHeight += height;
        rows.add(
          ListTile(
            minTileHeight: height,
            minVerticalPadding: 8,
            minLeadingWidth: 40,
            horizontalTitleGap: 16,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            titleTextStyle: titleStyle,
            subtitleTextStyle: subtitleStyle,
            leading: Icon(
              entry.key == current
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: entry.key == current
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            title: Text(entry.value),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: preview == null
                ? null
                : SizedBox.square(
                    dimension: 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: preview,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            onTap: () => onSelected(entry.key),
          ),
        );
      }
      final content = Column(mainAxisSize: MainAxisSize.min, children: rows);
      return totalHeight <= constraints.maxHeight
          ? content
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: content,
            );
    },
  );
}
