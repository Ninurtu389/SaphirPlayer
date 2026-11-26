import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../shell_controller.dart';

class NavigationSidebar extends StatelessWidget {
  const NavigationSidebar({
    super.key,
    required this.activeSection,
    required this.onSelectSection,
  });

  final AppSection activeSection;
  final ValueChanged<AppSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.navRailWidth,
      color: AppColors.anthraciteSurface,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          _NavRailItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: AppStrings.homeTab,
            selected: activeSection == AppSection.home,
            onTap: () => onSelectSection(AppSection.home),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavRailItem(
            icon: Icons.video_library_outlined,
            selectedIcon: Icons.video_library,
            label: AppStrings.libraryTab,
            selected: activeSection == AppSection.library,
            onTap: () => onSelectSection(AppSection.library),
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavRailItem(
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            label: AppStrings.statsTab,
            selected: activeSection == AppSection.stats,
            onTap: () => onSelectSection(AppSection.stats),
          ),
          const Spacer(),
          _NavRailItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: AppStrings.settingsTab,
            selected: activeSection == AppSection.settings,
            onTap: () => onSelectSection(AppSection.settings),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _NavRailItem extends StatefulWidget {
  const _NavRailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final foregroundColor = isSelected
        ? AppColors.sapphireBright
        : (_isHovered ? AppColors.textPrimary : AppColors.textSecondary);
    final backgroundColor = isSelected
        ? AppColors.elevatedSurface
        : (_isHovered ? AppColors.surfaceHover : AppColors.borderTransparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: AppColors.borderTransparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            height: AppSpacing.navItemHeight,
            color: backgroundColor,
            child: Row(
              children: [
                Container(
                  width: AppSpacing.navIndicatorWidth,
                  height: AppSpacing.navIndicatorHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.sapphireBright
                        : AppColors.borderTransparent,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(AppSpacing.xxs),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? widget.selectedIcon : widget.icon,
                        color: foregroundColor,
                        size: AppSpacing.iconSizeMd,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: foregroundColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                      ),
                    ],
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
