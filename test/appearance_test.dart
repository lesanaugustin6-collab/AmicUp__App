import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/theme/appearance_controller.dart';
import 'package:amicup_app/views/appearance_view.dart';
import 'package:amicup_app/views/onboarding/onboarding_flow_view.dart';
import 'package:amicup_app/widgets/animated_tab_selector.dart';
import 'package:amicup_app/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test('Dark surfaces use a clear charcoal hierarchy', () {
    for (final accent in AppAccent.values) {
      final scheme = AppTheme.build(
        accent: accent,
        brightness: Brightness.dark,
      ).colorScheme;
      expect(
        scheme.surfaceContainerLow.computeLuminance(),
        lessThan(scheme.surface.computeLuminance()),
      );
      expect(
        scheme.surface.computeLuminance(),
        lessThan(scheme.surfaceContainer.computeLuminance()),
      );
      expect(scheme.surfaceContainer.computeLuminance(), lessThan(0.035));
    }
  });
  for (final accent in AppAccent.values) {
    for (final brightness in Brightness.values) {
      test('${accent.name} ${brightness.name} readable semantic colors', () {
        final theme = AppTheme.build(accent: accent, brightness: brightness);
        final c = theme.colorScheme;
        expect(
          contrast(AppColors(c).incomingBubble, c.onSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(c.brightness, brightness);
        expect(contrast(c.primary, c.onPrimary), greaterThanOrEqualTo(4.5));
        expect(contrast(c.surface, c.onSurface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.surface, c.onSurfaceVariant),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(c.surface, c.onPrimaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(c.primaryContainer, c.onPrimaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      });
      testWidgets('${accent.name} ${brightness.name} forms and selectors fit', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(accent: accent, brightness: brightness),
            home: const OnboardingFlowView(),
          ),
        );
        await tester.pumpAndSettle();
        final page = tester.widget<PageView>(find.byType(PageView));
        page.controller!.jumpToPage(9);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(accent: accent, brightness: brightness),
            home: Scaffold(
              body: Column(
                children: [
                  AnimatedTabSelector(
                    labels: const ['Groups', 'Direct'],
                    icons: const [
                      Icons.groups_outlined,
                      Icons.chat_bubble_outline,
                    ],
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                  const ChatBubble(text: 'Hello', isCurrentUser: true),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final hello = tester.widget<Text>(find.text('Hello'));
        expect(
          hello.style!.color,
          AppTheme.build(
            accent: accent,
            brightness: brightness,
          ).colorScheme.onPrimary,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('Appearance survives restart and rapid changes', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppearanceController();
    await settings.load();
    final a = settings.setAppearance(accent: AppAccent.white);
    final b = settings.setAppearance(mode: ThemeMode.dark);
    await Future.wait([a, b]);
    final restored = AppearanceController();
    await restored.load();
    expect(restored.accent, AppAccent.white);
    expect(restored.mode, ThemeMode.dark);
    settings.dispose();
    restored.dispose();
  });
  testWidgets('Appearance exposes every theme and both modes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AppearanceView()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Use device setting'), findsOneWidget);
    for (final accent in AppAccent.values) {
      await tester.scrollUntilVisible(find.text(accent.label), 100);
      expect(find.text(accent.label), findsOneWidget);
    }
  });
}
