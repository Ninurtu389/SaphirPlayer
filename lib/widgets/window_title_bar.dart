import 'package:material_ui/material_ui.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_strings.dart';
import '../features/shell/shell_controller.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    required this.shellController,
    this.searchController,
    this.onSearchChanged,
    this.onClearSearch,
    this.showSearch = true,
  });

  final ShellController shellController;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onClearSearch;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: shellController,
      builder: (context, _) {
        return Container(
          height: AppSpacing.titleBarHeight,
          color: AppColors.anthraciteSurface,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => shellController.startWindowDragging(),
                  onDoubleTap: shellController.toggleMaximizeWindow,
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    IgnorePointer(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: AppSpacing.titleBarLogoDotSize,
                            height: AppSpacing.titleBarLogoDotSize,
                            decoration: const BoxDecoration(
                              color: AppColors.sapphireBright,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            AppStrings.appTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _WindowControlButton(
                      tooltip: AppStrings.windowMinimizeTooltip,
                      icon: Icons.remove,
                      onPressed: shellController.minimizeWindow,
                    ),
                    _WindowControlButton(
                      tooltip: shellController.isMaximized
                          ? AppStrings.windowRestoreTooltip
                          : AppStrings.windowMaximizeTooltip,
                      icon: shellController.isMaximized
                          ? Icons.filter_none
                          : Icons.crop_square,
                      onPressed: shellController.toggleMaximizeWindow,
                    ),
                    _WindowControlButton(
                      tooltip: AppStrings.windowCloseTooltip,
                      icon: Icons.close,
                      onPressed: shellController.closeWindow,
                    ),
                  ],
                ),
              ),
              if (showSearch && onSearchChanged != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.titleBarSearchHorizontalClearance,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.searchBarExpandedWidth,
                      ),
                      child: SizedBox(
                        height: AppSpacing.titleBarSearchHeight,
                        child: _GlobalSearchField(
                          controller: searchController,
                          onChanged: onSearchChanged!,
                          onClear: onClearSearch,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GlobalSearchField extends StatelessWidget {
  const _GlobalSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController? controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasText = controller != null && controller!.text.isNotEmpty;
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      borderSide: BorderSide.none,
    );

    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: AppSpacing.titleBarSearchFontSize,
          ),
      decoration: InputDecoration(
        hintText: AppStrings.searchHint,
        hintStyle: Theme.of(context).textTheme.bodySmall,
        filled: true,
        fillColor: AppColors.elevatedSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        border: noBorder,
        enabledBorder: noBorder,
        focusedBorder: noBorder,
        prefixIcon: const Icon(
          Icons.search,
          size: AppSpacing.iconSizeSm,
          color: AppColors.textSecondary,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: AppSpacing.xl,
          minHeight: AppSpacing.titleBarSearchHeight,
        ),
        suffixIcon: hasText && onClear != null
            ? IconButton(
                tooltip: AppStrings.clearSearchTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: AppSpacing.lg,
                  minHeight: AppSpacing.titleBarSearchHeight,
                ),
                onPressed: onClear,
                icon: const Icon(
                  Icons.close,
                  size: AppSpacing.iconSizeSm,
                  color: AppColors.textSecondary,
                ),
              )
            : null,
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.windowControlWidth,
        height: AppSpacing.windowControlHeight,
      ),
      icon: Icon(
        icon,
        size: AppSpacing.windowControlIconSize,
      ),
    );
  }
}
