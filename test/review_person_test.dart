import 'package:amicup_app/services/review_service.dart';
import 'package:amicup_app/views/review_person_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReviews extends ReviewService {
  bool eligible = true;
  Map<String, dynamic>? existing;
  int? savedRating;
  String? savedId;
  @override
  Future<bool> canReview(String target) async => eligible;
  @override
  Future<Map<String, dynamic>?> ownReview(String target) async => existing;
  @override
  Future<void> save(String target, int rating, String body, String? id) async {
    savedRating = rating;
    savedId = id;
  }
}

void main() {
  testWidgets('Requires stars and permits a one-star review', (tester) async {
    final service = FakeReviews();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPersonView(
          userId: 'target',
          name: 'Alex',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('1 star'));
    await tester.enterText(find.byType(TextField), 'Not a good experience.');
    await tester.pump();
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();
    expect(service.savedRating, 1);
    expect(service.savedId, isNull);
  });
  testWidgets('Existing review is prefilled and edited, not duplicated', (
    tester,
  ) async {
    final service = FakeReviews()
      ..existing = {'id': 'review-id', 'rating': 3, 'body': 'Original'};
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPersonView(
          userId: 'target',
          name: 'Alex',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    await tester.tap(find.byTooltip('5 stars'));
    await tester.pump();
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(service.savedRating, 5);
    expect(service.savedId, 'review-id');
  });
  testWidgets('Unmatched person cannot submit or edit', (tester) async {
    final service = FakeReviews()..eligible = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPersonView(
          userId: 'target',
          name: 'Alex',
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}
