import 'package:flutter/material.dart';
import '../services/review_service.dart';

class ReviewPersonView extends StatefulWidget {
  const ReviewPersonView({
    super.key,
    required this.userId,
    required this.name,
    this.service,
  });
  final String userId;
  final String name;
  final ReviewService? service;
  @override
  State<ReviewPersonView> createState() => _ReviewPersonViewState();
}

class _ReviewPersonViewState extends State<ReviewPersonView> {
  late final service = widget.service ?? ReviewService();
  final body = TextEditingController();
  int rating = 0;
  String? id;
  bool loading = true, busy = false, allowed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final eligible = await service.canReview(widget.userId);
      final existing = await service.ownReview(widget.userId);
      if (!mounted) return;
      allowed = eligible;
      id = existing?['id'] as String?;
      rating = (existing?['rating'] as num?)?.toInt() ?? 0;
      body.text = existing?['body']?.toString() ?? '';
    } catch (_) {
      error = 'Could not load your review. Please try again.';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.save(widget.userId, rating, body.text, id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save. Check your connection and that you are still matched. If you already submitted a review, reopen this screen to edit it.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your review?'),
        content: const Text('Your rating and written review will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await service.delete(id!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not delete your review. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(id == null ? 'Rate ${widget.name}' : 'Your review'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (id == null && !allowed)
                    TextButton(onPressed: load, child: const Text('Try again')),
                ],
                if (!allowed)
                  const Text(
                    'You must be matched to submit or edit a review. You can still delete an existing review.',
                  ),
                const SizedBox(height: 16),
                const Text(
                  'How was your experience with this person?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      tooltip: '${index + 1} ${index == 0 ? 'star' : 'stars'}',
                      onPressed: allowed && !busy
                          ? () => setState(() => rating = index + 1)
                          : null,
                      icon: Icon(
                        index < rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 34,
                      ),
                    ),
                  ),
                ),
                Text(rating == 0 ? 'Choose 1–5 stars' : '$rating of 5 stars'),
                const SizedBox(height: 24),
                TextField(
                  controller: body,
                  enabled: allowed && !busy,
                  maxLength: 2000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Review (optional)',
                    hintText:
                        'Share your experience honestly and respectfully.',
                  ),
                ),
                const Text(
                  'Reviews are visible to signed-in members and are not anonymous. Do not include private information.',
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: allowed && !busy && rating > 0 ? save : null,
                  child: Text(
                    busy
                        ? 'Saving…'
                        : id == null
                        ? 'Submit review'
                        : 'Save review',
                  ),
                ),
                if (id != null)
                  TextButton(
                    onPressed: busy ? null : remove,
                    child: const Text('Delete my review'),
                  ),
              ],
            ),
    ),
  );
}
