import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/profile_field_codec.dart';

class SupabaseService {
  static final unmatchChanges = ValueNotifier<int>(0);
  SupabaseService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static StreamSubscription<String>? _fcmTokenRefreshSubscription;

  SupabaseClient get supabase => _client;

  User? get currentUser => _client.auth.currentUser;
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    // Use the password sign-in flow (modern GoTrue API)
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Future<void> updateProfileBasicInfo({
    required String userId,
    required String firstName,
    required String lastName,
    required String username,
    required String bio,
  }) async {
    await _client
        .from('profiles')
        .update({
          'first_name': firstName,
          'last_name': lastName,
          'username': username,
          'bio': bio,
        })
        .eq('id', userId);
  }

  Future<void> updateProfilePrompts({
    required String userId,
    required List<Map<String, String>> prompts,
  }) async {
    await _client
        .from('profiles')
        .update({'prompts': prompts})
        .eq('id', userId);
  }

  Future<void> saveProfile({
    required String id,
    required String firstName,
    required String secondName,
    String? username,
    required DateTime dateOfBirth,
    required String gender,
    required List<String> sports,
    required List<String> hobbies,
    required List<String> music,
    required List<String> lifestyle,
    required List<String> socialVibe,
    String? matchIntent,
    List<String>? availability,
    List<String>? languages,
    String? bio,
    String? avatarUrl,
    String? country,
    List<String>? photos,
    Map<String, dynamic>? icebreakers,
  }) async {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    final finalId = uuidRegex.hasMatch(id)
        ? id
        : _client.auth.currentUser?.id ??
              '00000000-0000-0000-0000-000000000001';

    final normalizedUsername = (username ?? '').trim();
    final resolvedUsername = normalizedUsername.isNotEmpty
        ? normalizedUsername
        : (() {
            final sanitizedName = [firstName, secondName]
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .map(
                  (part) => part
                      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
                      .toLowerCase(),
                )
                .where((part) => part.isNotEmpty)
                .join('_');
            final fallbackName = sanitizedName.isNotEmpty
                ? sanitizedName
                : 'user';
            final suffix = finalId
                .replaceAll('-', '')
                .substring(0, 6)
                .toLowerCase();
            return '${fallbackName}_$suffix';
          })();

    // Keep list values native; Supabase serializes them into request arrays.
    final Map<String, dynamic> payload = {
      'id': finalId,
      'first_name': firstName,
      'last_name': secondName,
      'username': resolvedUsername,
      'birth_date': dateOfBirth.toIso8601String().split('T').first,
      'gender': gender,
      'sports': encodeProfileList(sports),
      'hobbies': encodeProfileList(hobbies),
      'music': encodeProfileList(music),
      'lifestyle': encodeProfileList(lifestyle),
      'social_vibe': encodeProfileList(socialVibe),
    };

    if (matchIntent != null) payload['match_intent'] = matchIntent;
    if (availability != null) {
      payload['availability'] = List<String>.from(availability);
    }
    if (languages != null) payload['languages'] = encodeProfileList(languages);
    if (bio != null) payload['bio'] = bio;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      payload['avatar_url'] = avatarUrl;
    }
    if (country != null && country.trim().isNotEmpty) {
      payload['country'] = country.trim();
    }
    if (photos != null) payload['gallery_photos'] = encodeProfileList(photos);
    if (icebreakers != null) {
      payload['prompts'] = icebreakers;
    }

    await _client.from('profiles').upsert(payload);
  }

  Future<String?> uploadSingleProfileImage(
    XFile file,
    String userId, {
    bool isAvatar = false,
  }) async {
    final bucket = 'profiles';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = isAvatar
        ? 'avatar_$timestamp.jpg'
        : 'photo_$timestamp.jpg';
    final path = isAvatar ? 'avatars/$userId/$fileName' : '$userId/$fileName';

    try {
      await _client.storage.from(bucket).upload(path, File(file.path));
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Upload error for $path: $e');
      return null;
    }
  }

  /// Uploads profile photos to the 'profile_photos' bucket under {userId}/{timestamp}_{index}.jpg
  /// Returns a list of public URLs for the uploaded files.
  Future<List<String>> uploadProfilePhotos(
    List<XFile> files,
    String userId,
  ) async {
    final bucket = 'profiles';
    final uploadedUrls = <String>[];

    for (var i = 0; i < files.length; i++) {
      final xfile = files[i];
      final localFile = File(xfile.path);
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      try {
        await _client.storage.from(bucket).upload(path, localFile);
        final publicUrl = _client.storage.from(bucket).getPublicUrl(path);
        uploadedUrls.add(publicUrl);
      } catch (e) {
        // Continue uploading other files, but log the error
        // ignore: avoid_print
        print('Upload error for $path: $e');
      }
    }

    return uploadedUrls;
  }

  Future<List<Map<String, dynamic>>> fetchMatches({
    required List<double> userVector,
    required String userId,
  }) async {
    final data = await _client.rpc(
      'match_profiles',
      params: {
        'query_vector': userVector,
        'match_threshold': 0.3,
        'match_count': 10,
        'user_id': userId,
      },
    );

    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> fetchUserMatches() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return [];

    final rawMatches = await _client
        .from('matches')
        .select()
        .or('user_1.eq.$currentUserId,user_2.eq.$currentUserId')
        .order('created_at', ascending: false);

    final matchRows = List<Map<String, dynamic>>.from(rawMatches as List);

    final otherUserIds = <String>[];
    final otherUserIdByMatchId = <String, String>{};
    final matchIds = <String>[];

    for (final row in matchRows) {
      final user1 = row['user_1']?.toString() ?? '';
      final user2 = row['user_2']?.toString() ?? '';
      final otherUserId = user1 == currentUserId ? user2 : user1;
      final matchId = row['id']?.toString() ?? '';

      if (otherUserId.isEmpty || matchId.isEmpty) continue;

      otherUserIds.add(otherUserId);
      matchIds.add(matchId);
      otherUserIdByMatchId[matchId] = otherUserId;
    }

    if (otherUserIds.isEmpty || matchIds.isEmpty) return [];

    final rawProfiles = await _client
        .from('profiles')
        .select(
          'id, first_name, last_name, username, avatar_url, gallery_photos',
        )
        .inFilter('id', otherUserIds);

    final profiles = List<Map<String, dynamic>>.from(rawProfiles as List);
    final profileById = <String, Map<String, dynamic>>{};
    for (final profile in profiles) {
      final id = profile['id']?.toString();
      if (id == null || id.isEmpty) continue;
      profileById[id] = profile;
    }

    final rawMessages = await _client
        .from('messages')
        .select('match_id, content, created_at, sender_id, is_read')
        .inFilter('match_id', matchIds)
        .order('created_at', ascending: false);

    final messages = List<Map<String, dynamic>>.from(rawMessages as List);
    final latestMessageByMatchId = <String, Map<String, dynamic>>{};
    for (final message in messages) {
      final matchId = message['match_id']?.toString() ?? '';
      if (matchId.isEmpty) continue;
      latestMessageByMatchId.putIfAbsent(matchId, () => message);
    }

    final results = <Map<String, dynamic>>[];
    for (final matchId in matchIds) {
      final otherUserId = otherUserIdByMatchId[matchId];
      if (otherUserId == null) continue;
      final profile = profileById[otherUserId];
      if (profile == null) continue;

      final latest = latestMessageByMatchId[matchId];
      final senderId = latest?['sender_id']?.toString() ?? '';
      final isRead = latest?['is_read'] == true;
      final unread = latest != null && senderId != currentUserId && !isRead;

      final displayName = [
        profile['first_name']?.toString().trim() ?? '',
        profile['last_name']?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).join(' ');
      final avatarUrl = profile['avatar_url']?.toString();
      final photos = decodeProfileList(profile['gallery_photos']);

      final normalizedPhotos = avatarUrl != null && avatarUrl.isNotEmpty
          ? <String>[avatarUrl, ...photos.where((p) => p != avatarUrl)]
          : photos;

      results.add(<String, dynamic>{
        'match_id': matchId,
        'id': profile['id'],
        'display_name': displayName.isEmpty ? profile['username'] : displayName,
        'first_name': profile['first_name'] ?? displayName,
        'firstName': profile['first_name'] ?? displayName,
        'avatar_url': avatarUrl,
        'photos': normalizedPhotos,
        'last_message': latest?['content']?.toString() ?? '',
        'last_message_at': latest?['created_at'],
        'last_message_sender_id': senderId,
        'unread': unread,
      });
    }

    results.sort((a, b) {
      final aTs = DateTime.tryParse(a['last_message_at']?.toString() ?? '');
      final bTs = DateTime.tryParse(b['last_message_at']?.toString() ?? '');
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });

    return results;
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String matchId) async {
    final rawMessages = await _client
        .from('messages')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(rawMessages as List);
  }

  Future<void> sendMessage(String matchId, String content) async {
    final senderId = _client.auth.currentUser?.id;
    if (senderId == null) {
      throw StateError('No active user session found.');
    }

    await _client.from('messages').insert({
      'match_id': matchId,
      'sender_id': senderId,
      'content': content,
    });
  }

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String currentUserId,
  }) async {
    // ignore: avoid_print
    print(
      '🚨 [READ_RECEIPT] STARTING RPC for conversation: $conversationId | reader:$currentUserId',
    );
    try {
      final result = await _client.rpc(
        'mark_messages_as_read',
        params: {
          'p_conversation_id': conversationId,
          'p_reader_id': currentUserId,
        },
      );
      // ignore: avoid_print
      print('🚨 [READ_RECEIPT] SUCCESS! DB rows updated: $result');
    } catch (e) {
      // ignore: avoid_print
      print('🚨 [READ_RECEIPT] ERROR: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String matchId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at', ascending: false)
        .map((rows) {
          final normalized = rows.map<Map<String, dynamic>>((row) {
            final map = Map<String, dynamic>.from(row);
            final createdAt = map['created_at'];
            if (createdAt is String && createdAt.isNotEmpty) {
              try {
                final parsed = DateTime.parse(createdAt);
                map['created_at'] = parsed.toUtc().toIso8601String();
              } catch (_) {
                // Keep original value if parsing fails.
              }
            }
            return map;
          }).toList();

          normalized.sort((a, b) {
            final aTime =
                DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime.now();
            final bTime =
                DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime.now();
            return aTime.compareTo(bTime);
          });

          return normalized;
        });
  }

  /// Fetch discovery profiles excluding current user's own profile,
  /// already interacted users, and permanently blocked users.
  Future<List<Map<String, dynamic>>> fetchDiscoveryProfiles() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return [];

    // Gather interacted user ids (users that current user already liked/passed)
    List<String> interacted = [];
    try {
      final interactionsData = await _client
          .from('interactions')
          .select('target_user_id')
          .eq('user_id', currentUserId);
      final interactionsList = interactionsData as List;
      for (final item in interactionsList) {
        if (item is Map<String, dynamic> && item['target_user_id'] != null) {
          interacted.add(item['target_user_id'].toString());
        }
      }
    } catch (_) {
      // ignore and continue with empty interacted
    }

    // Gather blocked user ids from blocked_users in both directions.
    // 1) Users I blocked, 2) Users who blocked me.
    final blocked = <String>{};
    try {
      final blockedByMeData = await _client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', currentUserId);
      final blockedByMeList = blockedByMeData as List;
      for (final item in blockedByMeList) {
        if (item is Map<String, dynamic> && item['blocked_id'] != null) {
          blocked.add(item['blocked_id'].toString());
        }
      }

      final blockedMeData = await _client
          .from('blocked_users')
          .select('blocker_id')
          .eq('blocked_id', currentUserId);
      final blockedMeList = blockedMeData as List;
      for (final item in blockedMeList) {
        if (item is Map<String, dynamic> && item['blocker_id'] != null) {
          blocked.add(item['blocker_id'].toString());
        }
      }
    } catch (_) {
      // ignore
    }

    // Fetch candidate profiles (exclude current user)
    List<Map<String, dynamic>> rawProfiles = [];
    try {
      final profilesData = await _client
          .from('profiles')
          .select()
          .neq('id', currentUserId);
      final profilesList = profilesData as List;
      rawProfiles = profilesList.cast<Map<String, dynamic>>();
    } catch (_) {
      // ignore and return empty
      return [];
    }

    final candidateIds = rawProfiles
        .map((profile) => profile['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final hiddenProfileIds = <String>{};
    final verifiedProfileIds = <String>{};

    if (candidateIds.isNotEmpty) {
      try {
        final settingsRows = await _client
            .from('user_settings')
            .select('user_id, incognito_mode, pause_profile')
            .inFilter('user_id', candidateIds);
        for (final row in settingsRows as List) {
          final settings = Map<String, dynamic>.from(row as Map);
          final userId = settings['user_id']?.toString();
          if (userId != null &&
              (settings['incognito_mode'] == true ||
                  settings['pause_profile'] == true)) {
            hiddenProfileIds.add(userId);
          }
        }
      } catch (_) {
        // Profiles without accessible settings remain discoverable.
      }

      try {
        final verifiedRows = await _client
            .from('verified_users')
            .select('user_id, is_verified')
            .inFilter('user_id', candidateIds)
            .eq('is_verified', true);
        for (final row in verifiedRows as List) {
          final userId = (row as Map)['user_id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            verifiedProfileIds.add(userId);
          }
        }
      } catch (_) {
        // A verification lookup failure must not block discovery.
      }
    }

    // Filter out interacted and blocked users locally for simplicity
    final filteredProfiles = rawProfiles.where((p) {
      final pid = p['id']?.toString() ?? '';
      if (pid.isEmpty) return false;
      if (interacted.contains(pid)) return false;
      if (blocked.contains(pid)) return false;
      if (hiddenProfileIds.contains(pid)) return false;
      p['is_verified'] = verifiedProfileIds.contains(pid);
      return true;
    }).toList();

    return filteredProfiles;
  }

  /// Record an interaction (like/pass) from the current user towards a target user.
  Future<void> recordInteraction({
    required String targetUserId,
    required String action,
  }) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final isLike = action == 'like' || action == 'superlike';
    final normalizedAction = isLike ? 'like' : 'pass';

    await _client.from('likes').insert({
      'liker_id': currentUserId,
      'liked_id': targetUserId,
      'is_like': isLike,
      'action': normalizedAction,
    });

    await _client.from('interactions').insert({
      'user_id': currentUserId,
      'target_user_id': targetUserId,
      'action': normalizedAction,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeInteraction({required String targetUserId}) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      return;
    }

    try {
      await _client
          .from('interactions')
          .delete()
          .eq('user_id', currentUserId)
          .eq('target_user_id', targetUserId);

      await _client
          .from('likes')
          .delete()
          .eq('liker_id', currentUserId)
          .eq('liked_id', targetUserId);
    } catch (e) {
      // ignore: avoid_print
      print('Error in removeInteraction for targetUserId=$targetUserId: $e');
    }
  }

  Future<void> unmatchUser({required String targetUserId}) async {
    final supabase = _client;
    try {
      await supabase.rpc(
        'unmatch_and_reset',
        params: {'target_id': targetUserId},
      );
      unmatchChanges.value++;
      debugPrint('Successfully unmatched user $targetUserId and purged rows.');
    } catch (e) {
      debugPrint('Error unmatching user: $e');
      rethrow;
    }
  }

  /// Check if a mutual match exists between current user and [targetUserId].
  Future<bool> checkIfMatch(String targetUserId) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return false;

    // Look for a match record that contains both users (either order)
    final matchesRaw = await _client
        .from('matches')
        .select()
        .or(
          'and(user_1.eq.$currentUserId,user_2.eq.$targetUserId),and(user_1.eq.$targetUserId,user_2.eq.$currentUserId)',
        );
    List matchesList = [];
    try {
      matchesList = matchesRaw as List;
    } catch (_) {
      try {
        final m = matchesRaw as Map;
        matchesList = (m['data'] ?? []) as List;
      } catch (_) {
        matchesList = [];
      }
    }

    return matchesList.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final data = await _client.from('profiles').select().eq('id', userId);
    final list = data as List;
    if (list.isNotEmpty) {
      return Map<String, dynamic>.from(list.first as Map);
    }
    return null;
  }

  Future<bool> hasProfile(String userId) async {
    final profile = await getProfile(userId);
    return profile != null;
  }

  Future<void> updateFcmToken(String token) async {
    final userId = currentUserId;
    if (userId == null || token.isEmpty) {
      return;
    }

    await _client
        .from('profiles')
        .update({'fcm_token': token})
        .eq('id', userId);
  }

  Future<void> saveFcmToken() async {
    final userId = currentUserId;
    if (userId == null) {
      return;
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      // Network/device issue fetching the FCM token; skip syncing for now.
      return;
    }
    if (token != null && token.isNotEmpty) {
      await updateFcmToken(token);
    }

    _fcmTokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen((refreshedToken) {
          unawaited(updateFcmToken(refreshedToken));
        });
  }

  /// Returns true if a profile row exists for [userId]. Returns false on empty or error.
  Future<bool> profileExists(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return response != null;
    } catch (e) {
      return false;
    }
  }
}
