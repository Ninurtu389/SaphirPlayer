import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/theme/effect_mode.dart';

class SurfacePanel extends StatelessWidget {
  const SurfacePanel({
    super.key,
    required this.child,
    required this.effectMode,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.borderRadius = AppSpacing.radiusMd,
  });

  final Widget child;
  final EffectMode effectMode;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isGlass = effectMode == EffectMode.glass;
    final radius = BorderRadius.circular(borderRadius);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color:
            isGlass ? AppColors.glassOverlayFill : AppColors.solidOverlayFill,
        borderRadius: radius,
        border: Border.all(
          color: isGlass ? AppColors.sapphireGlow : AppColors.borderSubtle,
        ),
      ),
      child: child,
    );

    if (!isGlass) {
      return container;
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppSpacing.blurSigmaGlass,
          sigmaY: AppSpacing.blurSigmaGlass,
        ),
        child: container,
      ),
    );
  }
}
