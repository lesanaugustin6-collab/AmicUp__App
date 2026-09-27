import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/views/main_navigation_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Highlight slides between tabs without delaying selection', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: AmicUpNavigationBar(
              currentIndex: selected,
              isDark: selected == 2,
              onTap: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    final highlight = find.byType(IgnorePointer).last;
    final start = tester.getTopLeft(highlight).dx;
    await tester.tap(find.bySemanticsLabel('Profile'));
    await tester.pump();
    expect(selected, 4);
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getTopLeft(highlight).dx;
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(highlight).dx;
    expect(middle, greaterThan(start));
    expect(end, greaterThan(middle));
    await tester.tap(find.descendant(
      of: find.byType(AmicUpNavigationBar),
      matching: find.byType(InkWell),
    ).at(2));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced motion disables navigation animation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            bottomNavigationBar: AmicUpNavigationBar(
              currentIndex: 0,
              isDark: false,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<AnimatedPositionedDirectional>(
            find.byType(AnimatedPositionedDirectional),
          )
          .duration,
      Duration.zero,
    );
  });
}
