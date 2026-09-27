import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/widgets/country_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Country can be searched and changed in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: CountryPickerField(
                country: 'Romania',
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Romania'), findsOneWidget);
      await tester.tap(find.text('Romania'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mold');
      await tester.pumpAndSettle();
      expect(find.text('Moldova'), findsOneWidget);
      await tester.tap(find.text('Moldova'));
      await tester.pumpAndSettle();
      expect(selected, 'Moldova');
      expect(tester.takeException(), isNull);
    });
  }
}
