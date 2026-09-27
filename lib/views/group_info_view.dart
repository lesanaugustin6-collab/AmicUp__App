import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/group_service.dart';
import '../theme/app_theme.dart';
import 'channel_reviews_view.dart';
import 'edit_group_view.dart';

class GroupInfoView extends StatefulWidget {
  const GroupInfoView({
    super.key,
    required this.channelId,
    required this.name,
    this.embedded = false,
  });
  final String channelId;
  final String name;
  final bool embedded;

  @override
  State<GroupInfoView> createState() => _GroupInfoViewState();
}

class _GroupInfoViewState extends State<GroupInfoView> {
  final _client = Supabase.instance.client;
  late final _groups = GroupService(_client);
  late Future<Map<String, dynamic>> _data = _load();

  Future<Map<String, dynamic>> _load() async {
    final rows = await Future.wait<dynamic>([
      _client.from('channels').select().eq('id', widget.channelId).single(),
      _client
          .from('channel_members')
          .select('user_id,role,profiles(first_name,last_name,username,avatar_url)')
          .eq('channel_id', widget.channelId),
    ]);
    return {'channel': rows[0], 'members': List<Map<String, dynamic>>.from(rows[1] as List)};
  }

  Future<void> _invite() async {
    final friends = await _groups.friends();
    if (!mounted) return;
    final currentData = await _data;
    if (!mounted) return;
    final memberIds = (currentData['members'] as List<Map<String, dynamic>>)
        .map((m) => m['user_id'].toString()).toSet();
    final choices = friends.where((friend) => !memberIds.contains(friend['id'].toString())).toList();
    final friend = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [for (final item in choices) ListTile(
          leading: CircleAvatar(backgroundImage: item['avatar_url'] == null ? null : NetworkImage(item['avatar_url'].toString())),
          title: Text(item['first_name']?.toString() ?? item['username']?.toString() ?? 'Member'),
          onTap: () => Navigator.pop(context, item),
        )],
      )),
    );
    if (friend == null) return;
    try {
      await _groups.invite(widget.channelId, friend['id'].toString());
      if (mounted) setState(() => _data = _load());
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add member: $error')));
    }
  }

  Future<void> _showRating() async {
    var rating = 0;
    final comment = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          title: const Text('Rate this channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) => IconButton(
                  onPressed: () => setDialogState(() => rating = index + 1),
                  icon: Icon(index < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: AppTheme.of(context).violetStrong),
                )),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: comment,
                maxLength: 500,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: rating == 0
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Post rating'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      comment.dispose();
      return;
    }
    try {
      await _groups.ratePublicChannel(channelId: widget.channelId, rating: rating, comment: comment.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Channel rating posted')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not rate this channel: $error')));
    } finally {
      comment.dispose();
    }
  }

  Future<void> _changeRole(String userId, String role) async {
    try {
      await _groups.setRole(widget.channelId, userId, role);
      if (mounted) {
        setState(() {
          _data = _load();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update moderator role: $error')),
        );
      }
    }
  }

  Future<void> _confirmModerator(String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Make $name a moderator?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Moderators can:'),
            SizedBox(height: 8),
            Text('• Add matched friends to private groups'),
            Text('• Remove regular members'),
            SizedBox(height: 12),
            Text('Only owners can edit group details, change moderators, or remove an owner.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Make moderator')),
        ],
      ),
    );
    if (confirmed == true) await _changeRole(userId, 'moderator');
  }

  Future<void> _removeMember(String userId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('They will lose access to this group and its messages.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _groups.removeMember(widget.channelId, userId);
      if (mounted) setState(() { _data = _load(); });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove member: $error')));
    }
  }

  Future<void> _editGroup(Map<String, dynamic> channel) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditGroupView(channel: channel)),
    );
    if (changed == true && mounted) setState(() { _data = _load(); });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Group info'),
      automaticallyImplyLeading: !widget.embedded,
      leading: widget.embedded ? IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)) : null,
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load group info.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final channel = Map<String, dynamic>.from(snapshot.data!['channel'] as Map);
        final members = snapshot.data!['members'] as List<Map<String, dynamic>>;
        final uid = _client.auth.currentUser?.id;
        final myMembership = members.where((m) => m['user_id']?.toString() == uid).toList();
        final myRole = myMembership.isEmpty
            ? 'member'
            : myMembership.first['role']?.toString() ?? 'member';
        final canManage = myRole == 'owner';
        final isPrivate = channel['visibility']?.toString() == 'private';
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: CircleAvatar(radius: 42, backgroundImage: channel['image_url'] == null ? null : NetworkImage(channel['image_url'].toString()), child: channel['image_url'] == null ? const Icon(Icons.groups_rounded, size: 34) : null)),
            const SizedBox(height: 12),
            Center(child: Text(widget.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Center(child: Text(isPrivate ? 'Private group' : 'Public channel', style: TextStyle(color: AppTheme.of(context).muted))),
            if (canManage)
              Center(
                child: TextButton.icon(
                  onPressed: () => _editGroup(channel),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit group details'),
                ),
              ),
            if (!isPrivate)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 2,
                children: [
                  TextButton.icon(
                    onPressed: _showRating,
                    icon: const Icon(Icons.star_outline_rounded),
                    label: const Text('Rate this channel'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelReviewsView(
                          channelId: widget.channelId,
                          channelName: widget.name,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.reviews_outlined),
                    label: const Text('All reviews'),
                  ),
                ],
              ),
            if ((channel['description']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height:18), Text(channel['description'].toString())],
            if ((channel['rules']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height:18), const Text('Rules', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height:6), Text(channel['rules'].toString())],
            const SizedBox(height: 18),
            Text(
              (channel['message_cooldown_seconds'] as num? ?? 0).toInt() == 0
                  ? 'No message timer'
                  : '${channel['message_cooldown_seconds']} seconds between messages',
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
            const SizedBox(height: 18),
            Row(children: [const Text('Members', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const Spacer(), if (isPrivate && (canManage || myRole == 'moderator')) TextButton.icon(onPressed: _invite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add'))]),
            ...members.map((member) {
              final profile = member['profiles'] is Map ? Map<String,dynamic>.from(member['profiles'] as Map) : <String,dynamic>{};
              final role = member['role']?.toString() ?? 'member';
              final name = [profile['first_name'], profile['last_name']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
              final isOtherMember = member['user_id']?.toString() != uid;
              final canRemove = isOtherMember &&
                  (canManage || (myRole == 'moderator' && role == 'member'));
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundImage: profile['avatar_url'] == null ? null : NetworkImage(profile['avatar_url'].toString())),
                title: Text(name.isEmpty ? profile['username']?.toString() ?? 'Member' : name),
                subtitle: Text(role[0].toUpperCase() + role.substring(1)),
                trailing: canRemove
                    ? PopupMenuButton<String>(
                        onSelected: (value) {
                          final memberId = member['user_id'].toString();
                          if (value == 'moderator') {
                            _confirmModerator(memberId, name.isEmpty ? 'this member' : name);
                          } else if (value == 'remove') {
                            _removeMember(memberId, name.isEmpty ? 'this member' : name);
                          } else {
                            _changeRole(memberId, 'member');
                          }
                        },
                        itemBuilder: (_) => [
                          if (canManage && role != 'moderator')
                            const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                          if (canManage && role == 'moderator')
                            const PopupMenuItem(value: 'member', child: Text('Remove moderator')),
                          const PopupMenuItem(value: 'remove', child: Text('Remove from group')),
                        ],
                      ) : null,
              );
            }),
          ],
        );
      },
    ),
  );
}
