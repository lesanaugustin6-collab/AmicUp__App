import 'package:supabase_flutter/supabase_flutter.dart';

/// Retry only a confirmed missing reply column, never an ambiguous network error.
Future<void> insertChatMessage(
  Map<String, dynamic> payload,
  Future<void> Function(Map<String, dynamic>) insert,
) async {
  try {
    await insert(payload);
  } on PostgrestException catch (error) {
    if (!payload.containsKey('reply_to_id') ||
        !{'PGRST204', '42703'}.contains(error.code) ||
        !error.message.contains('reply_to_id')) {
      rethrow;
    }
    // Older databases still support the visible text quote.
    await insert(Map<String, dynamic>.of(payload)..remove('reply_to_id'));
  }
}

void toggleMessageReaction(
  Map<String, String> reactions,
  String id,
  String emoji,
) {
  if (reactions[id] == emoji) {
    reactions.remove(id);
  } else {
    reactions[id] = emoji;
  }
}
