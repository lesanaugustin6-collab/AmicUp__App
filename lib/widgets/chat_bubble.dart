import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    this.text,
    this.message,
    this.isCurrentUser = false,
    this.isRead = false,
    this.showSeenIndicator = false,
    this.isLatestSentMessage = false,
    this.showSeenStatus = false,
  });

  final String? text;
  final Map<String, dynamic>? message;
  final bool isCurrentUser;
  final bool isRead;
  final bool showSeenIndicator;
  final bool isLatestSentMessage;
  final bool showSeenStatus;

  String get _resolvedText => text ?? message?['content']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isCurrentUser
        ? Theme.of(context).colorScheme.primary
        : AppTheme.of(context).incomingBubble;
    final textColor = isCurrentUser
        ? AppTheme.of(context).onAccent
        : AppTheme.of(context).ink;
    final bool footerIsRead = isRead || message?['is_read'] == true;

    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isCurrentUser ? 16 : 6),
                bottomRight: Radius.circular(isCurrentUser ? 6 : 16),
              ),
            ),
            child: Text(
              _resolvedText,
              style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
            ),
          ),
          if (isCurrentUser)
            Padding(
              padding: const EdgeInsets.only(top: 2.0, right: 6.0, bottom: 4.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  footerIsRead ? 'Seen' : 'Sent',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: footerIsRead
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: footerIsRead
                        ? AppTheme.of(context).ink
                        : AppTheme.of(context).muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
