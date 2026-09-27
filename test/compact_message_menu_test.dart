import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/theme/appearance_controller.dart';
import 'package:amicup_app/widgets/compact_message_menu.dart';
import 'package:amicup_app/widgets/reply_message_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Separate emoji strip, selected message, and vertical actions', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ReplyMessageText(
                  '↩ A very long original message with more words than fit in one line on this screen\nMy answer',
                  onQuoteTap: () => tapped = true,
                ),
                TextButton(
                  onPressed: () => showCompactMessageMenu(
                    context,
                    ownMessage: true,
                    preview: 'Selected message',
                    anchor: const Rect.fromLTRB(40, 100, 220, 160),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final quote = find.textContaining('A very long original');
    expect(tester.widget<Text>(quote).overflow, TextOverflow.ellipsis);
    expect(tester.widget<Text>(quote).maxLines, 1);
    await tester.tap(quote);
    expect(tapped, isTrue);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('❤️')).dy,
      lessThan(tester.getTopLeft(find.text('Selected message')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Selected message')).dy,
      lessThan(tester.getTopLeft(find.text('Reply')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Reply')).dy,
      lessThan(tester.getTopLeft(find.text('Forward')).dy),
    );
    expect(find.byTooltip('More reactions'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  });
  for (final accent in AppAccent.values) {
    for (final brightness in Brightness.values) {
      testWidgets('Compact menu and quote fit $accent $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? action;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(accent: accent, brightness: brightness),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    const ReplyMessageText('↩ Coffee tomorrow?\nYes, at six!'),
                    TextButton(
                      onPressed: () async {
                        action = await showCompactMessageMenu(
                          context,
                          ownMessage: false,
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('Coffee tomorrow?'), findsOneWidget);
        expect(find.text('Yes, at six!'), findsOneWidget);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Report'), findsOneWidget);
        expect(find.text('Delete'), findsNothing);
        await tester.tap(find.text('Reply'));
        await tester.pumpAndSettle();
        expect(action, 'reply');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
