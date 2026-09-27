import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  Timer? _debounceTimer;
  final Map<String, dynamic> _pendingChanges = {};
  Future<void> _saveQueue = Future.value();
  bool _isDisposed = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  final Map<String, dynamic> _settings = {
    'pause_profile': false,
    'age_min': 18,
    'age_max': 99,
    'push_notifications': true,
    'match_notifications': true,
    'message_notifications': true,
    'incognito_mode': false,
  };

  Map<String, dynamic> get settings => Map.unmodifiable(_settings);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  bool get pauseProfile => _settings['pause_profile'] == true;
  RangeValues get ageRange => RangeValues(
    (_settings['age_min'] as num? ?? 18).toDouble(),
    (_settings['age_max'] as num? ?? 99).toDouble(),
  );
  bool get pushNotifications => _settings['push_notifications'] == true;
  bool get matchNotifications => _settings['match_notifications'] == true;
  bool get messageNotifications => _settings['message_notifications'] == true;
  bool get incognitoMode => _settings['incognito_mode'] == true;
  bool get showFriendsList => _settings['show_friends_list'] != false;
  bool savingFriendsPrivacy = false;

  Future<void> setShowFriendsList(bool value) async {
    if (savingFriendsPrivacy || _isDisposed) return;
    savingFriendsPrivacy = true;
    _safeNotifyListeners();
    try {
      await _supabase.rpc('set_friends_visibility', params: {'visible': value});
      _settings['show_friends_list'] = value;
      _errorMessage = null;
    } catch (_) {
      _errorMessage =
          'Could not save friends privacy. Your setting has not changed.';
    } finally {
      savingFriendsPrivacy = false;
      _safeNotifyListeners();
    }
  }

  Future<void> loadSettings() async {
    if (_isDisposed) return;

    final uid = _supabase.auth.currentUser?.id;

    if (uid == null || uid.isEmpty) {
      _isLoading = false;
      _safeNotifyListeners();
      return;
    }

    try {
      final row = await _supabase
          .from('user_settings')
          .select()
          .eq('user_id', uid)
          .maybeSingle();

      if (row == null) {
        final defaults = _defaultSettings(uid);
        await _supabase.from('user_settings').insert(defaults);
        _settings
          ..clear()
          ..addAll(defaults);
      } else {
        final data = Map<String, dynamic>.from(row);
        _settings
          ..clear()
          ..addAll(_defaultSettings(uid))
          ..addAll(data);
      }
    } catch (error) {
      _errorMessage = 'Failed to load settings: $error';
      _settings
        ..clear()
        ..addAll(_defaultSettings(uid));
    } finally {
      if (!_isDisposed) {
        _isLoading = false;
        _safeNotifyListeners();
      }
    }
  }

  void setPauseProfile(bool value) {
    _updateSetting('pause_profile', value);
  }

  void setAgeRange(RangeValues value) {
    final min = value.start.round();
    final max = value.end.round();
    _updateSetting('age_min', min);
    _updateSetting('age_max', max);
  }

  void setPushNotifications(bool value) {
    _updateSetting('push_notifications', value);
  }

  void setMatchNotifications(bool value) {
    _updateSetting('match_notifications', value);
  }

  void setMessageNotifications(bool value) {
    _updateSetting('message_notifications', value);
  }

  void setIncognitoMode(bool value) {
    _updateSetting('incognito_mode', value);
  }

  void _updateSetting(String key, dynamic value) {
    if (_isDisposed) return;

    _settings[key] = value;
    _pendingChanges[key] = value;
    _safeNotifyListeners();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_flushChanges());
    });
  }

  Future<void> _flushChanges() {
    _debounceTimer?.cancel();
    final changes = Map<String, dynamic>.from(_pendingChanges);
    _pendingChanges.clear();
    if (changes.isEmpty) return _saveQueue;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return Future.value();
    _saveQueue = _saveQueue.then((_) => _upsertSettings(uid, changes));
    return _saveQueue;
  }

  Future<void> _upsertSettings(String uid, Map<String, dynamic> changes) async {
    _isSaving = true;
    _safeNotifyListeners();

    try {
      await _supabase.from('user_settings').upsert({
        'user_id': uid,
        ...changes,
        'updated_at': DateTime.now().toIso8601String(),
      });
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to save settings: $error';
    } finally {
      if (!_isDisposed) {
        _isSaving = false;
        _safeNotifyListeners();
      }
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await _flushChanges();
      await _supabase.auth.signOut();
      _errorMessage = null;
      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (error) {
      _errorMessage = 'Failed to sign out: $error';
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to sign out: $error')));
      }
    }
  }

  Future<void> deleteAccount(BuildContext context) async {
    try {
      // Server-side RPC drops the auth.users record and cascades related tables.
      await _supabase.rpc('delete_user_account');
      await _supabase.auth.signOut();
      _errorMessage = null;

      if (context.mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (error) {
      _errorMessage = 'Failed to delete account: $error';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $error')),
        );
      }
    }
  }

  void _safeNotifyListeners() {
    if (_isDisposed || !hasListeners) return;

    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && hasListeners) {
          notifyListeners();
        }
      });
      return;
    }

    notifyListeners();
  }

  Map<String, dynamic> _defaultSettings(String userId) {
    return {
      'user_id': userId,
      'pause_profile': false,
      'age_min': 18,
      'age_max': 99,
      'push_notifications': true,
      'match_notifications': true,
      'message_notifications': true,
      'incognito_mode': false,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  @override
  void dispose() {
    unawaited(_flushChanges());
    _debounceTimer?.cancel();
    _isDisposed = true;
    super.dispose();
  }
}
