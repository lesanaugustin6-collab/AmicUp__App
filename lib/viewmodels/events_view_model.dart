import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppEvent {
  const AppEvent({
    required this.id,
    required this.hostId,
    required this.title,
    required this.description,
    required this.category,
    required this.locationName,
    required this.startTime,
    required this.endTime,
    required this.attendeeCount,
    required this.isGoing,
    this.coverImageUrl,
    this.maxAttendees,
    this.registrationLink,
  });

  final String id;
  final String hostId;
  final String title;
  final String description;
  final String category;
  final String locationName;
  final DateTime startTime;
  final DateTime? endTime;
  final int attendeeCount;
  final bool isGoing;
  final String? coverImageUrl;
  final int? maxAttendees;
  final String? registrationLink;

  factory AppEvent.fromMap(Map<String, dynamic> data, String? currentUserId) {
    final attendees = (data['event_attendees'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final goingAttendees = attendees
        .where((row) => row['status']?.toString() == 'going')
        .toList();

    return AppEvent(
      id: data['id'].toString(),
      hostId: data['host_id']?.toString() ?? '',
      title: data['title']?.toString() ?? 'Untitled event',
      description: data['description']?.toString() ?? '',
      category: data['category']?.toString() ?? 'Hangout',
      locationName:
          data['location_name']?.toString() ?? 'Location to be announced',
      startTime:
          DateTime.tryParse(data['start_time']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      endTime: DateTime.tryParse(data['end_time']?.toString() ?? '')?.toLocal(),
      attendeeCount: goingAttendees.length,
      isGoing: goingAttendees.any(
        (row) => row['user_id']?.toString() == currentUserId,
      ),
      coverImageUrl: _nonEmpty(data['cover_image_url']),
      maxAttendees: (data['max_attendees'] as num?)?.toInt(),
      registrationLink: _nonEmpty(data['registration_link']),
    );
  }

  static String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

typedef EventModel = AppEvent;

class EventsViewModel extends ChangeNotifier {
  EventsViewModel({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  bool _isDisposed = false;
  bool _isLoading = false;
  bool _isCreating = false;
  String? _errorMessage;
  List<AppEvent> _events = const [];

  List<AppEvent> get events => List.unmodifiable(_events);
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  String? get errorMessage => _errorMessage;

  Future<void> fetchUpcomingEvents({String category = 'All'}) async {
    _isLoading = true;
    _errorMessage = null;
    _safeNotifyListeners();

    try {
      var request = _supabase
          .from('events')
          .select('*, event_attendees(user_id, status)')
          .gte('start_time', DateTime.now().toUtc().toIso8601String());
      if (category != 'All') {
        request = request.eq('category', category);
      }
      final response = await request.order('start_time');
      final currentUserId = _supabase.auth.currentUser?.id;
      _events = (response as List)
          .map(
            (row) => AppEvent.fromMap(
              Map<String, dynamic>.from(row as Map),
              currentUserId,
            ),
          )
          .toList();
    } catch (error) {
      _errorMessage = 'Unable to load events. Please try again.';
      debugPrint('Failed to fetch events: $error');
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<AppEvent?> fetchEvent(String eventId) async {
    try {
      final response = await _supabase
          .from('events')
          .select('*, event_attendees(user_id, status)')
          .eq('id', eventId)
          .maybeSingle();
      if (response == null) return null;
      return AppEvent.fromMap(
        Map<String, dynamic>.from(response),
        _supabase.auth.currentUser?.id,
      );
    } catch (error) {
      _errorMessage = 'Unable to load this event.';
      _safeNotifyListeners();
      debugPrint('Failed to fetch event: $error');
      return null;
    }
  }

  Future<bool> createEvent({
    required String title,
    required String category,
    required String locationName,
    required String description,
    required DateTime startTime,
    DateTime? endTime,
    String? coverImageUrl,
    int? maxAttendees,
    String? registrationLink,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _errorMessage = 'Please sign in to create an event.';
      _safeNotifyListeners();
      return false;
    }

    _isCreating = true;
    _errorMessage = null;
    _safeNotifyListeners();
    try {
      await _supabase.from('events').insert({
        'host_id': userId,
        'title': title.trim(),
        'description': description.trim(),
        'cover_image_url': _nullableText(coverImageUrl),
        'category': category,
        'location_name': locationName.trim(),
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime?.toUtc().toIso8601String(),
        'max_attendees': maxAttendees,
        'registration_link': _nullableText(registrationLink),
      });
      await fetchUpcomingEvents();
      return true;
    } catch (error) {
      _errorMessage = 'Unable to create the event. Please try again.';
      debugPrint('Failed to create event: $error');
      return false;
    } finally {
      _isCreating = false;
      _safeNotifyListeners();
    }
  }

  Future<String?> uploadCoverImage(File imageFile) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _errorMessage = 'Please sign in to upload an image.';
      _safeNotifyListeners();
      return null;
    }

    try {
      final path = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage
          .from('event_covers')
          .upload(
            path,
            imageFile,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return _supabase.storage.from('event_covers').getPublicUrl(path);
    } catch (error) {
      _errorMessage = 'Unable to upload the cover image. Please try again.';
      _safeNotifyListeners();
      debugPrint('Failed to upload event cover: $error');
      return null;
    }
  }

  Future<bool> updateEvent({
    required String eventId,
    required String title,
    required String category,
    required String locationName,
    required String description,
    required DateTime startTime,
    DateTime? endTime,
    String? coverImageUrl,
    int? maxAttendees,
    String? registrationLink,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _errorMessage = 'Please sign in to update an event.';
      _safeNotifyListeners();
      return false;
    }

    _isCreating = true;
    _errorMessage = null;
    _safeNotifyListeners();
    try {
      await _supabase
          .from('events')
          .update({
            'title': title.trim(),
            'description': description.trim(),
            'cover_image_url': _nullableText(coverImageUrl),
            'category': category,
            'location_name': locationName.trim(),
            'start_time': startTime.toUtc().toIso8601String(),
            'end_time': endTime?.toUtc().toIso8601String(),
            'max_attendees': maxAttendees,
            'registration_link': _nullableText(registrationLink),
          })
          .eq('id', eventId)
          .eq('host_id', userId);
      await fetchUpcomingEvents();
      return true;
    } catch (error) {
      _errorMessage = 'Unable to save your event. Please try again.';
      debugPrint('Failed to update event: $error');
      return false;
    } finally {
      _isCreating = false;
      _safeNotifyListeners();
    }
  }

  Future<bool> deleteEvent(String eventId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _errorMessage = 'Please sign in to delete an event.';
      _safeNotifyListeners();
      return false;
    }

    try {
      await _supabase
          .from('events')
          .delete()
          .eq('id', eventId)
          .eq('host_id', userId);
      _events = _events.where((event) => event.id != eventId).toList();
      _errorMessage = null;
      _safeNotifyListeners();
      return true;
    } catch (error) {
      _errorMessage = 'Unable to delete your event. Please try again.';
      _safeNotifyListeners();
      debugPrint('Failed to delete event: $error');
      return false;
    }
  }

  Future<bool> toggleAttendance(String eventId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _errorMessage = 'Please sign in to join an event.';
      _safeNotifyListeners();
      return false;
    }

    final event = _events.where((item) => item.id == eventId).firstOrNull;
    final shouldJoin = !(event?.isGoing ?? false);
    try {
      if (shouldJoin) {
        await _supabase.from('event_attendees').upsert({
          'event_id': eventId,
          'user_id': userId,
          'status': 'going',
        }, onConflict: 'event_id,user_id');
      } else {
        await _supabase
            .from('event_attendees')
            .delete()
            .eq('event_id', eventId)
            .eq('user_id', userId);
      }
      await fetchUpcomingEvents();
      return true;
    } catch (error) {
      _errorMessage = 'Unable to update your attendance. Please try again.';
      _safeNotifyListeners();
      debugPrint('Failed to toggle attendance: $error');
      return false;
    }
  }

  String? _nullableText(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _safeNotifyListeners() {
    if (_isDisposed || !hasListeners) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
