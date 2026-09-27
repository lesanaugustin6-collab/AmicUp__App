import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

// Stored in the existing content column so forwarding needs no schema upgrade.
const forwardedPrefix = 'Forwarded\n';

Map<String, dynamic> displayMessage(Map<String, dynamic> message) {
  final content = message['content']?.toString() ?? '';
  final forwarded = content.startsWith(forwardedPrefix);
  final body = forwarded ? content.substring(forwardedPrefix.length) : content;
  if (body.startsWith('[EVENT]:')) {
    final fields = body.substring(8).split('|');
    final title = fields.length > 1 ? fields[1] : 'Event';
    final location = fields.length > 3 ? fields[3] : '';
    return {
      ...message,
      '_raw_content': content,
      'content': '🎟 Event: $title${location.isEmpty ? '' : '\n$location'}',
      'event_id': fields.isEmpty ? null : fields.first,
      'is_event': true,
      'is_forwarded': forwarded,
    };
  }
  return {
    ...message,
    if (content.startsWith(forwardedPrefix)) ...{
      'content': content.substring(forwardedPrefix.length),
      'is_forwarded': true,
    },
  };
}

String forwardText(Map<String, dynamic> message) {
  final displayed = displayMessage(message);
  var text = message['_raw_content']?.toString() ??
      displayed['_raw_content']?.toString() ??
      displayed['content']?.toString() ??
      '';
  if (text.startsWith('↩ ') && text.contains('\n')) {
    text = text.substring(text.indexOf('\n') + 1);
  }
  return text.startsWith('[IMAGE]:') || text.startsWith('[ALBUM]:') ? '' : text;
}

List<String> forwardPhotos(Map<String, dynamic> message) {
  dynamic raw = message['image_urls'];
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      raw = null;
    }
  }
  if (raw is List) {
    final urls = raw
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (urls.isNotEmpty) return urls;
  }
  final single = message['image_url']?.toString().trim() ?? '';
  if (single.isNotEmpty) return [single];
  final content = displayMessage(message)['content']?.toString() ?? '';
  if (content.startsWith('[IMAGE]:')) return [content.substring(8).trim()];
  if (content.startsWith('[ALBUM]:')) {
    return content
        .substring(8)
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return [];
}

class ForwardDestination {
  const ForwardDestination({
    required this.id,
    required this.name,
    required this.group,
  });
  final String id;
  final String name;
  final bool group;
}

Map<String, dynamic> forwardPayload(
  Map<String, dynamic> message,
  ForwardDestination target,
  String sender,
) {
  final photos = forwardPhotos(message);
  final text = forwardText(message);
  // Legacy album content works with both chat tables, including group schemas
  // that have only image_url. Do not copy read receipts or reply links.
  return {
    target.group ? 'channel_id' : 'match_id': target.id,
    'sender_id': sender,
    'content': photos.length > 1 && text.isEmpty
        ? '[ALBUM]: ${photos.join(',')}'
        : text.isNotEmpty
        ? text
        : photos.isNotEmpty
        ? '[IMAGE]: ${photos.first}'
        : '',
    if (photos.length == 1) 'image_url': photos.first,
    if (!target.group && photos.length > 1) 'image_urls': photos,
  };
}

List<Map<String, dynamic>> forwardPayloads(
  Map<String, dynamic> message,
  ForwardDestination target,
  String sender,
) {
  final photos = forwardPhotos(message);
  if (target.group && photos.length > 1) {
    return [
      for (var i = 0; i < photos.length; i++)
        {
          'channel_id': target.id,
          'sender_id': sender,
          'image_url': photos[i],
          'content': i == 0 && forwardText(message).isNotEmpty
              ? forwardText(message)
              : '[IMAGE]: ${photos[i]}',
        },
    ];
  }
  return [forwardPayload(message, target, sender)];
}

class MessageForwarding {
  MessageForwarding(this.client);
  final SupabaseClient client;
  Future<List<ForwardDestination>> destinations({
    String? excludedSenderId,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Please sign in again.');
    final matches = await client
        .from('matches')
        .select('id,user_1,user_2')
        .or('user_1.eq.$uid,user_2.eq.$uid');
    final ids = matches
        .map((m) => (m['user_1'] == uid ? m['user_2'] : m['user_1']).toString())
        .toSet();
    final profiles = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : await client
              .from('profiles')
              .select('id,first_name,last_name,username')
              .inFilter('id', ids.toList());
    final names = <String, String>{};
    for (final p in profiles) {
      final name = [
        p['first_name'],
        p['last_name'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
      names[p['id'].toString()] = name.isEmpty
          ? p['username']?.toString() ?? 'Member'
          : name;
    }
    final members = await client
        .from('channel_members')
        .select('channel_id,channels(name)')
        .eq('user_id', uid);
    return [
      for (final m in matches)
        if ((m['user_1'] == uid ? m['user_2'] : m['user_1']) !=
                excludedSenderId &&
            names.containsKey(
              (m['user_1'] == uid ? m['user_2'] : m['user_1']).toString(),
            ))
          ForwardDestination(
            id: m['id'].toString(),
            name:
                names[(m['user_1'] == uid ? m['user_2'] : m['user_1'])
                    .toString()]!,
            group: false,
          ),
      for (final m in members)
        if (m['channels'] is Map)
          ForwardDestination(
            id: m['channel_id'].toString(),
            name: m['channels']['name']?.toString() ?? 'Group',
            group: true,
          ),
    ];
  }

  Future<void> send(
    Map<String, dynamic> message,
    ForwardDestination target,
  ) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Please sign in again.');
    if (target.group) {
      final membership = await client
          .from('channel_members')
          .select('id')
          .eq('user_id', uid)
          .eq('channel_id', target.id)
          .limit(1);
      if (membership.isEmpty) {
        throw StateError('You are no longer in this group.');
      }
      final recent = await client
          .from('channel_messages')
          .select('id')
          .eq('channel_id', target.id)
          .eq('sender_id', uid)
          .gte(
            'created_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          )
          .limit(1);
      if (recent.isNotEmpty) {
        throw StateError('Please wait a minute between group messages.');
      }
    } else {
      final match = await client
          .from('matches')
          .select('id,user_1,user_2')
          .eq('id', target.id)
          .or('user_1.eq.$uid,user_2.eq.$uid')
          .limit(1);
      if (match.isEmpty) {
        throw StateError('This conversation is no longer available.');
      }
      final other = match.first['user_1'] == uid
          ? match.first['user_2']
          : match.first['user_1'];
      if (other != null && other == message['sender_id']) {
        throw StateError('You cannot forward a message back to its sender.');
      }
    }
    final payloads = forwardPayloads(message, target, uid);
    if (payloads.first['content'] == '') {
      throw StateError('This message has no content to forward.');
    }
    final rows = await client
        .from(target.group ? 'channel_messages' : 'messages')
        .insert([
          for (final payload in payloads)
            {...payload, 'content': '$forwardedPrefix${payload['content']}'},
        ])
        .select('id');
    if (rows.length != payloads.length) {
      throw StateError(
        'Delivery could not be confirmed. Check the destination chat before retrying.',
      );
    }
  }
}
