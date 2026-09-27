import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static const AndroidNotificationChannel _foregroundSilentChannel =
      AndroidNotificationChannel(
        'foreground_silent_v1',
        'Silent in-app banners',
        description: 'Used for important notifications.',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
      );
  static const AndroidNotificationChannel _backgroundMessageChannel =
      AndroidNotificationChannel(
        'background_messages_v1',
        'Messages',
        description: 'Message notifications received outside the app.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

  factory NotificationService() => _instance;

  final visibleChats = <Object, bool Function(Map<String, dynamic>)>{};
  void Function(Map<String, dynamic>)? onNotificationTap;
  final _recentMessages = <String, DateTime>{};

  bool shouldSuppress(Map<String, dynamic> payload) =>
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
      visibleChats.values.any((isVisible) => isVisible(payload));

  void _onTap(NotificationResponse response) {
    try {
      final payload = jsonDecode(response.payload ?? '{}');
      if (payload is Map<String, dynamic> && payload.isNotEmpty) {
        onNotificationTap?.call(payload);
      }
    } on FormatException catch (_) {
      debugPrint('Ignored invalid notification payload');
    }
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _localNotificationsInitialized = false;
  StreamSubscription<RemoteMessage>? _foregroundMessagesSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  Future<void> initNotifications() async {
    try {
      await FirebaseMessaging.instance.requestPermission(sound: true);
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: true,
            sound: false,
          );
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (e) {
      debugPrint('Failed to initialize Firebase Messaging: $e');
    }

    try {
      await _initializeLocalNotifications();
    } catch (e) {
      debugPrint('Failed to initialize local notifications: $e');
    }

    _foregroundMessagesSubscription ??= FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      final title =
          message.notification?.title ??
          message.data['title']?.toString() ??
          'Notification';

      final payload = message.data;
      final rawBody =
          message.notification?.body ??
          payload['body']?.toString() ??
          payload['content']?.toString() ??
          '';
      final senderName = payload['sender_name']?.toString().trim() ?? 'Someone';
      final displayBody = sanitizeNotificationBody(rawBody, senderName);

      if (rawBody.trim().isEmpty && payload.isEmpty) return;

      unawaited(
        _sendNotification(
          title: title,
          payload: {
            ...payload,
            'body': displayBody,
            if (payload['body'] == null && payload['content'] == null)
              'content': displayBody,
          },
        ),
      );
    });

    _authStateSubscription ??= Supabase.instance.client.auth.onAuthStateChange
        .listen((authState) {
          if (authState.event == AuthChangeEvent.signedIn ||
              authState.event == AuthChangeEvent.tokenRefreshed ||
              authState.event == AuthChangeEvent.userUpdated) {
            unawaited(updateFcmToken());
          }
        });

    await updateFcmToken();
  }

  Future<void> updateFcmToken() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Failed to fetch FCM token (network/device issue): $e');
    }

    if (token != null && token.isNotEmpty) {
      await _syncFcmToken(supabase: supabase, userId: userId, token: token);
    }

    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh
        .listen(
          (refreshedToken) async {
            final refreshedUserId = supabase.auth.currentUser?.id;
            if (refreshedUserId == null || refreshedToken.isEmpty) {
              return;
            }

            await _syncFcmToken(
              supabase: supabase,
              userId: refreshedUserId,
              token: refreshedToken,
            );
          },
          onError: (Object e) {
            debugPrint('FCM token refresh stream error: $e');
          },
        );
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsInitialized) {
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onTap,
    );
    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      _onTap(launch!.notificationResponse!);
    }

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      _foregroundSilentChannel,
    );
    await androidImplementation?.createNotificationChannel(
      _backgroundMessageChannel,
    );
    await androidImplementation?.requestNotificationsPermission();

    _localNotificationsInitialized = true;
  }

  Future<void> _syncFcmToken({
    required SupabaseClient supabase,
    required String userId,
    required String token,
  }) async {
    try {
      await supabase
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (e) {
      debugPrint('Failed to sync FCM token: $e');

      final shouldRefreshSession =
          (e is PostgrestException && e.code == 'PGRST303') ||
          e.toString().toUpperCase().contains('JWT');

      if (shouldRefreshSession) {
        try {
          await supabase.auth.refreshSession();
        } catch (refreshError) {
          debugPrint(
            'Failed to refresh session after FCM sync error: $refreshError',
          );
        }
      }
    }
  }

  String sanitizeNotificationBody(String body, String senderName) {
    final trimmed = body.trim();
    final bool isImage = trimmed.contains('chat_images') ||
        trimmed.contains('storage/v1/object') ||
        trimmed.startsWith('[IMAGE]:') ||
        trimmed.endsWith('.jpg') ||
        trimmed.endsWith('.jpeg') ||
        trimmed.endsWith('.png') ||
        trimmed.endsWith('.webp');

    if (isImage) {
      return 'sent a photo 📷';
    }

    return body;
  }

  Future<void> _sendNotification({
    required String title,
    required Map<String, dynamic> payload,
  }) async {
    final String senderName =
        payload['sender_name']?.toString().trim() ?? 'Someone';
    final String rawBody =
        payload['body']?.toString() ?? payload['content']?.toString() ?? title;
    final bool hasImage =
        payload['image_url'] != null ||
        payload['has_image'] == true ||
        (payload['content']?.toString().toLowerCase() ?? '').contains(
          'chat_images',
        ) ||
        (payload['content']?.toString().toLowerCase() ?? '').contains(
          'storage/v1/object',
        ) ||
        (payload['content']?.toString().toLowerCase() ?? '').contains('.jpg') ||
        (payload['content']?.toString().toLowerCase() ?? '').contains('.png') ||
        (payload['content']?.toString().toLowerCase() ?? '').contains(
          '.jpeg',
        ) ||
        (payload['content']?.toString().toLowerCase() ?? '').contains('.webp');

    final body = hasImage
        ? 'sent a photo 📷'
        : sanitizeNotificationBody(rawBody, senderName);

    await showNotification(title: title, body: body, payload: payload);
  }

  Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic> payload = const {},
  }) async {
    if (shouldSuppress(payload)) return;
    if (title.trim().isEmpty || body.trim().isEmpty) {
      return;
    }

    await _initializeLocalNotifications();
    if (shouldSuppress(payload)) return;
    final messageId = payload['message_id']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      final now = DateTime.now();
      _recentMessages.removeWhere(
        (_, time) => now.difference(time).inMinutes >= 5,
      );
      if (_recentMessages.containsKey(messageId)) return;
      _recentMessages[messageId] = now;
    }

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      payload: jsonEncode(payload),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'foreground_silent_v1',
          'Silent in-app banners',
          channelDescription: 'Used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
          presentBanner: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: false,
        ),
      ),
    );
  }
}
