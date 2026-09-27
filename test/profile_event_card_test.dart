import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/views/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Profile event is full-width with a 21:9 photo and date below', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ProfileEventCard(
                event: const {
                  'title': 'A very long event name that must not overflow',
                  'category': 'Meetup',
                  'location_name': 'A long location name in Chișinău',
                  'start_time': '2026-09-21T12:00:00',
                },
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(image.aspectRatio, 21 / 9);
    expect(find.textContaining('Sep 21'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AspectRatio),
        matching: find.textContaining('Sep 21'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
