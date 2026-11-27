import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';
import '../player_models.dart';

class PlayerDiagnosticsOverlay extends StatelessWidget {
  const PlayerDiagnosticsOverlay({
    super.key,
    required this.diagnostics,
    required this.effectMode,
    required this.onClose,
  });

  final PlayerDiagnostics? diagnostics;
  final EffectMode effectMode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final diag = diagnostics;
    return Positioned(
      top: AppSpacing.diagnosticsTopOffset,
      left: AppSpacing.md,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.diagnosticsOverlayMaxWidth,
        ),
        child: SurfacePanel(
          effectMode: effectMode,
          padding: const EdgeInsets.all(AppSpacing.sm),
          borderRadius: AppSpacing.radiusSm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.playerDiagnosticsTitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.sapphireBright,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: AppStrings.playerCloseOverlayAction,
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: AppSpacing.iconSizeSm),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              _DiagRow(
                label: AppStrings.diagVideoCodecLabel,
                value: diag?.videoCodec ?? AppStrings.diagUnknownValue,
              ),
              _DiagRow(
                label: AppStrings.diagAudioCodecLabel,
                value: diag?.audioCodec ?? AppStrings.diagUnknownValue,
              ),
              _DiagRow(
                label: AppStrings.diagResolutionLabel,
                value: diag?.resolution ?? AppStrings.diagUnknownValue,
              ),
              _DiagRow(
                label: AppStrings.diagFpsLabel,
                value: diag?.fps ?? AppStrings.diagUnknownValue,
              ),
              _DiagRow(
                label: AppStrings.diagHwdecLabel,
                value: diag?.hwdec ?? AppStrings.diagUnknownValue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: AppSpacing.diagnosticsFontSize,
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: AppSpacing.diagnosticsFontSize,
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
