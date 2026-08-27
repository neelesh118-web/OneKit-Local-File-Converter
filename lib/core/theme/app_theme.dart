import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// OneKit is deliberately monochrome. Everything is expressed as a position on
/// a black-to-white ramp so the two themes are exact inversions of each other:
/// dark mode paints white buttons on black, light mode black buttons on white.
class Mono {
  Mono._();

  static const black = Color(0xFF000000);
  static const near = Color(0xFF0A0A0A);
  static const ink = Color(0xFF121212);
  static const slate = Color(0xFF1C1C1E);
  static const graphite = Color(0xFF2C2C2E);
  static const steel = Color(0xFF48484A);
  static const ash = Color(0xFF8E8E93);
  static const silver = Color(0xFFC7C7CC);
  static const mist = Color(0xFFE5E5EA);
  static const cloud = Color(0xFFF2F2F7);
  static const white = Color(0xFFFFFFFF);
}

/// Semantic tokens resolved per brightness. Widgets read these instead of
/// branching on `Theme.of(context).brightness` everywhere.
class OneKitTokens extends ThemeExtension<OneKitTokens> {
  const OneKitTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.starColor,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textFaint;

  /// The button fill: white in dark mode, black in light mode.
  final Color accent;

  /// Text/icon colour drawn on top of [accent].
  final Color onAccent;

  final Color starColor;
  final bool isDark;

  static const dark = OneKitTokens(
    background: Mono.black,
    surface: Mono.ink,
    surfaceRaised: Mono.slate,
    border: Mono.graphite,
    textPrimary: Mono.white,
    textSecondary: Mono.silver,
    textFaint: Mono.ash,
    accent: Mono.white,
    onAccent: Mono.black,
    starColor: Mono.white,
    isDark: true,
  );

  static const light = OneKitTokens(
    background: Mono.white,
    surface: Mono.cloud,
    surfaceRaised: Mono.white,
    border: Mono.mist,
    textPrimary: Mono.black,
    textSecondary: Mono.steel,
    textFaint: Mono.ash,
    accent: Mono.black,
    onAccent: Mono.white,
    starColor: Mono.black,
    isDark: false,
  );

  @override
  ThemeExtension<OneKitTokens> copyWith() => this;

  @override
  ThemeExtension<OneKitTokens> lerp(ThemeExtension<OneKitTokens>? other, double t) {
    if (other is! OneKitTokens) return this;
    return t < 0.5 ? this : other;
  }
}

extension TokenLookup on BuildContext {
  OneKitTokens get tokens => Theme.of(this).extension<OneKitTokens>()!;
}

class AppTheme {
  AppTheme._();

  static const double radius = 18;
  static const double radiusSmall = 12;
  static const double gutter = 20;

  /// Built once. These were reconstructed on every settings change, and each
  /// new ThemeData identity invalidates every `Theme.of` dependent in the tree.
  static final ThemeData darkTheme = _build(OneKitTokens.dark);
  static final ThemeData lightTheme = _build(OneKitTokens.light);

  static ThemeData dark() => darkTheme;
  static ThemeData light() => lightTheme;

  static ThemeData _build(OneKitTokens t) {
    final scheme = ColorScheme(
      brightness: t.isDark ? Brightness.dark : Brightness.light,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.textSecondary,
      onSecondary: t.background,
      surface: t.surface,
      onSurface: t.textPrimary,
      error: t.textPrimary,
      onError: t.background,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [t],
      textTheme: _text(base.textTheme, t),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: t.textPrimary,
        titleTextStyle: TextStyle(
          color: t.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: t.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
              ),
      ),
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: t.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.border,
          disabledForegroundColor: t.textFaint,
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          minimumSize: const Size(0, 54),
          side: BorderSide(color: t.border, width: 1.4),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall + 2)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.textPrimary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: t.textPrimary, minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        hintStyle: TextStyle(color: t.textFaint, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 2),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 2),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 2),
          borderSide: BorderSide(color: t.accent, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.accent,
        side: BorderSide(color: t.border),
        labelStyle: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: t.onAccent, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.isDark ? Mono.graphite : Mono.mist,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: t.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? t.textPrimary : t.textFaint),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: t.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.accent,
        contentTextStyle: TextStyle(color: t.onAccent, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.border,
        circularTrackColor: t.border,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.surface,
        ),
        trackOutlineColor: WidgetStatePropertyAll(t.border),
      ),
    );
  }

  static TextTheme _text(TextTheme base, OneKitTokens t) {
    return base
        .apply(bodyColor: t.textPrimary, displayColor: t.textPrimary)
        .copyWith(
          displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.0, color: t.textPrimary),
          headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: t.textPrimary),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: t.textPrimary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.textPrimary),
          bodyLarge: TextStyle(fontSize: 15.5, height: 1.45, color: t.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: t.textSecondary),
          bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: t.textFaint),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.textPrimary),
        );
  }
}
