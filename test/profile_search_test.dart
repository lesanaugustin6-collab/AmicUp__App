import 'dart:async';
import 'package:amicup_app/views/profile_search_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Search strips @, waits for typing, and opens a profile', (
    tester,
  ) async {
    final queries = <String>[];
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSearchView(
          search: (query) async {
            queries.add(query);
            return [
              {'id': 'friend', 'first_name': 'Alex', 'username': 'alex'},
            ];
          },
          onOpen: (id) => opened = id,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '@alex');
    await tester.pump(const Duration(milliseconds: 200));
    expect(queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(queries, ['alex']);
    await tester.tap(find.text('Alex'));
    expect(opened, 'friend');
  });
  testWidgets('Old responses cannot replace a newer search or cleared input', (
    tester,
  ) async {
    final old = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSearchView(
          search: (q) async => q == 'old' ? old.future : [],
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    old.complete([
      {'id': 'old', 'first_name': 'Stale'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Stale'), findsNothing);
    expect(
      find.text('Enter at least 2 characters to find a friend.'),
      findsOneWidget,
    );
  });
  testWidgets('Failure is shown and retry succeeds', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSearchView(
          search: (_) async {
            if (calls++ == 0) throw Exception('offline');
            return [];
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.text('No profiles found. Try another name or username.'),
      findsOneWidget,
    );
  });
}
