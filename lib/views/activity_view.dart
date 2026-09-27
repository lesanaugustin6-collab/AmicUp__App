import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/inbox_service.dart';
import '../widgets/inbox_tiles.dart';
import 'profile_view.dart';

class ActivityView extends StatefulWidget {
  const ActivityView({super.key, this.service, this.onOpenProfile});
  final InboxService? service;
  final ValueChanged<String>? onOpenProfile;
  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView>
    with WidgetsBindingObserver {
  late final InboxService _service =
      widget.service ?? InboxService(Supabase.instance.client);
  final List<Map<String, dynamic>> _items = [];
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  bool _loading = false, _hasMore = true, _reloadPending = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = _service.watch(_scheduleRefresh);
    unawaited(_load(reset: true));
  }

  void _scheduleRefresh() {
    if (!mounted) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 300),
      () => _load(reset: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRefresh();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) {
      if (reset) _reloadPending = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.activity(offset: reset ? 0 : _items.length);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        final seen = _items.map((e) => e['id']).toSet();
        _items.addAll(rows.where((e) => seen.add(e['id'])));
        _hasMore = rows.length == 40;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load activity. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_reloadPending) {
          _reloadPending = false;
          unawaited(_load(reset: true));
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    if (_channel != null) unawaited(_service.client.removeChannel(_channel!));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activity')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_items.isEmpty && _loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_items.isEmpty && !_loading && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 64),
              child: Text(
                'New connections and people who want to connect will appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final item in _items)
            ActivityItemTile(
              item: item,
              onTap: () async {
                if (widget.onOpenProfile != null) {
                  widget.onOpenProfile!(item['actor_id'].toString());
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfileView(userId: item['actor_id'].toString()),
                  ),
                );
                if (mounted) unawaited(_load(reset: true));
              },
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _load(reset: _items.isEmpty),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          if (_items.isNotEmpty && _hasMore && _error == null)
            TextButton(
              onPressed: _loading ? null : _load,
              child: Text(_loading ? 'Loading…' : 'Load more'),
            ),
        ],
      ),
    ),
  );
}

class ActivityItemTile extends StatelessWidget {
  const ActivityItemTile({super.key, required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final first = item['first_name']?.toString().trim() ?? '';
    final name = first.isEmpty
        ? item['username']?.toString() ?? 'Member'
        : first;
    final match = item['kind'] == 'match';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: InboxAvatar(name: name, url: item['avatar_url']?.toString()),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${match ? 'You connected' : 'Wants to connect'} · ${inboxTime(item['occurred_at']?.toString())}',
      ),
      trailing: Icon(
        match
            ? Icons.people_outline_rounded
            : Icons.check_circle_outline_rounded,
        color: colors.onPrimaryContainer,
      ),
      onTap: onTap,
    );
  }
}
