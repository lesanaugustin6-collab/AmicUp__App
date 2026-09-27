import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/review_service.dart';
import '../views/review_person_view.dart';

class ProfileReviewsTab extends StatefulWidget {
  const ProfileReviewsTab({
    super.key,
    required this.userId,
    required this.onCount,
  });
  final String userId;
  final ValueChanged<int> onCount;
  @override
  State<ProfileReviewsTab> createState() => _ProfileReviewsTabState();
}

class _ProfileReviewsTabState extends State<ProfileReviewsTab> {
  final service = ReviewService();
  List<Map<String, dynamic>> reviews = [];
  bool loading = true, failed = false;
  @override
  void initState() {
    super.initState();
    ReviewService.changes.addListener(_changed);
    load();
  }

  void _changed() {
    load();
  }

  @override
  void dispose() {
    ReviewService.changes.removeListener(_changed);
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final data = await service.list(widget.userId);
      if (!mounted) return;
      reviews = data;
      widget.onCount(data.length);
    } catch (_) {
      failed = true;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final average = reviews.isEmpty
        ? null
        : reviews.fold<double>(
                0,
                (sum, r) => sum + (r['rating'] as num).toDouble(),
              ) /
              reviews.length;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (failed) ...[
            const Text('Could not load reviews.'),
            TextButton(onPressed: load, child: const Text('Try again')),
          ] else if (reviews.isEmpty)
            const Text(
              'No reviews yet. Reviews from connections will appear here.',
            )
          else ...[
            Text(
              '${average!.toStringAsFixed(1)} / 5 · ${reviews.length} reviews',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...reviews.map((r) {
              final person = r['reviewer'] as Map? ?? {};
              final name = [
                person['first_name'],
                person['last_name'],
              ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
              final date = DateTime.tryParse(
                r['created_at'].toString(),
              )?.toLocal();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty
                              ? (person['username']?.toString() ??
                                    'AmicUp member')
                              : name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Semantics(
                          label: '${r['rating']} out of 5 stars',
                          child: Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < (r['rating'] as num)
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 20,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                        if (date != null)
                          Text(
                            '${date.day}/${date.month}/${date.year}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if ((r['body']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(r['body'].toString()),
                        ],
                        if (r['reviewer_id'] ==
                            Supabase.instance.client.auth.currentUser?.id)
                          TextButton(
                            onPressed: () async {
                              final changed = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReviewPersonView(
                                    userId: widget.userId,
                                    name: 'this person',
                                  ),
                                ),
                              );
                              if (changed == true && mounted) await load();
                            },
                            child: const Text('Manage my review'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
