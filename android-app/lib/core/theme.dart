import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Brand colours ────────────────────────────────────────────────────────────
const Color kPurple = Color(0xFFDBB8FF); // primary accent
const Color kPurpleDark = Color(0xFFA855F7); // icons, text on light bg
const Color kPurpleDeep = Color(0xFF7C3AED); // pressed / deep accent
const Color kSurface = Color(0xFFFFFFFF); // page background
const Color kCardBg = Color(0xFFF8F7FF); // card / input fill
const Color kBorder = Color(0xFFEDE9FE); // borders, dividers
const Color kTextPrimary = Color(0xFF1C1C2E); // headlines
const Color kTextSecondary = Color(0xFF71717A); // subtitles, timestamps

// ─── ZentraTheme ──────────────────────────────────────────────────────────────
class ZentraTheme {
  ZentraTheme._();

  static ThemeData get light {
    const fontFamily = 'Inter';

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: kPurple,
      onPrimary: kTextPrimary,
      primaryContainer: kCardBg,
      onPrimaryContainer: kPurpleDeep,
      secondary: kPurpleDark,
      onSecondary: Colors.white,
      secondaryContainer: kCardBg,
      onSecondaryContainer: kPurpleDeep,
      tertiary: kPurpleDeep,
      onTertiary: Colors.white,
      tertiaryContainer: kCardBg,
      onTertiaryContainer: kPurpleDeep,
      error: Color(0xFFDC2626),
      onError: Colors.white,
      errorContainer: Color(0xFFFEF2F2),
      onErrorContainer: Color(0xFFDC2626),
      surface: kSurface,
      onSurface: kTextPrimary,
      surfaceContainerHighest: kCardBg,
      onSurfaceVariant: kTextSecondary,
      outline: kBorder,
      outlineVariant: kBorder,
      shadow: Color(0xFF000000),
      inverseSurface: kTextPrimary,
      onInverseSurface: Colors.white,
      inversePrimary: kPurpleDeep,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: kSurface,
      fontFamily: fontFamily,

      // ── AppBar ──────────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: kSurface,
        foregroundColor: kTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: kBorder,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: kTextPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: kTextSecondary, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ── InputDecoration ─────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kCardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPurpleDark, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 14),
        hintStyle: const TextStyle(color: kTextSecondary, fontSize: 14),
        prefixIconColor: kTextSecondary,
      ),

      // ── FilledButton ────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kPurple,
          foregroundColor: kTextPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
          elevation: 0,
        ),
      ),

      // ── OutlinedButton ──────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kPurpleDeep,
          side: const BorderSide(color: kBorder, width: 1.5),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),

      // ── TextButton ──────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kPurpleDeep,
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ── ElevatedButton ──────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPurple,
          foregroundColor: kTextPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),

      // ── NavigationBar ───────────────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kSurface,
        indicatorColor: kPurple.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kPurpleDeep,
            );
          }
          return const TextStyle(
            fontFamily: fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: kTextSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: kPurpleDeep, size: 22);
          }
          return const IconThemeData(color: kTextSecondary, size: 22);
        }),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),

      // ── Slider ──────────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: kPurpleDark,
        thumbColor: kPurpleDeep,
        overlayColor: kPurple.withOpacity(0.18),
        inactiveTrackColor: kBorder,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        trackHeight: 4,
      ),

      // ── ChoiceChip / FilterChip ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: kCardBg,
        selectedColor: kPurple.withOpacity(0.18),
        secondarySelectedColor: kPurple.withOpacity(0.18),
        labelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: kTextPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: kPurpleDeep,
        ),
        side: const BorderSide(color: kBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: kPurpleDeep,
        showCheckmark: false,
      ),

      // ── Card ─────────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: kCardBg,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: kBorder),
        ),
      ),

      // ── Divider ──────────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: kBorder,
        thickness: 1,
        space: 1,
      ),

      // ── Text ─────────────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: kTextPrimary, letterSpacing: -1),
        displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: kTextPrimary, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: kTextPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kTextPrimary, letterSpacing: -0.3),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kTextPrimary),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextPrimary),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextPrimary),
        bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kTextPrimary, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: kTextPrimary, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: kTextSecondary, height: 1.4),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kTextPrimary),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kTextSecondary),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: kTextSecondary, letterSpacing: 0.4),
      ),
    );
  }
}