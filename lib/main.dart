import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_controller.dart';
import 'viewmodels/events_view_model.dart';
import 'views/auth_gate.dart';
import 'views/channel_chat_view.dart';
import 'views/direct_chat_view.dart';
import 'views/messages_hub_view.dart';

final supabase = Supabase.instance.client;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
Map<String, dynamic>? _pendingNotificationPayload;

void handleNotificationNavigation(RemoteMessage message) {
  handleNotificationPayload(message.data);
}

void handleNotificationPayload(Map<String, dynamic> payload) {
  final type = payload['type']?.toString().toLowerCase() ?? '';
  final matchId = payload['match_id']?.toString();
  final senderId = payload['sender_id']?.toString();
  final senderName = payload['sender_name']?.toString() ?? 'Chat';
  final channelId = payload['channel_id']?.toString();
  final channelName = payload['channel_name']?.toString() ?? 'Group';

  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    _pendingNotificationPayload = payload;
    return;
  }

  if (type == 'direct' || (matchId != null && matchId.isNotEmpty)) {
    navigator.push(
      MaterialPageRoute(
        builder: (context) => DirectChatView(
          matchId: matchId ?? '',
          otherUserId: senderId ?? '',
          otherUserName: senderName,
        ),
      ),
    );
    return;
  }

  if (type == 'channel' || (channelId != null && channelId.isNotEmpty)) {
    navigator.push(
      MaterialPageRoute(
        builder: (context) => ChannelChatView(
          channelId: channelId ?? '',
          channelName: channelName,
        ),
      ),
    );
    return;
  }

  navigator.push(
    MaterialPageRoute(builder: (context) => const MessagesHubView()),
  );
}

Future<void> setupFCMNavigation() async {
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    handleNotificationNavigation(initialMessage);
  }

  FirebaseMessaging.onMessageOpenedApp.listen(handleNotificationNavigation);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      rethrow;
    }
  } catch (_) {}

  final firebaseMessaging = FirebaseMessaging.instance;
  debugPrint('FCM initialized: $firebaseMessaging');

  await Supabase.initialize(
    url: 'https://tjlbuggkrudvsxxskjyz.supabase.co',
    publishableKey: 'sb_publishable_UNDjmLF6Cbd25XkP8bJGJg_vm0basbZ',
  );

  await AppearanceController.instance.load();
  runApp(const AmicUpApp());
}

class AmicUpApp extends StatefulWidget {
  const AmicUpApp({super.key});

  @override
  State<AmicUpApp> createState() => _AmicUpAppState();
}

class _AmicUpAppState extends State<AmicUpApp> {
  void _flushPendingNotification() {
    final pending = _pendingNotificationPayload;
    _pendingNotificationPayload = null;
    if (pending != null) handleNotificationPayload(pending);
  }

  @override
  void initState() {
    super.initState();
    NotificationService().onNotificationTap = handleNotificationPayload;
    setupFCMNavigation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _flushPendingNotification();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => EventsViewModel())],
      child: AnimatedBuilder(
        animation: AppearanceController.instance,
        builder: (context, _) => MaterialApp(
          navigatorKey: navigatorKey,
          title: 'AmicUp',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(accent: AppearanceController.instance.accent),
          darkTheme: AppTheme.build(
            accent: AppearanceController.instance.accent,
            brightness: Brightness.dark,
          ),
          themeMode: AppearanceController.instance.mode,
          home: const AuthGate(),
          routes: {'/login': (_) => const AuthGate()},
        ),
      ),
    );
  }
}
