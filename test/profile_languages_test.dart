import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/views/profile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Profile does not repeat a country already in the location', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ProfileLocationAndLanguages(
            country: 'Moldova',
            location: 'Moldova, Chișinău',
            languages: [],
          ),
        ),
      ),
    );

    expect(find.text('Moldova, Chișinău'), findsOneWidget);
    expect(find.text('Moldova, Moldova, Chișinău'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Profile previews two languages and lists all in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: brightness),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(18),
              child: ProfileLocationAndLanguages(
                country: 'Moldova',
                location: 'Chișinău',
                languages: ['Romanian', 'English', 'French', 'German'],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Romanian, English'), findsOneWidget);
      expect(find.text('Moldova, Chișinău'), findsOneWidget);
      expect(find.text('French'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Languages'), findsOneWidget);
      for (final language in ['Romanian', 'English', 'French', 'German']) {
        expect(find.text(language), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close languages'));
      await tester.pumpAndSettle();
      expect(find.text('Languages'), findsNothing);
    });
  }
}
