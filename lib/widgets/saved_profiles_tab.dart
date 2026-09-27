import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SavedProfilesTab extends StatefulWidget {
  const SavedProfilesTab({
    super.key,
    required this.loadProfiles,
    required this.onOpen,
  });
  final Future<List<Map<String, dynamic>>> Function() loadProfiles;
  final ValueChanged<String> onOpen;

  @override
  State<SavedProfilesTab> createState() => _SavedProfilesTabState();
}

class _SavedProfilesTabState extends State<SavedProfilesTab> {
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final profiles = await widget.loadProfiles();
      if (mounted) setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Saved profiles',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (_failed) ...[
            const Text('Could not load your saved profiles.'),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ] else if (_profiles.isEmpty) ...[
            const SizedBox(height: 32),
            Icon(
              Icons.bookmark_border_rounded,
              size: 40,
              color: AppTheme.of(context).violetStrong,
            ),
            const SizedBox(height: 12),
            const Text(
              'No saved profiles yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Save someone from Discover to find them here later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
          ] else
            ..._profiles.map((profile) {
              final name = [profile['first_name'], profile['last_name']]
                  .whereType<String>()
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .join(' ');
              final username = profile['username']?.toString() ?? '';
              final avatar = profile['avatar_url']?.toString() ?? '';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                leading: ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: avatar.isEmpty
                        ? const _AvatarPlaceholder()
                        : Image.network(
                            avatar,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _AvatarPlaceholder(),
                          ),
                  ),
                ),
                title: Text(
                  name.isNotEmpty
                      ? name
                      : (username.isNotEmpty ? username : 'AmicUp member'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: username.isEmpty ? null : Text('@$username'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => widget.onOpen(profile['id'].toString()),
              );
            }),
        ],
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.of(context).primarySoft,
    child: Icon(Icons.person_outline, color: AppTheme.of(context).violetStrong),
  );
}
