import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/profile_field_codec.dart';
import 'chat_view.dart';

class MatchesListView extends StatefulWidget {
  const MatchesListView({super.key});

  @override
  State<MatchesListView> createState() => _MatchesListViewState();
}

class _MatchesListViewState extends State<MatchesListView> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _matchesChannel;

  List<Map<String, dynamic>> _matchesList = [];
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _fetchMatches() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = _supabase.auth.currentUser!.id;

      final matchesResponse = await _supabase
          .from('matches')
          .select('*')
          .or('user_1.eq.$currentUserId,user_2.eq.$currentUserId')
          .order('created_at', ascending: false);

      final matchesRows = List<Map<String, dynamic>>.from(
        matchesResponse as List,
      );
      if (matchesRows.isEmpty) {
        if (!mounted) return;
        setState(() {
          _matchesList = [];
          _isLoading = false;
        });
        return;
      }

      final partnerIds = matchesRows
          .map((m) => m['user_1'] == currentUserId ? m['user_2'] : m['user_1'])
          .whereType<String>()
          .toSet()
          .toList();

      final List<dynamic> profilesResponse = partnerIds.isEmpty
          ? <dynamic>[]
          : await _supabase
                .from('profiles')
                .select('*')
                .inFilter('id', partnerIds);

      final profilesRows = List<Map<String, dynamic>>.from(profilesResponse);
      final profileById = <String, Map<String, dynamic>>{};
      for (final profile in profilesRows) {
        final id = profile['id']?.toString();
        if (id == null || id.isEmpty) continue;
        profileById[id] = profile;
      }

      final mappedMatches = matchesRows.map((match) {
        final partnerId = match['user_1'] == currentUserId
            ? match['user_2']
            : match['user_1'];
        final partnerProfile = profileById[partnerId?.toString() ?? ''];

        return <String, dynamic>{
          'match_id': match['id'],
          'user_1': match['user_1'],
          'user_2': match['user_2'],
          'created_at': match['created_at'],
          'partner_id': partnerId,
          'display_name': [
            partnerProfile?['first_name']?.toString().trim() ?? '',
            partnerProfile?['last_name']?.toString().trim() ?? '',
          ].where((name) => name.isNotEmpty).join(' '),
          'first_name': partnerProfile?['first_name'],
          'avatar_url': partnerProfile?['avatar_url'],
          'gallery_photos': partnerProfile?['gallery_photos'] ?? '',
        };
      }).toList();

      // ignore: avoid_print
      print(
        'Fetched ${matchesRows.length} matches and ${profilesRows.length} profiles',
      );

      if (!mounted) return;
      setState(() {
        _matchesList = mappedMatches;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshMatches() async {
    await _fetchMatches();
  }

  void _subscribeToMatchesRealtime() {
    _matchesChannel = _supabase
        .channel('public:matches')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            final deletedMatchId = payload.oldRecord['id']?.toString();
            if (deletedMatchId == null || !mounted) return;

            setState(() {
              _matchesList.removeWhere(
                (match) =>
                    match['id']?.toString() == deletedMatchId ||
                    match['match_id']?.toString() == deletedMatchId,
              );
            });
          },
        )
        .subscribe();
  }

  String _formatTimestamp(dynamic value) {
    if (value == null) return '';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return '';

    final now = DateTime.now();
    final local = dt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final differenceDays = today.difference(messageDay).inDays;

    if (differenceDays == 0) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      final meridiem = local.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $meridiem';
    }

    if (differenceDays == 1) {
      return 'Yesterday';
    }

    return '${local.month}/${local.day}/${local.year}';
  }

  @override
  void initState() {
    super.initState();
    _subscribeToMatchesRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchMatches();
    });
  }

  @override
  void dispose() {
    final matchesChannel = _matchesChannel;
    if (matchesChannel != null) {
      unawaited(_supabase.removeChannel(matchesChannel));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null && _matchesList.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _fetchMatches,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_matchesList.isEmpty) {
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: _refreshMatches,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No connections yet. Discover people you might like to meet.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _fetchMatches,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshMatches,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _matchesList.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final match = _matchesList[index];
            final photos = decodeProfileList(match['gallery_photos']);
            final avatarUrl =
                (match['avatar_url']?.toString().isNotEmpty ?? false)
                ? match['avatar_url']?.toString()
                : (photos.isNotEmpty ? photos.first : null);
            final displayName = match['display_name']?.toString().trim();
            final firstName = match['first_name']?.toString().trim();
            final name = (displayName != null && displayName.isNotEmpty)
                ? displayName
                : ((firstName != null && firstName.isNotEmpty)
                      ? firstName
                      : 'Buddy');
            final timestamp = _formatTimestamp(match['created_at']);

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: avatarUrl != null
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null ? const Icon(Icons.person) : null,
                ),
                title: Text(name),
                subtitle: Text(
                  timestamp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () async {
                  final matchId = match['match_id']?.toString() ?? '';
                  if (matchId.isEmpty) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatView(matchId: matchId, otherUser: match),
                    ),
                  );
                  if (!mounted) return;
                  await _fetchMatches();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
