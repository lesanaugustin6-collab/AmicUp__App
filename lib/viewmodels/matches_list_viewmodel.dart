import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class MatchesListViewModel extends ChangeNotifier {
  MatchesListViewModel({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService() {
    _subscribeToRealtimeMessages();
  }

  final SupabaseService _supabaseService;
  RealtimeChannel? _messagesChannel;
  bool _isReloading = false;

  List<Map<String, dynamic>> matches = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadMatches() async {
    await _reloadMatches(showLoading: true);
  }

  Future<void> unmatchUser({required String targetUserId}) async {
    if (targetUserId.isEmpty) return;

    try {
      await _supabaseService.unmatchUser(targetUserId: targetUserId);
      matches.removeWhere(
        (m) =>
            (m['id']?.toString() ?? '') == targetUserId ||
            (m['partner_id']?.toString() ?? '') == targetUserId,
      );
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _reloadMatches({required bool showLoading}) async {
    if (_isReloading) return;
    _isReloading = true;

    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }

    errorMessage = null;

    try {
      matches = await _supabaseService.fetchUserMatches();
    } catch (e) {
      errorMessage = e.toString();
      matches = [];
    } finally {
      if (showLoading) {
        isLoading = false;
      }
      _isReloading = false;
      notifyListeners();
    }
  }

  void _subscribeToRealtimeMessages() {
    final userId = _supabaseService.currentUserId;
    if (userId == null) return;

    _messagesChannel = Supabase.instance.client
        .channel('public:messages:matches-list:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) {
            unawaited(_reloadMatches(showLoading: false));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _messagesChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }
}