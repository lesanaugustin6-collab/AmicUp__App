import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BlockedProfilesView extends StatefulWidget {
  const BlockedProfilesView({super.key});
  @override
  State<BlockedProfilesView> createState() => _BlockedProfilesViewState();
}

class _BlockedProfilesViewState extends State<BlockedProfilesView> {
  final client = Supabase.instance.client;
  List<Map<String, dynamic>> people = [];
  bool loading = true;
  String? error;
  final busy = <String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final me = client.auth.currentUser?.id;
      if (me == null) throw StateError('Not signed in');
      final current = await client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', me);
      final legacy = await client
          .from('blocks')
          .select('blocked_user_id')
          .eq('blocker_id', me);
      final ids = {
        ...current.map((r) => r['blocked_id']),
        ...legacy.map((r) => r['blocked_user_id']),
      }.whereType<String>().toList();
      final profiles = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await client
                .from('profiles')
                .select('id, first_name, last_name, username')
                .inFilter('id', ids);
      final byId = {for (final p in profiles) p['id']: p};
      if (mounted) {
        people = [
          for (final id in ids)
            byId[id] ?? {'id': id, 'first_name': 'Blocked account'},
        ];
      }
    } catch (_) {
      error = 'Could not load blocked accounts. Please try again.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> unblock(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock this account?'),
        content: const Text(
          'This person may be able to find your profile again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy.add(id));
    try {
      final me = client.auth.currentUser!.id;
      await client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_id', id);
      await client
          .from('blocks')
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_user_id', id);
      // Re-read: RLS may deny deletion without an exception.
      await load();
      if (mounted && people.any((p) => p['id'] == id)) {
        setState(
          () => error =
              'This account is still blocked. Please check your connection and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not unblock this account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocked accounts')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null) ...[
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('Try again')),
                ],
                if (people.isEmpty && error == null)
                  const Text('You have no blocked accounts.'),
                ...people.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      [
                        p['first_name'],
                        p['last_name'],
                      ].whereType<String>().join(' ').trim(),
                    ),
                    trailing: TextButton(
                      onPressed: busy.contains(p['id'])
                          ? null
                          : () => unblock(p['id'].toString()),
                      child: const Text('Unblock'),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}
