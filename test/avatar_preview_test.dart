import 'package:amicup_app/widgets/avatar_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Avatar preview preserves circular crop and closes', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(onPressed: () => showAvatarPreview(context,
        const AssetImage('assets/amicup_logo_transparent.png')), child: const Text('Photo')),
    ))));
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(find.byType(ClipOval), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
