import 'dart:convert';
import 'package:amicup_app/services/inbox_service.dart';
import 'package:amicup_app/views/activity_view.dart';
import 'package:amicup_app/views/messages_hub_view.dart';
import 'package:amicup_app/views/image_gallery_view.dart';
import 'package:amicup_app/widgets/chat_photo_thumbnail.dart';
import 'package:amicup_app/widgets/message_interaction.dart';
import 'package:amicup_app/widgets/inbox_tiles.dart';
import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/theme/appearance_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _InboxApi {
  List<Map<String, dynamic>> conversations = [
    {
      'match_id': 'a',
      'partner_id': 'anna',
      'first_name': 'Anna',
      'unread_count': 0,
      'last_message': 'Hello',
      'last_message_at': '2026-09-11T10:00:00Z',
    },
    {
      'match_id': 'b',
      'partner_id': 'bogdan',
      'first_name': 'Bogdan',
      'unread_count': 0,
      'last_message': 'See you',
      'last_message_at': '2026-09-10T10:00:00Z',
    },
  ];
  Map<String, dynamic>? readRequest;
  bool failActivity = false;
  final offsets = <int>[];
  late final client = SupabaseClient(
    'https://example.com',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      dynamic result;
      switch (request.url.path) {
        case '/auth/v1/token':
          result = {
            'access_token': 'test-token',
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'me',
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-11T00:00:00Z',
            },
          };
        case '/rest/v1/channel_members':
          result = [
            {
              'channel_id': 'group',
              'channels': {'id': 'group', 'name': 'Runners'},
            },
          ];
        case '/rest/v1/channels':
          result = [
            {'id': 'group', 'name': 'Runners'},
          ];
        case '/rest/v1/rpc/get_channel_member_counts':
          result = [
            {'channel_id': 'group', 'member_count': 27},
          ];
        case '/rest/v1/rpc/get_direct_inbox':
          result = conversations;
        case '/rest/v1/rpc/get_profile_activity':
          if (failActivity) {
            return http.Response(
              '{"message":"Offline"}',
              503,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          final offset = jsonDecode(request.body)['page_offset'] as int;
          offsets.add(offset);
          result = offset == 0
              ? [
                  for (var i = 0; i < 40; i++)
                    {
                      'id': 'like:$i',
                      'kind': i == 0 ? 'match' : 'like',
                      'actor_id': 'person-$i',
                      'first_name': 'Person $i',
                      'occurred_at': '2026-09-11T10:00:00Z',
                    },
                ]
              : [
                  {
                    'id': 'like:40',
                    'kind': 'like',
                    'actor_id': 'last',
                    'first_name': 'Last person',
                  },
                ];
        case '/rest/v1/rpc/mark_direct_messages_read':
          readRequest = Map<String, dynamic>.from(jsonDecode(request.body));
          result = null;
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
      return http.Response(
        jsonEncode(result),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  Future<void> signIn() => client.auth.signInWithPassword(
    email: 'test@example.com',
    password: 'test',
  );
}

class _InboxService extends InboxService {
  _InboxService(super.client);
  VoidCallback? onChange;
  @override
  RealtimeChannel? watch(VoidCallback onChange) {
    this.onChange = onChange;
    return null;
  }
}

void main() {
  testWidgets(
    'Inbox live refresh shows counts and moves chat; Activity stays pinned during search',
    (tester) async {
      final api = _InboxApi();
      await tester.runAsync(api.signIn);
      addTearDown(() => tester.runAsync(api.client.dispose));
      final service = _InboxService(api.client);
      await tester.pumpWidget(
        MaterialApp(home: MessagesHubView(service: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('27 members'), findsOneWidget);
      await tester.tap(find.text('Direct'));
      await tester.pumpAndSettle();
      final activityPosition = tester.getTopLeft(
        find.byKey(const ValueKey('pinned-activity')),
      );
      expect(
        tester.getTopLeft(find.text('Anna')).dy,
        lessThan(tester.getTopLeft(find.text('Bogdan')).dy),
      );
      api.conversations = [
        {
          ...api.conversations[1],
          'unread_count': 3,
          'last_message': 'New message',
          'last_message_at': '2026-09-11T11:00:00Z',
        },
        api.conversations[0],
      ];
      service.onChange!();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('New message'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Bogdan')).dy,
        lessThan(tester.getTopLeft(find.text('Anna')).dy),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('pinned-activity'))),
        activityPosition,
      );
      await tester.enterText(find.byType(TextField), 'no-match');
      await tester.pumpAndSettle();
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Bogdan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'Read receipts only send IDs of messages displayed, with the correct conversation',
    () async {
      final api = _InboxApi();
      addTearDown(api.client.dispose);
      final service = InboxService(api.client);
      await service.markRead('conversation-a', ['message-1', 'message-2']);
      expect(api.readRequest, {
        'conversation_id': 'conversation-a',
        'message_ids': ['message-1', 'message-2'],
      });
      api.readRequest = null;
      await service.markRead('conversation-a', []);
      expect(api.readRequest, isNull);
    },
  );

  testWidgets(
    'Activity retries a failed request, opens actor profile, and paginates',
    (tester) async {
      final api = _InboxApi()..failActivity = true;
      await tester.runAsync(api.signIn);
      addTearDown(() => tester.runAsync(api.client.dispose));
      final service = _InboxService(api.client);
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: ActivityView(
            service: service,
            onOpenProfile: (id) => opened = id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      api.failActivity = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Person 0'));
      expect(opened, 'person-0');
      await tester.scrollUntilVisible(find.text('Load more'), 500);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(api.offsets, [0, 40]);
      await tester.scrollUntilVisible(find.text('Last person'), 300);
      expect(find.text('Last person'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Group single photo opens zoom gallery inside message gesture wrapper',
    (tester) async {
      var hearts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: MessageInteraction(
                  onOptions: () {},
                  onHeart: () => hearts++,
                  onReply: () {},
                  child: const ChatPhotoThumbnail(
                    images: ['https://example.com/photo.jpg'],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChatPhotoThumbnail));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(ImageGalleryView), findsOneWidget);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        4,
      );
      expect(hearts, 0);
    },
  );

  for (final accent in AppAccent.values) {
    for (final brightness in Brightness.values) {
      testWidgets('Inbox badge and activity fit $accent $brightness', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(360, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(accent: accent, brightness: brightness),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: Column(
                  children: [
                    ActivityInboxTile(onTap: () {}),
                    DirectInboxTile(
                      conversation: {
                        'first_name': 'A very long name for a friend',
                        'unread_count': 143,
                        'last_message':
                            'Forwarded\n[IMAGE]: https://example.com/photo.jpg',
                        'last_message_at': '2026-09-10T09:00:00Z',
                      },
                      onTap: () {},
                      onReview: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('99+'), findsOneWidget);
        expect(find.text('Forwarded · Photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
