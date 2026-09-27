import 'package:amicup_app/services/message_forwarding.dart';
import 'package:amicup_app/widgets/reaction_picker.dart';
import 'package:amicup_app/widgets/compact_message_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Forward sends to the selected match and confirms the inserted row',
    () async {
      Map<String, dynamic>? sent;
      final client = SupabaseClient(
        'https://example.com',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/token')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-token',
                'refresh_token': 'refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': 'me',
                  'aud': 'authenticated',
                  'app_metadata': {},
                  'user_metadata': {},
                  'created_at': '2026-09-10T00:00:00Z',
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/matches')) {
            expect(request.url.queryParameters['id'], 'eq.destination');
            return http.Response(
              '[{"id":"destination","user_1":"me","user_2":"friend"}]',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/messages');
          sent = Map<String, dynamic>.from(
            (jsonDecode(request.body) as List).single,
          );
          return http.Response(
            '[{"id":"new-message"}]',
            201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test',
      );
      await MessageForwarding(client).send(
        {'content': 'Hello', 'match_id': 'source'},
        const ForwardDestination(
          id: 'destination',
          name: 'Friend',
          group: false,
        ),
      );
      expect(sent?['match_id'], 'destination');
      expect(sent?['sender_id'], 'me');
      expect(sent?['content'], 'Forwarded\nHello');
      expect(displayMessage(sent!)['content'], 'Hello');
      expect(displayMessage(sent!)['is_forwarded'], true);
      expect(forwardText(sent!), 'Hello');
      sent = null;
      await expectLater(
        MessageForwarding(client).send(
          {'content': 'Hello', 'sender_id': 'friend'},
          const ForwardDestination(
            id: 'destination',
            name: 'Friend',
            group: false,
          ),
        ),
        throwsStateError,
      );
      expect(sent, isNull);
    },
  );
  test(
    'Forwards body and attachments without original ownership or reply metadata',
    () {
      final message = {
        'id': 'old',
        'sender_id': 'other',
        'match_id': 'source',
        'reply_to_id': 'original',
        'is_read': true,
        'content': '↩ Quoted text\nCaption',
        'image_urls': ['one.jpg', 'two.jpg'],
      };
      final direct = forwardPayloads(
        message,
        const ForwardDestination(id: 'new', name: 'Friend', group: false),
        'me',
      );
      expect(direct.single, {
        'match_id': 'new',
        'sender_id': 'me',
        'content': 'Caption',
        'image_urls': ['one.jpg', 'two.jpg'],
      });
      final group = forwardPayloads(
        message,
        const ForwardDestination(id: 'group', name: 'Group', group: true),
        'me',
      );
      expect(group.length, 2);
      expect(group.first['content'], 'Caption');
      expect(group.first['image_url'], 'one.jpg');
      expect(group.last['image_url'], 'two.jpg');
      expect(
        group.every(
          (row) =>
              !row.containsKey('reply_to_id') && !row.containsKey('image_urls'),
        ),
        isTrue,
      );
    },
  );
  test('Supports joined, flag, skin-tone, and keycap emoji', () {
    for (final emoji in ['❤️', '🧑🏽‍💻', '🇲🇩', '1️⃣', '🫶']) {
      expect(isSingleEmoji(emoji), isTrue);
    }
    for (final text in ['', 'hi', '❤️❤️']) {
      expect(isSingleEmoji(text), isFalse);
    }
  });
  testWidgets('Plus picker returns custom emoji to the original action menu', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showCompactMessageMenu(
                  context,
                  ownMessage: true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More reactions'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '🧑🏽‍💻');
    await tester.tap(find.byTooltip('Use emoji'));
    await tester.pumpAndSettle();
    expect(result, 'react:🧑🏽‍💻');
  });
}
