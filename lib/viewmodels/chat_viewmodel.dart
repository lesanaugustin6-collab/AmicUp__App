import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';

class ChatViewModel extends ChangeNotifier {
  ChatViewModel({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService();

  final SupabaseService _supabaseService;

  bool isSending = false;
  String? errorMessage;

  String? get currentUserId => _supabaseService.currentUserId;

  Future<List<Map<String, dynamic>>> loadInitialMessages(String matchId) {
    return _supabaseService.fetchMessages(matchId);
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String matchId) {
    return _supabaseService.streamMessages(matchId);
  }

  Future<void> sendMessage(String matchId, String content) async {
    isSending = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _supabaseService.sendMessage(matchId, content);
    } catch (e) {
      errorMessage = e.toString();
      rethrow;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<void> initChat(String matchId) async {
    final currentUserId = _supabaseService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    await markMessagesAsRead(
      conversationId: matchId,
      currentUserId: currentUserId,
    );
  }

  Future<void> handleIncomingMessages(String matchId, List<Map<String, dynamic>> messages) async {
    final currentUserId = _supabaseService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final hasUnreadIncoming = messages.any(
      (msg) =>
          msg['sender_id']?.toString() != currentUserId &&
          msg['is_read'] != true,
    );

    if (hasUnreadIncoming) {
      await markMessagesAsRead(
        conversationId: matchId,
        currentUserId: currentUserId,
      );
    }
  }

  Future<void> markMessagesAsRead({
    required String conversationId,
    required String currentUserId,
  }) async {
    await _supabaseService.markMessagesAsRead(
      conversationId: conversationId,
      currentUserId: currentUserId,
    );
  }
}