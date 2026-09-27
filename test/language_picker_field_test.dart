import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/widgets/language_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('Languages can be edited in $brightness', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      List<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: LanguagePickerField(
                selectedLanguages: const ['Romanian', 'English'],
                onChanged: (languages) => result = languages,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Romanian, English'), findsOneWidget);
      await tester.tap(find.text('Romanian, English'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'French');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'French'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done (3)'));
      await tester.pumpAndSettle();

      expect(result, ['Romanian', 'English', 'French']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Closing the picker discards changes', (tester) async {
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: LanguagePickerField(
            selectedLanguages: const ['Romanian'],
            onChanged: (languages) => result = languages,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Romanian'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
