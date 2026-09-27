import 'package:amicup_app/widgets/animated_tab_selector.dart';
import 'package:amicup_app/theme/amicup_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main tab motion preserves the state of hidden screens', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: AmicUpTabStack(
              index: selected,
              children: const [
                _CounterTab(),
                Center(child: Text('Other tab')),
              ],
            ),
            bottomNavigationBar: TextButton(
              onPressed: () => setState(() => selected = selected == 0 ? 1 : 0),
              child: const Text('Switch'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Count: 1'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(find.text('Other tab'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final labels in [
    ['Groups', 'Direct'],
    ['Explore', 'My events'],
  ]) {
    testWidgets('${labels.first} selector slides and preserves selection', (
      tester,
    ) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: AnimatedTabSelector(
                    labels: labels,
                    icons: const [
                      Icons.groups_outlined,
                      Icons.explore_outlined,
                    ],
                    selectedIndex: selected,
                    onSelected: (index) => setState(() => selected = index),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final pill = find.byType(FractionallySizedBox);
      final start = tester.getTopLeft(pill).dx;
      await tester.tap(find.text(labels.last));
      await tester.pump();
      expect(selected, 1);
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getTopLeft(pill).dx;
      await tester.pumpAndSettle();
      expect(middle, greaterThan(start));
      expect(tester.getTopLeft(pill).dx, greaterThan(middle));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Selector supports enlarged text and reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: AnimatedTabSelector(
                  labels: const ['Explore', 'My events'],
                  icons: const [
                    Icons.explore_outlined,
                    Icons.event_note_outlined,
                  ],
                  selectedIndex: 1,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).duration,
      Duration.zero,
    );
    expect(tester.takeException(), isNull);
  });
}

class _CounterTab extends StatefulWidget {
  const _CounterTab();

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Count: $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: const Text('Increment'),
        ),
      ],
    ),
  );
}
