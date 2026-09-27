import 'dart:io';
import 'dart:ui' as ui;

import 'package:amicup_app/main.dart';
import 'package:amicup_app/theme/app_theme.dart';
import 'package:amicup_app/theme/appearance_controller.dart';
import 'package:amicup_app/views/appearance_view.dart';
import 'package:amicup_app/views/onboarding/onboarding_flow_view.dart';
import 'package:amicup_app/views/main_navigation_view.dart';
import 'package:amicup_app/widgets/animated_tab_selector.dart';
import 'package:amicup_app/widgets/chat_bubble.dart';
import 'package:amicup_app/widgets/compact_message_menu.dart';
import 'package:amicup_app/widgets/message_interaction.dart';
import 'package:amicup_app/widgets/inbox_tiles.dart';
import 'package:amicup_app/views/activity_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Optional local visual review; output paths and fonts are provided by the
// developer, never bundled in or accessed by the production app.
const previewDirectory = String.fromEnvironment('DESIGN_PREVIEW_DIR');
const fontDirectory = String.fromEnvironment('DESIGN_FONT_DIR');

void main() {
  test('Application entry point compiles with the new theme', () {
    expect(const AmicUpApp(), isA<StatefulWidget>());
  });

  testWidgets(
    'Capture real signup, gallery, and login layouts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final emojiFont = File('C:/Windows/Fonts/seguiemj.ttf');
        if (await emojiFont.exists()) {
          final loader = FontLoader('Segoe UI Emoji');
          loader.addFont(
            emojiFont.readAsBytes().then(
              (bytes) => ByteData.sublistView(bytes),
            ),
          );
          await loader.load();
        }
        // Widget tests substitute Ahem for system text. Replace that test font
        // with Roboto so the captured layouts have readable, realistic glyphs.
        for (final family in ['Ahem', 'Roboto']) {
          final loader = FontLoader(family);
          for (final file in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
            loader.addFont(
              File(
                '$fontDirectory/$file',
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          }
          await loader.load();
        }
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          File(
            '$fontDirectory/materialicons-regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
        await icons.load();
      });
      final boundaryKey = GlobalKey();
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(previewDirectory).create(recursive: true);
          await File(
            '$previewDirectory/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      var previewTheme = AppTheme.light;
      Widget app(Widget screen) => RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: previewTheme.copyWith(
            appBarTheme: previewTheme.appBarTheme.copyWith(
              titleTextStyle: previewTheme.textTheme.titleLarge!.copyWith(
                fontFamily: 'Roboto',
              ),
            ),
            chipTheme: previewTheme.chipTheme.copyWith(
              labelStyle: previewTheme.chipTheme.labelStyle!.copyWith(
                fontFamily: 'Roboto',
              ),
            ),
            textTheme: previewTheme.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: previewTheme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: previewTheme.elevatedButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: previewTheme.filledButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: previewTheme.outlinedButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: previewTheme.textButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            inputDecorationTheme: previewTheme.inputDecorationTheme.copyWith(
              labelStyle: TextStyle(
                fontFamily: 'Roboto',
                color: previewTheme.colorScheme.onSurfaceVariant,
              ),
              hintStyle: TextStyle(
                fontFamily: 'Roboto',
                color: previewTheme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          home: screen,
        ),
      );
      await tester.pumpWidget(app(const OnboardingFlowView()));
      await capture('signup');
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(9);
      await capture('gallery');
      await tester.pumpWidget(app(const LoginView()));
      await capture('login');
      // Actual shared widgets, with sample content; not an authenticated feed.
      Widget socialPreview() => Scaffold(
        appBar: AppBar(title: const Text('AmicUp')),
        bottomNavigationBar: AmicUpNavigationBar(
          currentIndex: 3,
          isDark: false,
          onTap: (_) {},
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Messages',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            AnimatedTabSelector(
              labels: const ['Groups', 'Direct'],
              icons: const [Icons.groups_outlined, Icons.chat_bubble_outline],
              selectedIndex: 1,
              onSelected: (_) {},
            ),
            const SizedBox(height: 20),
            const ChatBubble(text: 'Coffee after work?'),
            const ChatBubble(
              text: 'Yes! See you at 6.',
              isCurrentUser: true,
              isRead: true,
            ),
            const SizedBox(height: 32),
            const Text(
              'Events',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            AnimatedTabSelector(
              labels: const ['Explore', 'My events'],
              icons: const [Icons.explore_outlined, Icons.event_note_outlined],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: true,
                  selectedColor: previewTheme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: previewTheme.colorScheme.onPrimary,
                  ),
                  checkmarkColor: previewTheme.colorScheme.onPrimary,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('Sports'),
                  selected: false,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('Hangout'),
                  selected: false,
                  onSelected: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create event'),
            ),
            const SizedBox(height: 20),
            Text(
              'Style preview · Sample conversation',
              style: TextStyle(
                fontSize: 12,
                color: previewTheme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(app(socialPreview()));
      await capture('social-style');
      for (final accent in AppAccent.values) {
        for (final brightness in Brightness.values) {
          previewTheme = AppTheme.build(accent: accent, brightness: brightness);
          await tester.pumpWidget(app(socialPreview()));
          await capture('theme-${accent.name}-${brightness.name}');
        }
      }
      previewTheme = AppTheme.build(brightness: Brightness.dark);
      await tester.pumpWidget(app(const LoginView()));
      await capture('login-dark');
      AppearanceController.instance.mode = ThemeMode.dark;
      await tester.pumpWidget(app(const AppearanceView()));
      await capture('appearance-dark');
      for (final brightness in Brightness.values) {
        previewTheme = AppTheme.build(brightness: brightness);
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Messages')),
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showCompactMessageMenu(
                      context,
                      ownMessage: true,
                      preview: 'See you at the gym tomorrow?',
                      selectedReaction: '❤️',
                      anchor: const Rect.fromLTRB(100, 260, 360, 310),
                    ),
                    child: const Text('Open message actions'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open message actions'));
        await capture('message-menu-${brightness.name}');
        await tester.tap(find.text('Reply'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Messages')),
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topRight,
                  child: MessageInteraction(
                    ownMessage: true,
                    forwarded: true,
                    sentAt: DateTime(2026, 9, 10, 14, 30),
                    onOptions: () {},
                    onHeart: () {},
                    onReply: () {},
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: previewTheme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'See you at the gym tomorrow?',
                        style: TextStyle(
                          color: previewTheme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('See you at the gym tomorrow?'));
        await tester.pump(const Duration(milliseconds: 350));
        await capture('forwarded-message-${brightness.name}');
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Messages')),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedTabSelector(
                      labels: const ['Groups', 'Direct'],
                      icons: const [Icons.groups_outlined, Icons.chat_bubble_outline],
                      selectedIndex: 1,
                      onSelected: (_) {},
                    ),
                  ),
                  ActivityInboxTile(onTap: () {}),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        DirectInboxTile(
                          conversation: {
                            'first_name': 'Alex',
                            'unread_count': 3,
                            'last_message': 'Are we still meeting at 6?',
                            'last_message_at': DateTime.now().toIso8601String(),
                          },
                          onTap: () {},
                          onReview: () {},
                        ),
                        DirectInboxTile(
                          conversation: {
                            'first_name': 'Daria',
                            'unread_count': 12,
                            'last_message': 'Forwarded\n[IMAGE]: example',
                            'last_message_at': DateTime.now().toIso8601String(),
                          },
                          onTap: () {},
                          onReview: () {},
                        ),
                        DirectInboxTile(
                          conversation: {
                            'first_name': 'Andrei',
                            'unread_count': 0,
                            'last_message': 'See you there!',
                            'last_message_at': DateTime.now()
                                .subtract(const Duration(days: 1))
                                .toIso8601String(),
                          },
                          onTap: () {},
                          onReview: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await capture('inbox-${brightness.name}');
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Activity')),
              body: ListView(
                children: [
                  ActivityItemTile(
                    item: {
                      'first_name': 'Alex',
                      'kind': 'match',
                      'occurred_at': DateTime.now().toIso8601String(),
                    },
                    onTap: () {},
                  ),
                  ActivityItemTile(
                    item: {
                      'first_name': 'Daria',
                      'kind': 'like',
                      'occurred_at': DateTime.now().toIso8601String(),
                    },
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await capture('activity-${brightness.name}');
      }
      debugDisableShadows = true;
    },
    skip: previewDirectory.isEmpty || fontDirectory.isEmpty,
  );
}
