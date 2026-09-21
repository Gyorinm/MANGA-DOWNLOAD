import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// هوية بصرية واحدة للتطبيق كله.
///
/// المنطق: التطبيق يُقرأ فيه لا يُتصفّح، فالخلفية داكنة هادئة تُبرز الصفحات
/// ولا تنافسها، ولون واحد دافئ يحمل كل الإشارات التفاعلية.
class AppTheme {
  const AppTheme._();

  static const ink = Color(0xFF0E1015);
  static const surface = Color(0xFF171A22);
  static const surfaceHigh = Color(0xFF212633);
  static const line = Color(0xFF2C3242);
  static const accent = Color(0xFFE0A33C);
  static const textPrimary = Color(0xFFF1EDE6);
  static const textMuted = Color(0xFF9AA1B1);

  static ThemeData build() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = GoogleFonts.tajawalTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: ink,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: ink,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
        error: Color(0xFFD9695C),
      ),
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.7),
        bodySmall: textTheme.bodySmall?.copyWith(color: textMuted, height: 1.6),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: line,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
