import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/appearance_controller.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: AppearanceController.instance,
    builder: (context, _) {
      final appearance = AppearanceController.instance;
      return Scaffold(
        appBar: AppBar(title: const Text('Appearance')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Display mode', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...ThemeMode.values.map(
              (mode) => ListTile(
                leading: Icon(switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }),
                title: Text(switch (mode) {
                  ThemeMode.system => 'Use device setting',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                selected: appearance.mode == mode,
                trailing: appearance.mode == mode
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => appearance.setAppearance(mode: mode),
              ),
            ),
            const SizedBox(height: 28),
            Text('Accent theme', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Changes colors throughout the app. Your logo keeps its original colors.',
            ),
            const SizedBox(height: 12),
            ...AppAccent.values.map(
              (accent) => ListTile(
                leading: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppTheme.build(accent: accent).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                ),
                title: Text(accent.label),
                selected: appearance.accent == accent,
                trailing: appearance.accent == accent
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => appearance.setAppearance(accent: accent),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your AmicUp',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('A preview of your selected colors.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Accent preview'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Saved on this device, including the login screen.'),
            if (appearance.error != null)
              Text(
                appearance.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    },
  );
}
