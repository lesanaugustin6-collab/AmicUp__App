import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

class ChannelReviewsView extends StatefulWidget {
  const ChannelReviewsView({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  final String channelId;
  final String channelName;

  @override
  State<ChannelReviewsView> createState() => _ChannelReviewsViewState();
}

class _ChannelReviewsViewState extends State<ChannelReviewsView> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _reviews = _loadReviews();

  Future<List<Map<String, dynamic>>> _loadReviews() async {
    final rows = await _client
        .from('channel_reviews')
        .select('reviewer_id,rating,comment,created_at,updated_at')
        .eq('channel_id', widget.channelId)
        .order('updated_at', ascending: false);
    final reviews = List<Map<String, dynamic>>.from(rows as List);
    final ids = reviews
        .map((review) => review['reviewer_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return reviews;
    final profiles = await _client
        .from('profiles')
        .select('id,first_name,last_name,username,avatar_url')
        .inFilter('id', ids.toList());
    final profileById = {
      for (final profile in profiles as List)
        profile['id']?.toString() ?? '': Map<String, dynamic>.from(profile),
    };
    return [
      for (final review in reviews)
        {...review, 'profile': profileById[review['reviewer_id']?.toString()]},
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Channel reviews')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _reviews = _loadReviews()),
              child: const Text('Could not load reviews. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final reviews = snapshot.data!;
        if (reviews.isEmpty) {
          return Center(
            child: Text(
              'No reviews yet. Be the first to rate ${widget.channelName}.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.of(context).muted),
            ),
          );
        }
        final average =
            reviews
                .map((review) => (review['rating'] as num).toDouble())
                .reduce((a, b) => a + b) /
            reviews.length;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _reviews = _loadReviews()),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Text(
                    average.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.star_rounded,
                    color: AppTheme.of(context).violetStrong,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
                    style: TextStyle(color: AppTheme.of(context).muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...reviews.map(_reviewTile),
            ],
          ),
        );
      },
    ),
  );

  Widget _reviewTile(Map<String, dynamic> review) {
    final profile = review['profile'] is Map
        ? Map<String, dynamic>.from(review['profile'] as Map)
        : <String, dynamic>{};
    final name = [
      profile['first_name'],
      profile['last_name'],
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    final date = DateTime.tryParse(review['updated_at']?.toString() ?? '');
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment']?.toString().trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.of(context).surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.of(context).line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundImage: profile['avatar_url'] == null
                ? null
                : NetworkImage(profile['avatar_url'].toString()),
            child: profile['avatar_url'] == null
                ? Text((name.isEmpty ? '?' : name[0]).toUpperCase())
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty
                            ? profile['username']?.toString() ?? 'Member'
                            : name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      date == null
                          ? ''
                          : DateFormat.MMMd().format(date.toLocal()),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.of(context).muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: List.generate(
                    5,
                    (index) => Icon(
                      index < rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: AppTheme.of(context).violetStrong,
                    ),
                  ),
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(comment),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
