import 'package:flutter/material.dart';

import 'direct_chat_view.dart';

/// Compatibility wrapper for the retired duplicate direct-chat screen.
///
/// All one-to-one conversations now use [DirectChatView], including callers
/// that still provide a match map through this older API.
@Deprecated('Use DirectChatView instead.')
class ChatView extends StatelessWidget {
  const ChatView({super.key, required this.matchId, required this.otherUser});

  final String matchId;
  final Map<String, dynamic> otherUser;

  @override
  Widget build(BuildContext context) {
    final otherUserId = (otherUser['partner_id'] ?? otherUser['id'] ?? '')
        .toString();
    final name = [
      otherUser['first_name']?.toString().trim() ?? '',
      otherUser['last_name']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    final fallbackName = otherUser['display_name']?.toString().trim();

    if (otherUserId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('This conversation is unavailable.')),
      );
    }

    return DirectChatView(
      matchId: matchId,
      otherUserId: otherUserId,
      otherUserName: name.isNotEmpty
          ? name
          : (fallbackName?.isNotEmpty == true ? fallbackName! : 'Buddy'),
    );
  }
}
