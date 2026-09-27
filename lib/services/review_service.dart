import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ReviewService {
  static final changes = ValueNotifier<int>(0);
  SupabaseClient get client => Supabase.instance.client;

  Future<bool> canReview(String target) async {
    final me = client.auth.currentUser?.id;
    if (me == null || me == target) return false;
    final matches = await client
        .from('matches')
        .select('user_1, user_2')
        .or('user_1.eq.$me,user_2.eq.$me');
    return matches.any(
      (m) =>
          (m['user_1'] == me && m['user_2'] == target) ||
          (m['user_2'] == me && m['user_1'] == target),
    );
  }

  Future<Map<String, dynamic>?> ownReview(String target) async {
    final me = client.auth.currentUser?.id;
    if (me == null) return null;
    return client
        .from('profile_reviews')
        .select()
        .eq('reviewer_id', me)
        .eq('reviewed_user_id', target)
        .maybeSingle();
  }

  Future<void> save(String target, int rating, String body, String? id) async {
    if (rating < 1 || rating > 5 || body.runes.length > 2000) {
      throw ArgumentError('Choose 1–5 stars and at most 2000 characters.');
    }
    if (!await canReview(target)) {
      throw StateError('You must still be matched to review this person.');
    }
    final me = client.auth.currentUser!.id;
    if (id == null) {
      await client.from('profile_reviews').insert({
        'reviewer_id': me,
        'reviewed_user_id': target,
        'rating': rating,
        'body': body.trim(),
      });
    } else {
      await client
          .from('profile_reviews')
          .update({'rating': rating, 'body': body.trim()})
          .eq('id', id)
          .eq('reviewer_id', me)
          .eq('reviewed_user_id', target)
          .select('id')
          .single();
    }
    changes.value++;
  }

  Future<void> delete(String id) async {
    final me = client.auth.currentUser?.id;
    if (me == null) throw StateError('Please sign in again.');
    await client
        .from('profile_reviews')
        .delete()
        .eq('id', id)
        .eq('reviewer_id', me);
    changes.value++;
  }

  Future<List<Map<String, dynamic>>> list(String target) async {
    return client
        .from('profile_reviews')
        .select(
          '*, reviewer:profiles!profile_reviews_reviewer_id_fkey(first_name, last_name, username)',
        )
        .eq('reviewed_user_id', target)
        .order('created_at', ascending: false);
  }
}
