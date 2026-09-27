import 'package:amicup_app/widgets/saved_profiles_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Saved profile opens the selected person', (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedProfilesTab(
            loadProfiles: () async => [
              {'id': 'person-id', 'first_name': 'Alex', 'username': 'alex'},
            ],
            onOpen: (id) => opened = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('@alex'), findsOneWidget);
    await tester.tap(find.text('Alex'));
    expect(opened, 'person-id');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failure can be retried and empty state is clear', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedProfilesTab(
            loadProfiles: () async {
              if (calls++ == 0) throw Exception('offline');
              return [];
            },
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load your saved profiles.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No saved profiles yet'), findsOneWidget);
    expect(calls, 2);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(calls, 3);
  });
}
