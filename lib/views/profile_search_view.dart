import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'profile_view.dart';

typedef ProfileSearch =
    Future<List<Map<String, dynamic>>> Function(String query);

class ProfileSearchView extends StatefulWidget {
  const ProfileSearchView({super.key, this.search, this.onOpen});
  final ProfileSearch? search;
  final ValueChanged<String>? onOpen;
  @override
  State<ProfileSearchView> createState() => _ProfileSearchViewState();
}

class _ProfileSearchViewState extends State<ProfileSearchView> {
  final controller = TextEditingController();
  Timer? debounce;
  int request = 0;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> results = [];
  String get query =>
      controller.text.trim().replaceFirst(RegExp(r'^@'), '').trim();
  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String _) {
    debounce?.cancel();
    final version = ++request;
    setState(() {
      results = [];
      error = null;
      loading = query.length >= 2;
    });
    if (query.length >= 2) {
      debounce = Timer(
        const Duration(milliseconds: 350),
        () => run(query, version),
      );
    }
  }

  Future<void> run(String text, int version) async {
    try {
      final data = widget.search != null
          ? await widget.search!(text)
          : List<Map<String, dynamic>>.from(
              await Supabase.instance.client.rpc(
                'search_profiles',
                params: {'search_text': text},
              ),
            );
      if (!mounted || version != request) return;
      setState(() {
        results = data;
        loading = false;
      });
    } catch (_) {
      if (!mounted || version != request) return;
      setState(() {
        error = 'Search is unavailable right now. Please try again.';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find people')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            onChanged: changed,
            decoration: InputDecoration(
              hintText: 'Name or @username',
              counterText: '',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        changed('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: () => changed(controller.text),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : query.length < 2
              ? const Center(
                  child: Text('Enter at least 2 characters to find a friend.'),
                )
              : results.isEmpty
              ? const Center(
                  child: Text(
                    'No profiles found. Try another name or username.',
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length + (results.length == 30 ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Showing the first 30 results. Refine your search to find someone specific.',
                        ),
                      );
                    }
                    final p = results[index];
                    final name = [p['first_name'], p['last_name']]
                        .whereType<String>()
                        .where((s) => s.trim().isNotEmpty)
                        .join(' ');
                    final username = p['username']?.toString() ?? '';
                    final avatar = p['avatar_url']?.toString() ?? '';
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: ClipOval(
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: avatar.isEmpty
                              ? const Icon(Icons.person_outline)
                              : Image.network(
                                  avatar,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.person_outline),
                                ),
                        ),
                      ),
                      title: Text(
                        name.isEmpty ? username : name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: username.isEmpty ? null : Text('@$username'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        final id = p['id'].toString();
                        if (widget.onOpen != null) {
                          widget.onOpen!(id);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileView(userId: id),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
