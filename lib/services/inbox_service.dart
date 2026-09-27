import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InboxService {
  InboxService(this.client);
  final SupabaseClient client;
  static final changes = ValueNotifier<int>(0);

  Future<List<Map<String, dynamic>>> conversations() async {
    final rows = await client.rpc('get_direct_inbox');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> activity({int offset = 0}) async {
    final rows = await client.rpc(
      'get_profile_activity',
      params: {'page_offset': offset, 'page_size': 40},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, int>> memberCounts(List<String> channelIds) async {
    if (channelIds.isEmpty) return {};
    final rows = await client.rpc(
      'get_channel_member_counts',
      params: {'channel_ids': channelIds},
    );
    return {
      for (final row in rows as List)
        row['channel_id'].toString(): (row['member_count'] as num).toInt(),
    };
  }

  Future<void> markRead(String matchId, List<String> ids) async {
    if (ids.isEmpty) return;
    await client.rpc(
      'mark_direct_messages_read',
      params: {'conversation_id': matchId, 'message_ids': ids},
    );
    changes.value++;
  }

  RealtimeChannel? watch(VoidCallback onChange) {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return null;
    final channel = client.channel(
      'inbox-$uid-${DateTime.now().microsecondsSinceEpoch}',
    );
    // RLS limits message events to conversations the current account can read.
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      callback: (_) => onChange(),
    );
    for (final column in ['user_1', 'user_2']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'matches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: uid,
        ),
        callback: (_) => onChange(),
      );
    }
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'likes',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'liked_id',
        value: uid,
      ),
      callback: (_) => onChange(),
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'channel_members',
      callback: (_) => onChange(),
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'channel_messages',
      callback: (_) => onChange(),
    );
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) onChange();
    });
    return channel;
  }
}
