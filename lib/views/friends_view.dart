import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_view.dart';

class FriendsView extends StatefulWidget {
  const FriendsView({super.key, required this.userId, this.loadFriends});
  final String userId;
  final Future<Map<String, dynamic>> Function(String userId, int offset)?
  loadFriends;
  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView> {
  final List<Map<String, dynamic>> _friends = [];
  bool _loading = true, _private = false;
  bool _hasMore = false;
  bool _requestActive = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_requestActive) return;
    _requestActive = true;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _friends.clear();
    });
    try {
      final data = widget.loadFriends != null
          ? await widget.loadFriends!(widget.userId, _friends.length)
          : await Supabase.instance.client.rpc(
              'get_profile_friends',
              params: {
                'target_id': widget.userId,
                'page_offset': _friends.length,
              },
            );
      if (!mounted) return;
      setState(() {
        _private = data['private'] == true;
        _hasMore = (data['friends'] as List).length >= 40;
        if (_private) {
          _friends.clear();
        } else {
          _friends.addAll(
            (data['friends'] as List).map((p) => Map<String, dynamic>.from(p)),
          );
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load friends. Please try again.');
      }
    } finally {
      _requestActive = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Friends')),
    body: _private
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Friends list is private',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This person has hidden their friends list in privacy settings.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final friend in _friends)
                  ListTile(
                    leading: CircleAvatar(
                      child: ClipOval(
                        child:
                            (friend['avatar_url']?.toString().isNotEmpty ??
                                false)
                            ? Image.network(
                                friend['avatar_url'],
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.person_outline),
                              )
                            : const Icon(Icons.person_outline),
                      ),
                    ),
                    title: Text(
                      [
                            friend['first_name'],
                            friend['last_name'],
                          ].whereType<String>().join(' ').trim().isEmpty
                          ? friend['username']?.toString() ?? 'Member'
                          : [
                              friend['first_name'],
                              friend['last_name'],
                            ].whereType<String>().join(' '),
                    ),
                    subtitle: friend['username'] == null
                        ? null
                        : Text('@${friend['username']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileView(userId: friend['id']),
                      ),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (!_loading && _error == null && _friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No friends yet')),
                  ),
              if (!_loading && _error == null && _hasMore)
                  TextButton(onPressed: _load, child: const Text('Load more')),
              ],
            ),
          ),
  );
}
