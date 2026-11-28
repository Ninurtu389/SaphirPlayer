import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/theme/effect_mode.dart';
import 'settings_subtitle_section.dart';

class SettingsAppearanceCard extends StatelessWidget {
  const SettingsAppearanceCard({
    super.key,
    required this.settingsController,
    required this.effectMode,
  });

  final SettingsController settingsController;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.display_settings_outlined,
      title: AppStrings.settingsAppearanceSectionTitle,
      description: AppStrings.settingsAppearanceSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEffectModeSelector(),
          const SizedBox(height: AppSpacing.md),
          const Divider(
            height: AppSpacing.dividerThickness,
            color: AppColors.dividerHairline,
          ),
          const SizedBox(height: AppSpacing.xs),
          SettingsToggleTile(
            title: AppStrings.perDeviceEffectLabel,
            subtitle: AppStrings.settingsPerDeviceDesc,
            value: settingsController.perDeviceEffect,
            onChanged: settingsController.updatePerDeviceEffect,
          ),
          const Divider(
            height: AppSpacing.dividerThickness,
            color: AppColors.dividerHairline,
          ),
          SettingsToggleTile(
            title: AppStrings.settingsHwdecLabel,
            subtitle: AppStrings.settingsHwdecDesc,
            value: settingsController.hardwareAccelerationEnabled,
            onChanged: settingsController.updateHardwareAcceleration,
          ),
        ],
      ),
    );
  }

  Widget _buildEffectModeSelector() {
    final glassCard = _EffectModeOptionCard(
      icon: Icons.auto_awesome_outlined,
      title: AppStrings.effectGlassLabel,
      description: AppStrings.settingsEffectGlassDesc,
      selected: effectMode == EffectMode.glass,
      onTap: () => settingsController.updateEffectMode(EffectMode.glass),
    );
    final leanCard = _EffectModeOptionCard(
      icon: Icons.bolt_outlined,
      title: AppStrings.effectLeanLabel,
      description: AppStrings.settingsEffectLeanDesc,
      selected: effectMode == EffectMode.lean,
      onTap: () => settingsController.updateEffectMode(EffectMode.lean),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
          return Column(
            children: [
              glassCard,
              const SizedBox(height: AppSpacing.sm),
              leanCard,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: glassCard),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: leanCard),
            ],
          ),
        );
      },
    );
  }
}

class _EffectModeOptionCard extends StatelessWidget {
  const _EffectModeOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.activeTileFill : AppColors.elevatedSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: selected ? AppColors.sapphireBright : AppColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: AppSpacing.iconSizeSm,
                  color: selected
                      ? AppColors.sapphireBright
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
