import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_strings.dart';
import '../features/shell/shell_controller.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    required this.shellController,
  });

  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shellController,
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: shellController.toggleMaximizeWindow,
          child: Container(
            height: AppSpacing.titleBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.anthraciteSurface,
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.xs,
                  height: AppSpacing.xs,
                  decoration: const BoxDecoration(
                    color: AppColors.sapphireBright,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  AppStrings.appTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Minimieren',
                  onPressed: shellController.minimizeWindow,
                  icon: const Icon(Icons.remove, size: AppSpacing.md),
                ),
                IconButton(
                  tooltip: shellController.isMaximized
                      ? 'Wiederherstellen'
                      : 'Maximieren',
                  onPressed: shellController.toggleMaximizeWindow,
                  icon: Icon(
                    shellController.isMaximized
                        ? Icons.filter_none
                        : Icons.crop_square,
                    size: AppSpacing.md,
                  ),
                ),
                IconButton(
                  tooltip: 'Schliessen',
                  onPressed: shellController.closeWindow,
                  icon: const Icon(Icons.close, size: AppSpacing.md),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
