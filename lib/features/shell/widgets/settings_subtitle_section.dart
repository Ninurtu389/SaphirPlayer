import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/controllers/settings_controller.dart';
import '../../../core/utils/formatters.dart';

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.anthraciteSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class SettingsSubtitleSection extends StatelessWidget {
  const SettingsSubtitleSection({
    super.key,
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      title: AppStrings.settingsSubtitlesSectionTitle,
      description: AppStrings.settingsSubtitlesSectionDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: AppColors.borderTransparent,
            child: SwitchListTile(
              tileColor: AppColors.borderTransparent,
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.settingsSubtitlesDefaultLabel),
              subtitle: Text(
                AppStrings.settingsSubtitlesDefaultDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: settingsController.subtitlesEnabledByDefault,
              onChanged: settingsController.updateSubtitlesDefaultEnabled,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.settingsSubtitleLanguageLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: AppStrings.subtitleLangCodeDe,
                label: Text(AppStrings.subtitleLangDe),
              ),
              ButtonSegment<String>(
                value: AppStrings.subtitleLangCodeEn,
                label: Text(AppStrings.subtitleLangEn),
              ),
              ButtonSegment<String>(
                value: AppStrings.subtitleLangCodeAuto,
                label: Text(AppStrings.subtitleLangAuto),
              ),
            ],
            selected: {settingsController.preferredSubtitleLanguage},
            onSelectionChanged: (selection) =>
                settingsController.updatePreferredSubtitleLanguage(
              selection.first,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: AppSpacing.dividerThickness),
          const SizedBox(height: AppSpacing.sm),
          _SubtitleSliderRow(
            label: AppStrings.subtitleScaleLabel,
            valueLabel: Formatters.formatSubtitleScale(
              settingsController.subtitleScale,
            ),
            value: settingsController.subtitleScale,
            min: AppSpacing.subtitleScaleMin,
            max: AppSpacing.subtitleScaleMax,
            divisions: AppSpacing.subtitleScaleDivisions,
            onChanged: (val) =>
                settingsController.updateSubtitleStyle(scale: val),
          ),
          _SubtitleSliderRow(
            label: AppStrings.subtitlePositionLabel,
            valueLabel: Formatters.formatPercent(
              settingsController.subtitlePosition,
              isFraction: false,
            ),
            value: settingsController.subtitlePosition.toDouble(),
            min: AppSpacing.subtitlePositionMin.toDouble(),
            max: AppSpacing.subtitlePositionMax.toDouble(),
            divisions: AppSpacing.subtitlePositionDivisions,
            onChanged: (val) => settingsController.updateSubtitleStyle(
              position: val.round(),
            ),
          ),
          _SubtitleSliderRow(
            label: AppStrings.subtitleBgOpacityLabel,
            valueLabel: Formatters.formatPercent(
              settingsController.subtitleBgOpacity,
            ),
            value: settingsController.subtitleBgOpacity,
            min: AppSpacing.subtitleBgOpacityMin,
            max: AppSpacing.subtitleBgOpacityMax,
            divisions: AppSpacing.subtitleBgOpacityDivisions,
            onChanged: (val) =>
                settingsController.updateSubtitleStyle(bgOpacity: val),
          ),
        ],
      ),
    );
  }
}

class _SubtitleSliderRow extends StatelessWidget {
  const _SubtitleSliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        SizedBox(
          width: AppSpacing.heroProgressWidth,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: AppSpacing.xxl,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
