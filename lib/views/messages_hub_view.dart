import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/amicup_motion.dart';
import '../widgets/animated_tab_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'channel_chat_view.dart';
import 'direct_chat_view.dart';
import 'review_person_view.dart';
import '../services/supabase_service.dart';
import '../services/inbox_service.dart';
import '../widgets/inbox_tiles.dart';
import 'activity_view.dart';
import 'create_group_view.dart';

class MessagesHubView extends StatefulWidget {
  const MessagesHubView({super.key, this.service});
  final InboxService? service;

  @override
  State<MessagesHubView> createState() => _MessagesHubViewState();
}

class _MessagesHubViewState extends State<MessagesHubView>
    with WidgetsBindingObserver {
  late final SupabaseClient _supabase =
      widget.service?.client ?? Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  late final InboxService _inbox = widget.service ?? InboxService(_supabase);
  RealtimeChannel? _realtime;
  Timer? _refreshTimer;
  Future<void>? _activeLoad;
  bool _reloadPending = false;
  String? _error;

  int _selectedTabIndex = 0;
  String _searchQuery = '';

  List<Map<String, dynamic>> _joinedGroups = [];
  List<Map<String, dynamic>> _suggestedGroups = [];
  List<Map<String, dynamic>> _directMatches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addObserver(this);
    InboxService.changes.addListener(_scheduleRefresh);
    _realtime = _inbox.watch(_scheduleRefresh);
    _loadData();
    SupabaseService.unmatchChanges.addListener(_onUnmatched);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    InboxService.changes.removeListener(_scheduleRefresh);
    _refreshTimer?.cancel();
    if (_realtime != null) unawaited(_supabase.removeChannel(_realtime!));
    SupabaseService.unmatchChanges.removeListener(_onUnmatched);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  void _onUnmatched() => unawaited(_loadData());

  void _scheduleRefresh() {
    if (!mounted) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), () => _loadData());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRefresh();
  }

  Future<void> _loadData() {
    if (_activeLoad != null) {
      _reloadPending = true;
      return _activeLoad!;
    }
    _activeLoad = _drainRefreshes().whenComplete(() => _activeLoad = null);
    return _activeLoad!;
  }

  Future<void> _drainRefreshes() async {
    do {
      _reloadPending = false;
      await _fetchData();
    } while (mounted && _reloadPending);
  }

  Future<void> _fetchData() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final initialResults = await Future.wait<dynamic>([
        _supabase.rpc('get_group_inbox'),
        _supabase.from('channels').select().eq('visibility', 'public'),
        _inbox.conversations(),
      ]);
      final groupInbox = initialResults[0];
      final joinedGroups = List<Map<String, dynamic>>.from(groupInbox as List);
      final joinedChannelIds = joinedGroups
          .map((group) => group['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final allChannels = initialResults[1];
      final channels = List<Map<String, dynamic>>.from(allChannels as List);

      final suggestedGroups = <Map<String, dynamic>>[];
      for (final channel in channels) {
        final channelId = channel['id']?.toString();
        if (channelId == null || channelId.isEmpty) continue;
        if (!joinedChannelIds.contains(channelId)) {
          suggestedGroups.add(channel);
        }
      }

      final directMatches = initialResults[2] as List<Map<String, dynamic>>;
      final counts = await _inbox.memberCounts(
        channels.map((c) => c['id'].toString()).toList(),
      );
      for (final group in suggestedGroups) {
        group['member_count'] = counts[group['id'].toString()];
      }

      if (!mounted) return;
      setState(() {
        _joinedGroups = joinedGroups;
        _suggestedGroups = suggestedGroups;
        _directMatches = directMatches;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not refresh conversations. Pull down to retry.';
      });
    }
  }

  List<Map<String, dynamic>> _filterChannels(List<Map<String, dynamic>> items) {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return items;

    return items.where((channel) {
      final name = (channel['name'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _filterDirectMatches() {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return _directMatches;

    return _directMatches.where((match) {
      final firstName = (match['first_name'] ?? '').toString().toLowerCase();
      final username = (match['username'] ?? '').toString().toLowerCase();
      return firstName.contains(query) || username.contains(query);
    }).toList();
  }

  Future<void> _joinSuggestedChannel(Map<String, dynamic> channel) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    final channelId = channel['id']?.toString();
    if (channelId == null || channelId.isEmpty) return;

    try {
      await _supabase.from('channel_members').insert({
        'channel_id': channelId,
        'user_id': currentUserId,
      });

      if (!mounted) return;
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to join channel: $error')));
    }
  }

  Widget _buildGroupsTab() {
    final joined = _filterChannels(_joinedGroups);
    final suggested = _filterChannels(_suggestedGroups);

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (joined.isNotEmpty) ...[
            Text(
              'JOINED GROUPS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppTheme.of(context).muted,
              ),
            ),
            const SizedBox(height: 12),
            ...joined.map((channel) {
              final channelId = channel['id']?.toString() ?? '';
              final name = channel['name']?.toString() ?? 'Channel';
              final memberCount = (channel['member_count'] is int)
                  ? channel['member_count']
                  : null;
              final latestMessage =
                  channel['last_message']?.toString() ?? 'No messages yet';
              final timestamp = channel['last_message_at']?.toString() ?? '';
              final unread = (channel['unread_count'] as num?)?.toInt() ?? 0;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.of(context).surfaceMuted,
                  backgroundImage: channel['image_url'] == null
                      ? null
                      : NetworkImage(channel['image_url'].toString()),
                  child: channel['image_url'] != null
                      ? null
                      : Text(
                          name
                              .substring(0, name.length > 1 ? 2 : 1)
                              .toUpperCase(),
                          style: TextStyle(
                            color: AppTheme.of(context).violetStrong,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  latestMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      inboxTime(timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.of(context).violet,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.of(context).onAccent,
                          ),
                        ),
                      )
                    else
                      Text(
                        memberCount == null
                            ? 'Members unavailable'
                            : '$memberCount members',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.of(context).muted,
                        ),
                      ),
                  ],
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChannelChatView(
                        channelId: channelId,
                        channelName: name,
                      ),
                    ),
                  );
                  if (mounted) await _loadData();
                },
              );
            }),
            const SizedBox(height: 20),
          ],

          if (suggested.isNotEmpty) ...[
            Text(
              'SUGGESTED FOR YOU',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppTheme.of(context).muted,
              ),
            ),
            const SizedBox(height: 12),
            ...suggested.map((channel) {
              final name = channel['name']?.toString() ?? 'Channel';
              final description =
                  channel['description']?.toString() ??
                  'Explore this conversation';
              final memberCount = (channel['member_count'] is int)
                  ? channel['member_count']
                  : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.of(context).surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.of(context).surfaceMuted),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.of(context).surfaceMuted,
                      backgroundImage: channel['image_url'] == null
                          ? null
                          : NetworkImage(channel['image_url'].toString()),
                      child: channel['image_url'] != null
                          ? null
                          : Text(
                              name
                                  .substring(0, name.length > 1 ? 2 : 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                color: AppTheme.of(context).violetStrong,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.of(context).muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            memberCount == null
                                ? 'Members unavailable'
                                : '$memberCount members',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.of(context).muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _joinSuggestedChannel(channel),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.of(context).violet,
                        side: BorderSide(
                          color: AppTheme.of(context).violetStrong,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Join'),
                    ),
                  ],
                ),
              );
            }),
          ],

          if (joined.isEmpty && suggested.isEmpty) ...[
            const SizedBox(height: 80),
            Center(
              child: Text(
                'No conversations match your search.',
                style: TextStyle(color: AppTheme.of(context).muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDirectTab() {
    final matches = _filterDirectMatches();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: matches.isEmpty ? 1 : matches.length,
        itemBuilder: (context, index) {
          if (matches.isEmpty) {
            return Center(
              heightFactor: 8,
              child: Text(
                'No direct conversations yet.',
                style: TextStyle(color: AppTheme.of(context).muted),
              ),
            );
          }

          final match = matches[index];
          final firstName = match['first_name']?.toString() ?? 'User';
          final username = match['username']?.toString() ?? '';
          final displayName = firstName.isNotEmpty ? firstName : username;
          final avatarUrl = match['avatar_url']?.toString();
          return DirectInboxTile(
            key: ValueKey(match['match_id']),
            conversation: match,
            onReview: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewPersonView(
                  userId: match['partner_id'].toString(),
                  name: displayName,
                ),
              ),
            ),
            onTap: () async {
              final matchId = match['match_id']?.toString() ?? '';
              final partnerId = match['partner_id']?.toString() ?? '';
              if (matchId.isEmpty || partnerId.isEmpty) return;

              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DirectChatView(
                    matchId: matchId,
                    otherUserId: partnerId,
                    otherUserName: displayName,
                    otherUserAvatar: avatarUrl,
                  ),
                ),
              );
              if (mounted) await _loadData();
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Messages',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.of(context).ink,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Create group',
                          onPressed: () async {
                            final id = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CreateGroupView(),
                              ),
                            );
                            if (id != null && mounted) await _loadData();
                          },
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search conversations...',
                        filled: true,
                        fillColor: AppTheme.of(context).surfaceMuted,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: AnimatedTabSelector(
                      labels: const ['Groups', 'Direct'],
                      icons: const [
                        Icons.groups_outlined,
                        Icons.chat_bubble_outline,
                      ],
                      selectedIndex: _selectedTabIndex,
                      onSelected: (index) =>
                          setState(() => _selectedTabIndex = index),
                    ),
                  ),
                  ActivityInboxTile(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ActivityView()),
                      );
                      if (mounted) await _loadData();
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  if (_error != null)
                    TextButton(onPressed: _loadData, child: Text(_error!)),
                  Expanded(
                    child: AmicUpContentSwitcher(
                      direction: _selectedTabIndex == 0 ? -1 : 1,
                      child: KeyedSubtree(
                        key: ValueKey(_selectedTabIndex),
                        child: _selectedTabIndex == 0
                            ? _buildGroupsTab()
                            : _buildDirectTab(),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
