import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/surface_panel.dart';
import '../saphir_player_controller.dart';

class PlayerSubtitleStyleDialog extends StatelessWidget {
  const PlayerSubtitleStyleDialog({
    super.key,
    required this.controller,
    required this.effectMode,
  });

  final SaphirPlayerController controller;
  final EffectMode effectMode;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.borderTransparent,
      elevation: AppSpacing.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.subtitleStyleDialogWidth,
        ),
        child: SurfacePanel(
          effectMode: effectMode,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.playerSubtitleStyleTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.playerCloseOverlayAction,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: AppSpacing.iconSizeMd),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _StyleSlider(
                  label: AppStrings.subtitleScaleLabel,
                  valueLabel:
                      Formatters.formatSubtitleScale(controller.subtitleScale),
                  value: controller.subtitleScale,
                  min: AppSpacing.subtitleScaleMin,
                  max: AppSpacing.subtitleScaleMax,
                  divisions: AppSpacing.subtitleScaleDivisions,
                  onChanged: (v) => controller.updateLiveSubtitleStyle(scale: v),
                ),
                _StyleSlider(
                  label: AppStrings.subtitlePositionLabel,
                  valueLabel: Formatters.formatPercent(
                    controller.subtitlePosition,
                    isFraction: false,
                  ),
                  value: controller.subtitlePosition.toDouble(),
                  min: AppSpacing.subtitlePositionMin.toDouble(),
                  max: AppSpacing.subtitlePositionMax.toDouble(),
                  divisions: AppSpacing.subtitlePositionDivisions,
                  onChanged: (v) =>
                      controller.updateLiveSubtitleStyle(position: v.round()),
                ),
                _StyleSlider(
                  label: AppStrings.subtitleBgOpacityLabel,
                  valueLabel:
                      Formatters.formatPercent(controller.subtitleBgOpacity),
                  value: controller.subtitleBgOpacity,
                  min: AppSpacing.subtitleBgOpacityMin,
                  max: AppSpacing.subtitleBgOpacityMax,
                  divisions: AppSpacing.subtitleBgOpacityDivisions,
                  onChanged: (v) =>
                      controller.updateLiveSubtitleStyle(bgOpacity: v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(valueLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
