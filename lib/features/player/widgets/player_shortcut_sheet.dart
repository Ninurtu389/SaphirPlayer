import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/effect_mode.dart';
import '../../../widgets/surface_panel.dart';

class PlayerShortcutSheet extends StatelessWidget {
  const PlayerShortcutSheet({
    super.key,
    required this.effectMode,
    required this.onClose,
  });

  final EffectMode effectMode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.shortcutSheetMaxWidth,
            maxHeight: AppSpacing.shortcutSheetMaxHeight,
          ),
          child: SurfacePanel(
            effectMode: effectMode,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.playerShortcutsTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: AppStrings.playerCloseOverlayAction,
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: AppSpacing.iconSizeMd),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.dividerThickness),
                const SizedBox(height: AppSpacing.xs),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: AppStrings.playerShortcutEntries
                          .map(
                            (entry) => _ShortcutRow(
                              keyLabel: entry.$1,
                              description: entry.$2,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.keyLabel,
    required this.description,
  });

  final String keyLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.shortcutKeyBadgeMinWidth,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.badgePaddingH,
                vertical: AppSpacing.badgePaddingV,
              ),
              decoration: BoxDecoration(
                color: AppColors.elevatedSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.borderSubtle,
                  width: AppSpacing.borderWidthThin,
                ),
              ),
              child: Text(
                keyLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: AppSpacing.shortcutKeyFontSize,
                      color: AppColors.sapphireBright,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
