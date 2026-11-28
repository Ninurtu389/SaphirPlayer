import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/media_source_models.dart';
import '../../../core/utils/formatters.dart';

class RemoveSourceDialog extends StatelessWidget {
  const RemoveSourceDialog({super.key, required this.source});

  final MediaSourceEntry source;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.anthraciteSurface,
      title: const Text(AppStrings.sourceRemoveDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSpacing.shortcutSheetMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Formatters.formatCompactPath(source.rootPath),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.sapphireBright,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.sourceRemoveDialogMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(AppStrings.cancelAction),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).pop(SourceRemovalAction.disableKeepData),
          child: const Text(AppStrings.sourceDisableKeepDataAction),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.errorRed,
            foregroundColor: AppColors.textPrimary,
          ),
          onPressed: () =>
              Navigator.of(context).pop(SourceRemovalAction.removeWithIndex),
          child: const Text(AppStrings.sourceRemoveWithIndexAction),
        ),
      ],
    );
  }
}
