import 'package:amicup_app/views/friends_view.dart';
import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/theme/appearance_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final accent in AppAccent.values) {
    for (final brightness in Brightness.values) {
      testWidgets('Private friends respect $accent $brightness', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(accent: accent, brightness: brightness),
            home: FriendsView(
              userId: 'someone',
              loadFriends: (id, offset) async {
                expect(id, 'someone');
                return {
                  'private': true,
                  'count': 1,
                  'friends': [
                    {'id': 'secret', 'first_name': 'Secret'},
                  ],
                };
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Friends list is private'), findsOneWidget);
        expect(find.text('Secret'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('Visible list loads friends and usernames', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FriendsView(
          userId: 'owner',
          loadFriends: (_, _) async => {
            'private': false,
            'count': 1,
            'friends': [
              {'id': 'friend', 'first_name': 'Alex', 'username': 'alex'},
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('@alex'), findsOneWidget);
    expect(find.text('Friends list is private'), findsNothing);
  });
}
