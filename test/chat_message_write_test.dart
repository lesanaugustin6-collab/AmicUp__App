import 'package:amicup_app/services/chat_message_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Missing reply column retries once, preserving visible quote', () async {
    final calls = <Map<String, dynamic>>[];
    final payload = {'content': '↩ Original\nReply', 'reply_to_id': 'original'};
    await insertChatMessage(payload, (data) async {
      calls.add(data);
      if (calls.length == 1) {
        throw const PostgrestException(
          message: "Could not find 'reply_to_id' column",
          code: 'PGRST204',
        );
      }
    });
    expect(calls.length, 2);
    expect(calls.last, {'content': '↩ Original\nReply'});
    expect(payload['reply_to_id'], 'original');
  });
  test('Other failures never retry and risk duplicate messages', () async {
    for (final error in [
      const PostgrestException(message: 'Permission denied', code: '42501'),
      const PostgrestException(
        message: "Missing 'image_urls' column",
        code: 'PGRST204',
      ),
      Exception('Network timeout'),
    ]) {
      var calls = 0;
      await expectLater(
        insertChatMessage({'reply_to_id': 'id'}, (data) async {
          calls++;
          throw error;
        }),
        throwsA(same(error)),
      );
      expect(calls, 1);
    }
  });
  test('A repeated heart removes it; a different emoji replaces it', () {
    final reactions = <String, String>{};
    toggleMessageReaction(reactions, 'message', '❤️');
    expect(reactions['message'], '❤️');
    toggleMessageReaction(reactions, 'message', '❤️');
    expect(reactions.containsKey('message'), isFalse);
    toggleMessageReaction(reactions, 'message', '😂');
    toggleMessageReaction(reactions, 'message', '❤️');
    expect(reactions['message'], '❤️');
  });
}
