import 'package:flutter/material.dart';

/// A deliberately small Markdown renderer for trusted GitHub release notes.
///
/// Release bodies only need headings, bullets, bold text and inline code. By
/// rendering that subset locally we avoid showing raw Markdown while keeping
/// the update path independent from a network-fetched runtime dependency.
class ReleaseNotesMarkdown extends StatelessWidget {
  const ReleaseNotesMarkdown({required this.data, super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('### ')) {
        children.add(
          _block(
            context,
            line.substring(4),
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            top: 8,
          ),
        );
      } else if (line.startsWith('## ')) {
        children.add(
          _block(
            context,
            line.substring(3),
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            top: 10,
          ),
        );
      } else if (line.startsWith('# ')) {
        children.add(
          _block(
            context,
            line.substring(2),
            theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            top: 10,
          ),
        );
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8),
                  child: Text('•'),
                ),
                Expanded(child: Text.rich(_inline(context, line.substring(2)))),
              ],
            ),
          ),
        );
      } else {
        children.add(_block(context, line, theme.textTheme.bodyMedium));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _block(
    BuildContext context,
    String text,
    TextStyle? style, {
    double top = 2,
  }) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 2),
    child: Text.rich(_inline(context, text, baseStyle: style)),
  );

  TextSpan _inline(BuildContext context, String text, {TextStyle? baseStyle}) {
    final base = baseStyle ?? Theme.of(context).textTheme.bodyMedium;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`)');
    var offset = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: base?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      }
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: base, children: spans);
  }
}
