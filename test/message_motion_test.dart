import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amicup_app/theme/amicup_motion.dart';

void main() {
  testWidgets('A new message enters and a deleted message collapses', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AmicUpMessageMotion(
                key: const ValueKey('message'),
                animateEntrance: true,
                visible: visible,
                ownMessage: true,
                child: const SizedBox(width: 120, height: 48),
              );
            },
          ),
        ),
      ),
    );

    final message = find.byKey(const ValueKey('message'));
    expect(tester.getSize(message).height, 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(message).height, 48);

    update(() => visible = false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getSize(message).height, 0);
  });
}
