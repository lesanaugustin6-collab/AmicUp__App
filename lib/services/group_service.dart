import 'package:supabase_flutter/supabase_flutter.dart';

class GroupService {
  GroupService(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> friends() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const [];
    final matches = await client
        .from('matches')
        .select('user_1,user_2')
        .or('user_1.eq.$uid,user_2.eq.$uid');
    final ids = <String>{
      for (final match in matches)
        (match['user_1'] == uid ? match['user_2'] : match['user_1']).toString(),
    };
    if (ids.isEmpty) return const [];
    final profiles = await client
        .from('profiles')
        .select('id,first_name,last_name,username,avatar_url')
        .inFilter('id', ids.toList());
    return List<Map<String, dynamic>>.from(profiles as List);
  }

  Future<String> create({
    required String name,
    required String visibility,
    String description = '',
    String category = 'General',
    String? imageUrl,
    String rules = '',
    int messageCooldownSeconds = 0,
    List<String> memberIds = const [],
  }) async {
    final result = await client.rpc(
      'create_amicup_group',
      params: {
        'p_name': name,
        'p_visibility': visibility,
        'p_description': description,
        'p_category': category,
        'p_image_url': imageUrl,
        'p_rules': rules,
        'p_message_cooldown_seconds': messageCooldownSeconds,
        'p_member_ids': memberIds,
      },
    );
    return result.toString();
  }

  Future<void> invite(String channelId, String userId) => client.rpc(
    'invite_to_private_group',
    params: {'p_channel_id': channelId, 'p_user_id': userId},
  );

  Future<void> setRole(String channelId, String userId, String role) => client
      .rpc(
        'set_group_member_role',
        params: {
          'p_channel_id': channelId,
          'p_user_id': userId,
          'p_role': role,
        },
      );

  Future<void> removeMember(String channelId, String userId) => client.rpc(
    'remove_group_member',
    params: {'p_channel_id': channelId, 'p_user_id': userId},
  );

  Future<void> updateGroup({
    required String channelId,
    required String name,
    required String description,
    required String rules,
    required int messageCooldownSeconds,
    String? imageUrl,
  }) => client.rpc(
    'update_amicup_group',
    params: {
      'p_channel_id': channelId,
      'p_name': name,
      'p_description': description,
      'p_rules': rules,
      'p_message_cooldown_seconds': messageCooldownSeconds,
      'p_image_url': imageUrl,
    },
  );

  Future<void> ratePublicChannel({
    required String channelId,
    required int rating,
    String comment = '',
  }) => client.rpc(
    'rate_public_channel',
    params: {
      'p_channel_id': channelId,
      'p_rating': rating,
      'p_comment': comment,
    },
  );
}
