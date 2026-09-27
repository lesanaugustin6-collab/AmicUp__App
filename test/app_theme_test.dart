import 'package:amicup_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('Shared surfaces stay neutral and selection uses brand violet', () {
    final theme = AppTheme.light;
    expect(theme.colorScheme.primary, AppTheme.violet);
    expect(theme.colorScheme.secondary, AppTheme.violet);
    expect(theme.scaffoldBackgroundColor, AppTheme.canvas);
    expect(theme.colorScheme.surfaceContainer, AppTheme.surfaceMuted);
    expect(theme.colorScheme.primaryContainer, AppTheme.primarySoft);
    expect(theme.colorScheme.surfaceTint, Colors.transparent);
  });

  test('Brand and supporting text meet normal text contrast', () {
    for (final background in [
      AppTheme.surface,
      AppTheme.canvas,
      AppTheme.surfaceMuted,
      AppTheme.primarySoft,
    ]) {
      expect(contrast(AppTheme.muted, background), greaterThanOrEqualTo(4.5));
      expect(contrast(AppTheme.violet, background), greaterThanOrEqualTo(4.5));
    }
    expect(contrast(Colors.white, AppTheme.violet), greaterThanOrEqualTo(4.5));
    expect(
      contrast(AppTheme.onDarkAccent, AppTheme.darkSurface),
      greaterThanOrEqualTo(4.5),
    );
  });
}
