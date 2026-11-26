import 'package:material_ui/material_ui.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData buildDarkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.sapphirePrimary,
      onPrimary: AppColors.textPrimary,
      secondary: AppColors.sapphireBright,
      onSecondary: AppColors.oledBackground,
      surface: AppColors.anthraciteSurface,
      onSurface: AppColors.textPrimary,
      error: Color(0xFFE05252),
      onError: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.oledBackground,
      canvasColor: AppColors.anthraciteSurface,
      dividerColor: AppColors.borderSubtle,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22.0,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12.0,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.sapphirePrimary,
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
        ),
      ),
    );
  }
}
