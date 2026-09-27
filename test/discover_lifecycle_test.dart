import 'package:amicup_app/views/discover_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Discover retains cards across tab changes and renders the next card',
    (tester) async {
      var tab = 0;
      var loads = 0;
      final swiped = <String>[];
      final discover = DiscoverView(
        loadProfiles: () async {
          loads++;
          return [
            for (var i = 0; i < 3; i++)
              {
                'id': '$i',
                'first_name': 'Person $i',
                'avatar_url': 'https://example.com/$i.jpg',
              },
          ];
        },
        onInteraction: (id, _) async => swiped.add(id),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: IndexedStack(
                index: tab,
                children: [
                  discover,
                  const Center(child: Text('My profile')),
                ],
              ),
              bottomNavigationBar: TextButton(
                onPressed: () => setState(() => tab = 1 - tab),
                child: const Text('Switch tab'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CardSwiper>(find.byType(CardSwiper))
            .numberOfCardsDisplayed,
        2,
      );
      expect(find.byType(Image), findsNWidgets(2));
      await tester.tap(find.text('Switch tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch tab'));
      await tester.pumpAndSettle();
      expect(find.byType(CardSwiper), findsOneWidget);
      expect(loads, 1);
      tester
          .widget<CardSwiper>(find.byType(CardSwiper))
          .controller!
          .swipeLeft();
      await tester.pumpAndSettle();
      expect(swiped, ['2']);
      await tester.tap(find.text('Switch tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch tab'));
      await tester.pumpAndSettle();
      tester
          .widget<CardSwiper>(find.byType(CardSwiper))
          .controller!
          .swipeRight();
      await tester.pumpAndSettle();
      expect(swiped, ['2', '1']);
      tester
          .widget<CardSwiper>(find.byType(CardSwiper))
          .controller!
          .swipeLeft();
      await tester.pumpAndSettle();
      expect(find.text('No people to discover yet'), findsOneWidget);
      await tester.tap(find.text('✨ Refresh Feed'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      tester
          .widget<CardSwiper>(find.byType(CardSwiper))
          .controller!
          .swipeLeft();
      await tester.pumpAndSettle();
      expect(swiped.last, '2');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Fetch failure is not reported as an empty feed; single card works',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoverView(
            loadProfiles: () async {
              if (attempts++ == 0) throw Exception('offline');
              return [
                {
                  'id': 'single',
                  'first_name': 'Single',
                  'avatar_url': 'https://example.com/single.jpg',
                },
              ];
            },
            onInteraction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load Discover. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CardSwiper>(find.byType(CardSwiper))
            .numberOfCardsDisplayed,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
