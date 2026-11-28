import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/status_feedback_models.dart';

class ShellStartupBanner extends StatelessWidget {
  const ShellStartupBanner({
    super.key,
    required this.banner,
    required this.canRetrySync,
    required this.onRetrySync,
    required this.onDismiss,
  });

  final StatusBannerMessage banner;
  final bool canRetrySync;
  final VoidCallback onRetrySync;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = _colorForSeverity(banner.severity);
    final icon = banner.severity == StatusSeverity.error
        ? Icons.error_outline
        : Icons.warning_amber_rounded;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.zero,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: AppSpacing.iconSizeMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _buildResponsiveContent(context)),
          IconButton(
            tooltip: AppStrings.playerCloseOverlayAction,
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: AppSpacing.iconSizeSm),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              banner.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (banner.detail != null && banner.detail!.isNotEmpty)
              Text(
                banner.detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
        if (constraints.maxWidth < AppSpacing.settingsCompactRowBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              textBlock,
              if (canRetrySync)
                TextButton(
                  onPressed: onRetrySync,
                  child: const Text(AppStrings.startupSyncRetryButton),
                ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: textBlock),
            if (canRetrySync) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: onRetrySync,
                child: const Text(AppStrings.startupSyncRetryButton),
              ),
            ],
          ],
        );
      },
    );
  }

  static Color _colorForSeverity(StatusSeverity severity) {
    switch (severity) {
      case StatusSeverity.error:
        return AppColors.errorRed;
      case StatusSeverity.warning:
        return AppColors.warningAmber;
      case StatusSeverity.success:
        return AppColors.successGreen;
      case StatusSeverity.info:
        return AppColors.sapphireBright;
    }
  }
}
