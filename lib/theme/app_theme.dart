import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'appearance_controller.dart';
import 'amicup_motion.dart';

/// Shared visual language. No navigation or application state belongs here.
abstract final class AppTheme {
  static const violet = Color(0xFF6040D8);
  static const violetStrong = Color(0xFF4930AC);
  static const ink = Color(0xFF1B1D27);
  static const muted = Color(0xFF646875);
  static const canvas = Color(0xFFF6F7F9);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF0F1F4);
  static const primarySoft = Color(0xFFEEE9FC);
  static const line = Color(0xFFDADDE5);
  static const darkSurface = Color(0xFF0F1114);
  static const onDarkAccent = Color(0xFFC7BAFF);
  static const coverStart = Color(0xFF8066DC);
  static const coverEnd = Color(0xFF4930AC);

  static AppColors of(BuildContext context) =>
      AppColors(Theme.of(context).colorScheme);
  static BoxDecoration chatBackgroundDecoration(BuildContext context) {
    final colors = of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, 0.48, 1],
        colors: [
          Color.lerp(colors.canvas, colors.violet, dark ? 0.17 : 0.08)!,
          colors.canvas,
          colors.canvas,
        ],
      ),
    );
  }

  static BoxDecoration chatBubbleDecoration(
    BuildContext context, {
    required bool own,
  }) {
    final colors = of(context);
    return BoxDecoration(
      gradient: own
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(colors.violet, colors.surface, 0.12)!,
                colors.violet,
              ],
            )
          : null,
      color: own ? null : colors.incomingBubble,
      border: Border.all(
        color: own
            ? colors.onAccent.withValues(alpha: 0.12)
            : colors.violet.withValues(alpha: 0.24),
      ),
      borderRadius: BorderRadius.circular(24),
    );
  }

  static ThemeData get light => build();

  static ThemeData build({
    AppAccent accent = AppAccent.violet,
    Brightness brightness = Brightness.light,
  }) {
    final dark = brightness == Brightness.dark;
    final seed = switch (accent) {
      AppAccent.violet => const Color(0xFF6040D8),
      AppAccent.indigo => const Color(0xFF3F51B5),
      AppAccent.lavender => const Color(0xFFB8A0EA),
      AppAccent.graphite => const Color(0xFF4B4E57),
      AppAccent.white => const Color(0xFFFFFFFF),
    };
    final violet = seed;
    final onAccent = (accent == AppAccent.lavender || accent == AppAccent.white)
        ? const Color(0xFF24212E)
        : Colors.white;
    final violetStrong = dark
        ? (accent == AppAccent.graphite
              ? const Color(0xFFCDD0D8)
              : Color.lerp(seed, Colors.white, 0.55)!)
        : switch (accent) {
            AppAccent.violet => const Color(0xFF4930AC),
            AppAccent.indigo => const Color(0xFF303F90),
            AppAccent.lavender => const Color(0xFF654399),
            AppAccent.graphite => const Color(0xFF40434B),
            AppAccent.white => const Color(0xFF40434B),
          };
    final ink = dark ? const Color(0xFFF1F2F5) : AppTheme.ink;
    final muted = dark ? const Color(0xFFB8BBC4) : AppTheme.muted;
    final canvas = dark ? const Color(0xFF050608) : AppTheme.canvas;
    final surface = dark ? const Color(0xFF0F1114) : Colors.white;
    final surfaceMuted = dark ? const Color(0xFF191B20) : AppTheme.surfaceMuted;
    final primarySoft = accent == AppAccent.violet && !dark
        ? AppTheme.primarySoft
        : dark
        ? Color.lerp(surface, seed, 0.18)!
        : Color.lerp(Colors.white, seed, 0.10)!;
    final line = dark ? const Color(0xFF2B2E35) : AppTheme.line;
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: brightness,
      primary: violet,
      onPrimary: onAccent,
      primaryContainer: primarySoft,
      onPrimaryContainer: violetStrong,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      outlineVariant: line,
      outline: muted,
      secondary: violet,
      onSecondary: onAccent,
      secondaryContainer: primarySoft,
      onSecondaryContainer: violetStrong,
      surfaceContainerLowest: surface,
      surfaceContainerLow: canvas,
      surfaceContainer: surfaceMuted,
      surfaceContainerHigh: surfaceMuted,
      surfaceContainerHighest: surfaceMuted,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            height: 1.15,
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            height: 1.2,
            color: ink,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: ink,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: ink,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
          bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AmicUpPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: AmicUpPageTransitionsBuilder(),
          TargetPlatform.macOS: AmicUpPageTransitionsBuilder(),
          TargetPlatform.linux: AmicUpPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkRipple.splashFactory,
      textTheme: text,
      primaryColor: violet,
      iconTheme: IconThemeData(color: ink),
      listTileTheme: ListTileThemeData(
        selectedColor: violetStrong,
        selectedTileColor: primarySoft,
        iconColor: muted,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: violetStrong,
        thumbColor: violetStrong,
        inactiveTrackColor: line,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? violetStrong : muted,
        ),
      ),
      scaffoldBackgroundColor: canvas,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        hintStyle: TextStyle(color: muted, fontSize: 15),
        labelStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: violetStrong, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(48, 48),
          shape: buttonShape.copyWith(
            side: BorderSide(
              color: accent == AppAccent.white ? line : Colors.transparent,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: onAccent,
          elevation: 0,
          minimumSize: Size(48, 48),
          shape: buttonShape.copyWith(
            side: BorderSide(
              color: accent == AppAccent.white ? line : Colors.transparent,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violetStrong,
          side: BorderSide(color: line),
          minimumSize: Size(48, 48),
          shape: buttonShape,
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: violetStrong,
          minimumSize: Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primarySoft,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: violetStrong,
        unselectedLabelColor: muted,
        indicatorColor: violetStrong,
        dividerColor: line,
        labelStyle: text.labelLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: canvas, fontSize: 14, height: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: violetStrong,
        linearTrackColor: surfaceMuted,
      ),
    );
  }
}

/// Read colors through the widget context so theme changes update every screen.
class AppColors {
  const AppColors(this.scheme);
  final ColorScheme scheme;
  Color get violet => scheme.primary;
  Color get onAccent => scheme.onPrimary;
  Color get violetStrong => scheme.onPrimaryContainer;
  Color get ink => scheme.onSurface;
  Color get muted => scheme.onSurfaceVariant;
  Color get canvas => scheme.surfaceContainerLow;
  Color get surface => scheme.surface;
  Color get surfaceMuted => scheme.surfaceContainer;
  /// Soft accent tint with a readable surface foreground in both modes.
  Color get incomingBubble => Color.lerp(
    surfaceMuted,
    violet,
    scheme.brightness == Brightness.dark ? 0.28 : 0.12,
  )!;
  Color get primarySoft => scheme.primaryContainer;
  Color get line => scheme.outlineVariant;
  Color get darkSurface => AppTheme.darkSurface;
  Color get onDarkAccent => Color.lerp(scheme.primary, Colors.white, 0.65)!;
  Color get coverStart =>
      Color.lerp(scheme.primary, AppTheme.darkSurface, 0.2)!;
  Color get coverEnd => Color.lerp(scheme.primary, AppTheme.darkSurface, 0.6)!;
}
