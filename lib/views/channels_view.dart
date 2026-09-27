import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'channel_chat_view.dart';

class ChannelsView extends StatefulWidget {
  const ChannelsView({super.key});

  @override
  State<ChannelsView> createState() => _ChannelsViewState();
}

class _ChannelsViewState extends State<ChannelsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _channels = [];
  Set<String> _joinedChannelIds = {};

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final channelsResponse = await _supabase.from('channels').select();
      final channels = List<Map<String, dynamic>>.from(
        channelsResponse as List,
      );

      final memberships = await _supabase
          .from('channel_members')
          .select('channel_id')
          .eq('user_id', currentUserId);

      final joinedIds = <String>{};
      for (final item in memberships as List) {
        final channelId = item['channel_id']?.toString();
        if (channelId != null && channelId.isNotEmpty) {
          joinedIds.add(channelId);
        }
      }

      if (!mounted) return;
      setState(() {
        _channels = channels;
        _joinedChannelIds = joinedIds;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load channels: $error')),
      );
    }
  }

  Future<void> _toggleJoin(Map<String, dynamic> channel) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to join a channel.')),
      );
      return;
    }

    final channelId = channel['id']?.toString();
    if (channelId == null || channelId.isEmpty) return;

    try {
      final isJoined = _joinedChannelIds.contains(channelId);

      if (isJoined) {
        await _supabase
            .from('channel_members')
            .delete()
            .eq('channel_id', channelId)
            .eq('user_id', userId);
      } else {
        await _supabase.from('channel_members').insert({
          'channel_id': channelId,
          'user_id': userId,
        });
      }

      await _loadChannels();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update membership: $error')),
      );
    }
  }

  Widget _buildChannelList({required bool joinedOnly}) {
    final filteredChannels = _channels.where((channel) {
      final channelId = channel['id']?.toString();
      if (channelId == null) return false;
      final isJoined = _joinedChannelIds.contains(channelId);
      return joinedOnly ? isJoined : !isJoined;
    }).toList();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filteredChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            joinedOnly
                ? 'You have not joined any channels yet.'
                : 'No channels available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.of(context).muted),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredChannels.length,
      itemBuilder: (context, index) {
        final channel = filteredChannels[index];
        final channelId = channel['id']?.toString() ?? '';
        final name = channel['name']?.toString() ?? 'Untitled Channel';
        final category = channel['category']?.toString() ?? 'General';
        final description =
            channel['description']?.toString() ?? 'No description available.';
        final isJoined = _joinedChannelIds.contains(channelId);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.of(context).surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.of(context).surfaceMuted),
            boxShadow: [
              BoxShadow(
                color: AppTheme.of(context).ink.withAlpha((0.03 * 255).round()),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.of(context).surfaceMuted,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.of(context).violetStrong,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toggleJoin(channel),
                    style: TextButton.styleFrom(
                      backgroundColor: isJoined
                          ? AppTheme.of(context).surfaceMuted
                          : AppTheme.of(context).violet,
                      foregroundColor: isJoined
                          ? AppTheme.of(context).ink
                          : AppTheme.of(context).onAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(isJoined ? 'Leave' : 'Join'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: TextStyle(
                  color: AppTheme.of(context).muted,
                  height: 1.4,
                ),
              ),
              if (isJoined) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChannelChatView(
                            channelId: channelId,
                            channelName: name,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Open'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.of(context).violet,
                      foregroundColor: AppTheme.of(context).onAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Interest Channels'),
          backgroundColor: AppTheme.of(context).surface,
          foregroundColor: AppTheme.of(context).ink,
          bottom: TabBar(
            indicatorColor: AppTheme.of(context).violet,
            tabs: [
              Tab(text: 'Joined Channels'),
              Tab(text: 'Explore Channels'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChannelList(joinedOnly: true),
            _buildChannelList(joinedOnly: false),
          ],
        ),
      ),
    );
  }
}
