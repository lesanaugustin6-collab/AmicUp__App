import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAccent { violet, indigo, lavender, graphite, white }

extension AccentLabel on AppAccent {
  String get label => switch (this) {
    AppAccent.violet => 'AmicUp purple',
    AppAccent.indigo => 'Indigo',
    AppAccent.lavender => 'Lavender',
    AppAccent.graphite => 'Dark gray',
    AppAccent.white => 'White',
  };
}

/// Device preferences work before login, independently of account settings.
class AppearanceController extends ChangeNotifier {
  static final instance = AppearanceController();
  AppAccent accent = AppAccent.violet;
  ThemeMode mode = ThemeMode.system;
  String? error;
  Future<void> _pending = Future.value();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final color = prefs.getString('appearance.accent');
      final theme = prefs.getString('appearance.mode');
      accent =
          AppAccent.values.where((a) => a.name == color).firstOrNull ??
          AppAccent.violet;
      mode =
          ThemeMode.values.where((m) => m.name == theme).firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      error = 'Could not restore appearance preferences.';
    }
    notifyListeners();
  }

  Future<void> setAppearance({AppAccent? accent, ThemeMode? mode}) {
    this.accent = accent ?? this.accent;
    this.mode = mode ?? this.mode;
    error = null;
    notifyListeners();
    final color = this.accent.name;
    final theme = this.mode.name;
    _pending = _pending.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final a = await prefs.setString('appearance.accent', color);
        final b = await prefs.setString('appearance.mode', theme);
        if (!a || !b) throw StateError('Storage unavailable');
      } catch (_) {
        error = 'Appearance changed, but could not be saved on this device.';
      }
      notifyListeners();
    });
    return _pending;
  }
}
