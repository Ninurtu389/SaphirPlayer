import 'package:material_ui/material_ui.dart';

class AppColors {
  AppColors._();

  static const Color oledBackground = Color(0xFF080A0F);
  static const Color anthraciteSurface = Color(0xFF10141D);
  static const Color elevatedSurface = Color(0xFF161C28);
  static const Color surfaceHover = Color(0xFF1E2636);
  static const Color glassOverlayFill = Color(0xA610141D);
  static const Color solidOverlayFill = Color(0xF010141D);

  static const Color sapphirePrimary = Color(0xFF1D6FE5);
  static const Color sapphireBright = Color(0xFF4B9BFF);
  static const Color sapphireGlow = Color(0x332979FF);
  static const Color sapphireHoverBorder = Color(0xCC4B9BFF);
  static const Color sapphireHoverShadow = Color(0x4D1D6FE5);

  static const Color borderTransparent = Colors.transparent;
  static const Color borderSubtle = Color(0xFF233047);
  static const Color dividerHairline = Color(0x1AFFFFFF);
  static const Color badgeBackground = Color(0xCC080A0F);
  static const Color scrollArrowBackground = Color(0xBF080A0F);

  static const Color textPrimary = Color(0xFFF2F6FC);
  static const Color textSecondary = Color(0xFFA7B3C7);

  static const Color successGreen = Color(0xFF25B869);
  static const Color progressTrack = Color(0xFF28354D);
  static const Color errorRed = Color(0xFFE05252);

  static const LinearGradient heroVerticalFadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
    colors: [
      Color(0x00080A0F),
      Color(0x99080A0F),
      oledBackground,
    ],
  );

  static const LinearGradient heroHorizontalFadeGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    stops: [0.0, 0.45, 0.78, 1.0],
    colors: [
      Color(0xF5080A0F),
      Color(0xBF080A0F),
      Color(0x33080A0F),
      Color(0x00080A0F),
    ],
  );

  static const LinearGradient cardOverlayGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.4, 0.75, 1.0],
    colors: [
      Color(0x00080A0F),
      Color(0x26080A0F),
      Color(0xCC080A0F),
      Color(0xF2080A0F),
    ],
  );

  static const LinearGradient playerTopHudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.6, 1.0],
    colors: [
      Color(0xD9000000),
      Color(0x73000000),
      Color(0x00000000),
    ],
  );

  static const LinearGradient playerBottomHudGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.4, 1.0],
    colors: [
      Color(0x00000000),
      Color(0x8C000000),
      Color(0xEB000000),
    ],
  );

  static const List<List<Color>> _coverFallbackGradients = [
    [Color(0xFF0E2347), Color(0xFF091326)],
    [Color(0xFF1B1B42), Color(0xFF0D0E24)],
    [Color(0xFF3E1222), Color(0xFF1D0911)],
    [Color(0xFF0F2E36), Color(0xFF09191E)],
    [Color(0xFF3B2410), Color(0xFF1A1007)],
    [Color(0xFF2A163E), Color(0xFF140B1F)],
  ];

  static List<Color> coverGradientForTitle(String title) {
    final hash = title.codeUnits.fold<int>(0, (acc, unit) => acc * 31 + unit);
    final index = hash.abs() % _coverFallbackGradients.length;
    return _coverFallbackGradients[index];
  }
}
