import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';

class PlayerIntroSkipButton extends StatelessWidget {
  const PlayerIntroSkipButton({
    super.key,
    required this.effectMode,
    required this.hudVisible,
    required this.selectedSeconds,
    required this.onSkipIntro,
    required this.onSelectSeconds,
    required this.onDismiss,
  });

  final EffectMode effectMode;
  final bool hudVisible;
  final int selectedSeconds;
  final VoidCallback onSkipIntro;
  final ValueChanged<int> onSelectSeconds;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppSpacing.lg,
      bottom: hudVisible ? AppSpacing.autoNextBottomWithHud : AppSpacing.lg,
      child: SurfacePanel(
        effectMode: effectMode,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        borderRadius: AppSpacing.radiusSm,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: onSkipIntro,
              icon: const Icon(
                Icons.fast_forward,
                size: AppSpacing.iconSizeSm,
                color: AppColors.sapphireBright,
              ),
              label: const Text(AppStrings.playerIntroSkipButton),
            ),
            PopupMenuButton<int>(
              tooltip: AppStrings.playerIntroSkipSettingsTooltip,
              icon: const Icon(
                Icons.tune,
                size: AppSpacing.iconSizeSm,
              ),
              onSelected: onSelectSeconds,
              itemBuilder: (context) => AppSpacing.introSkipPresets
                  .map(
                    (sec) => PopupMenuItem<int>(
                      value: sec,
                      child: Text(
                        '$sec ${AppStrings.playerIntroSkipSecondsSuffix}',
                        style: TextStyle(
                          color: sec == selectedSeconds
                              ? AppColors.sapphireBright
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: AppSpacing.tileRemoveButtonSize,
                height: AppSpacing.tileRemoveButtonSize,
              ),
              tooltip: AppStrings.dismissIntroSkipTooltip,
              onPressed: onDismiss,
              icon: const Icon(
                Icons.close,
                size: AppSpacing.introDismissIconSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
