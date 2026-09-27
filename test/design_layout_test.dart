import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/views/onboarding/onboarding_flow_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 430.0]) {
    testWidgets('Signup fits a $width phone with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const OnboardingFlowView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
      for (var step = 1; step < 10; step++) {
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .jumpToPage(step);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Onboarding step ${step + 1} at width $width',
        );
      }
    });
  }
  testWidgets('Login fields and password visibility remain usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoginView()),
    );
    await tester.pumpAndSettle();
    final password = find.byType(TextFormField).last;
    await tester.enterText(password, 'test-password');
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
