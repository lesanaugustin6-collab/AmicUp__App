import 'package:amicup_app/widgets/message_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Single tap toggles sent time; double tap only reacts', (
    tester,
  ) async {
    var hearts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInteraction(
            sentAt: DateTime(2026, 9, 10, 14, 30),
            forwarded: true,
            onOptions: () {},
            onReply: () {},
            onHeart: () => hearts++,
            child: const Text('Message'),
          ),
        ),
      ),
    );
    expect(find.text('Forwarded'), findsOneWidget);
    expect(find.textContaining('14:30'), findsNothing);
    await tester.tap(find.text('Message'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('14:30'), findsOneWidget);
    await tester.tap(find.text('Message'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('14:30'), findsNothing);
    await tester.tap(find.text('Message'));
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(find.text('Message'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(hearts, 1);
    expect(find.textContaining('14:30'), findsNothing);
  });
  testWidgets('Own messages reply only when swiped left', (tester) async {
    var replies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageInteraction(
              ownMessage: true,
              onOptions: () {},
              onHeart: () {},
              onReply: () => replies++,
              child: const SizedBox(
                width: 200,
                height: 80,
                child: Text('Mine'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.text('Mine'), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(replies, 0);
    await tester.drag(find.text('Mine'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(replies, 1);
  });
  testWidgets(
    'Hold, double tap, and threshold swipe trigger distinct actions',
    (tester) async {
      var options = 0;
      var hearts = 0;
      var replies = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MessageInteraction(
                onOptions: () => options++,
                onHeart: () => hearts++,
                onReply: () => replies++,
                child: const SizedBox(
                  width: 200,
                  height: 80,
                  child: Text('Message'),
                ),
              ),
            ),
          ),
        ),
      );
      final target = find.text('Message');
      await tester.longPress(target);
      await tester.pumpAndSettle();
      expect(options, 1);
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(hearts, 1);
      await tester.drag(target, const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(replies, 1);
      await tester.drag(target, const Offset(25, 0));
      await tester.pumpAndSettle();
      await tester.drag(target, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(replies, 1);
      expect(options, 1);
      expect(hearts, 1);
    },
  );

  testWidgets('Vertical scrolling does not reply', (tester) async {
    var replies = 0;
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              MessageInteraction(
                onOptions: () {},
                onHeart: () {},
                onReply: () => replies++,
                child: const SizedBox(height: 200, child: Text('Message')),
              ),
              const SizedBox(height: 1500),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(MessageInteraction), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(replies, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
