import 'package:flutter/material.dart';

/// Displays the quote format already used by stored chat messages.
class ReplyMessageText extends StatelessWidget {
  const ReplyMessageText(this.text, {super.key, this.style, this.onQuoteTap});
  final String text;
  final TextStyle? style;
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final separator = text.indexOf('\n');
    if (!text.startsWith('↩ ') || separator < 0) {
      return Text(text, style: style);
    }
    final color = style?.color ?? Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onQuoteTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .07),
              border: Border(
                left: BorderSide(color: color.withValues(alpha: .4), width: 2),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replied to',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text.substring(2, separator),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: .8),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(text.substring(separator + 1), style: style),
      ],
    );
  }
}
