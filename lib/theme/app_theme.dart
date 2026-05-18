import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  const AppColors._();

  static const navy = Color(0xFF082B67);
  static const electricBlue = Color(0xFF1258FF);
  static const skyTint = Color(0xFFEAF2FF);
  static const red = Color(0xFFE3223A);
  static const redDark = Color(0xFFC9152C);
  static const scaffold = Color(0xFFF6F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const slate = Color(0xFF5B667A);
  static const border = Color(0xFFE3EAF5);
}

class AppRadii {
  const AppRadii._();

  static const card = 24.0;
  static const field = 999.0;
  static const image = 22.0;
}

class AppSpacing {
  const AppSpacing._();

  static const page = 20.0;
  static const section = 16.0;
}

class AppShadows {
  const AppShadows._();

  static const softBlue = [
    BoxShadow(color: Color(0x1F1258FF), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static const navGlow = [
    BoxShadow(color: Color(0x241258FF), blurRadius: 28, offset: Offset(0, -8)),
  ];
}

class AppGradients {
  const AppGradients._();

  static const blueSurface = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const primaryAction = LinearGradient(
    colors: [AppColors.red, AppColors.redDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.electricBlue,
        primary: AppColors.navy,
        secondary: AppColors.electricBlue,
        tertiary: AppColors.red,
        error: AppColors.red,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.scaffold,
    );

    final textTheme = GoogleFonts.poppinsTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineLarge: textTheme.headlineLarge?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: AppColors.slate,
          height: 1.35,
          letterSpacing: 0,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          color: AppColors.slate,
          height: 1.3,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppColors.scaffold,
        foregroundColor: AppColors.navy,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.electricBlue.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        prefixIconColor: AppColors.electricBlue,
        labelStyle: const TextStyle(color: AppColors.slate),
        hintStyle: const TextStyle(color: AppColors.slate),
        border: _fieldBorder(AppColors.border),
        enabledBorder: _fieldBorder(AppColors.border),
        focusedBorder: _fieldBorder(AppColors.electricBlue, width: 1.6),
        errorBorder: _fieldBorder(AppColors.red),
        focusedErrorBorder: _fieldBorder(AppColors.red, width: 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          backgroundColor: AppColors.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.red.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: AppColors.red,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.navy,
          side: const BorderSide(color: AppColors.border, width: 1.3),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          shape: const StadiumBorder(),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.red,
        disabledColor: AppColors.skyTint,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.field),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
