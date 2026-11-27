import 'package:flutter/services.dart';
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showTitle =
                        constraints.maxWidth >= AppSpacing.compactPlayerBreakpoint;
                    return Row(
                      children: [
                        IgnorePointer(
                          child: _TitleBarBrand(showTitle: showTitle),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: (showSearch && onSearchChanged != null)
                              ? Center(
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
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _WindowControlsRow(shellController: shellController),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TitleBarBrand extends StatelessWidget {
  const _TitleBarBrand({required this.showTitle});

  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        if (showTitle) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            AppStrings.appTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }
}

class _GlobalSearchField extends StatefulWidget {
  const _GlobalSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController? controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  State<_GlobalSearchField> createState() => _GlobalSearchFieldState();
}

class _GlobalSearchFieldState extends State<_GlobalSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleEscape() {
    if (widget.controller != null && widget.controller!.text.isNotEmpty) {
      widget.onClear?.call();
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return _buildField(context, hasText: false);
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _buildField(context, hasText: value.text.isNotEmpty),
    );
  }

  Widget _buildField(BuildContext context, {required bool hasText}) {
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      borderSide: BorderSide.none,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      borderSide: const BorderSide(
        color: AppColors.sapphireBright,
        width: AppSpacing.borderWidthThin,
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        textAlignVertical: TextAlignVertical.center,
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
            vertical: AppSpacing.zero,
          ),
          border: baseBorder,
          enabledBorder: baseBorder,
          focusedBorder: focusedBorder,
          prefixIcon: const Icon(
            Icons.search,
            size: AppSpacing.iconSizeSm,
            color: AppColors.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: AppSpacing.xl,
            minHeight: AppSpacing.titleBarSearchHeight,
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: AppSpacing.lg,
            minHeight: AppSpacing.titleBarSearchHeight,
          ),
          suffixIcon: hasText && widget.onClear != null
              ? IconButton(
                  tooltip: AppStrings.clearSearchTooltip,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.lg,
                    minHeight: AppSpacing.titleBarSearchHeight,
                  ),
                  onPressed: widget.onClear,
                  icon: const Icon(
                    Icons.close,
                    size: AppSpacing.iconSizeSm,
                    color: AppColors.textSecondary,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _WindowControlsRow extends StatelessWidget {
  const _WindowControlsRow({required this.shellController});

  final ShellController shellController;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          iconSize: shellController.isMaximized
              ? AppSpacing.windowRestoreIconSize
              : AppSpacing.windowMaximizeIconSize,
          onPressed: shellController.toggleMaximizeWindow,
        ),
        _WindowControlButton(
          tooltip: AppStrings.windowCloseTooltip,
          icon: Icons.close,
          hoverColor: AppColors.errorRed,
          onPressed: shellController.closeWindow,
        ),
      ],
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = AppSpacing.windowControlIconSize,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      style: hoverColor != null
          ? IconButton.styleFrom(hoverColor: hoverColor)
          : null,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.windowControlWidth,
        height: AppSpacing.windowControlHeight,
      ),
      icon: Icon(
        icon,
        size: iconSize,
      ),
    );
  }
}
