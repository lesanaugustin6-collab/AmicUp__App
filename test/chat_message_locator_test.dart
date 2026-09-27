import 'package:amicup_app/widgets/chat_message_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reverse in [true, false]) {
    testWidgets('Find lazy original and clear highlight, reverse=$reverse', (
      tester,
    ) async {
      final locator = ChatMessageLocator();
      final scroll = ScrollController();
      locator.messages = List.generate(
        40,
        (i) => {'id': '$i', 'content': 'same'},
      );
      expect(locator.replyTarget('↩ same\nReply', null), isNull);
      expect(locator.replyTarget('↩ same\nReply', '30'), '30');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              controller: scroll,
              reverse: reverse,
              itemCount: 40,
              itemBuilder: (context, index) => SizedBox(
                key: locator.keyFor('$index'),
                height: 100,
                child: Text('$index'),
              ),
            ),
          ),
        ),
      );
      bool? revealed;
      locator.reveal('30', scroll).then((value) => revealed = value);
      for (var i = 0; i < 40 && revealed == null; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(revealed, isTrue);
      expect(locator.highlighted.value, '30');
      await tester.pump(const Duration(seconds: 1));
      expect(locator.highlighted.value, isNull);
      await tester.pumpWidget(const SizedBox());
      locator.dispose();
      scroll.dispose();
    });
  }
}
