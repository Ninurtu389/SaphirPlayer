import 'package:material_ui/material_ui.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/formatters.dart';
import '../stats_models.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.child,
  });

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
      child: child,
    );
  }
}

class StatsKpiCard extends StatelessWidget {
  const StatsKpiCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: AppSpacing.iconSizeMd,
                color: AppColors.sapphireBright,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class WeekdayChartCard extends StatelessWidget {
  const WeekdayChartCard({
    super.key,
    required this.weekdayWatchMs,
    required this.busiestIndex,
  });

  final List<int> weekdayWatchMs;
  final int? busiestIndex;

  @override
  Widget build(BuildContext context) {
    var maxMs = 0;
    for (final ms in weekdayWatchMs) {
      if (ms > maxMs) {
        maxMs = ms;
      }
    }

    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.statsWeekdayChartTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (busiestIndex != null)
                Text(
                  '${AppStrings.statsTopWeekdayTitle}: ${AppStrings.statsWeekdayFullNames[busiestIndex!]}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.sapphireBright,
                      ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              weekdayWatchMs.length,
              (index) => _WeekdayBarItem(
                index: index,
                ms: weekdayWatchMs[index],
                maxMs: maxMs,
                isTop: busiestIndex == index && weekdayWatchMs[index] > 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayBarItem extends StatelessWidget {
  const _WeekdayBarItem({
    required this.index,
    required this.ms,
    required this.maxMs,
    required this.isTop,
  });

  final int index;
  final int ms;
  final int maxMs;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final ratio = maxMs > 0 ? (ms / maxMs).clamp(0.0, 1.0) : 0.0;
    final barHeight = ms > 0
        ? (ratio * AppSpacing.statsBarMaxHeight)
            .clamp(AppSpacing.xs, AppSpacing.statsBarMaxHeight)
        : AppSpacing.xxs;

    return Expanded(
      child: Tooltip(
        message:
            '${AppStrings.statsWeekdayFullNames[index]}: ${Formatters.formatWatchDuration(ms)}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: AppSpacing.statsBarMaxHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: AppSpacing.statsBarWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isTop
                        ? AppColors.sapphireBright
                        : (ms > 0
                            ? AppColors.sapphirePrimary
                            : AppColors.progressTrack),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.statsWeekdayLabels[index],
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isTop
                        ? AppColors.sapphireBright
                        : AppColors.textSecondary,
                    fontWeight: isTop ? FontWeight.w700 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class RankedListCard extends StatelessWidget {
  const RankedListCard({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<RankedMediaStat> items;

  @override
  Widget build(BuildContext context) {
    final topMs = items.isNotEmpty ? items.first.watchedMs : 0;

    return StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (items.isEmpty)
            Text(
              AppStrings.statsNoDataDash,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Column(
              children: List.generate(items.length, (index) {
                final item = items[index];
                final ratio = topMs > 0
                    ? (item.watchedMs / topMs).clamp(0.0, 1.0)
                    : 0.0;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < items.length - 1 ? AppSpacing.sm : 0.0,
                  ),
                  child: _RankedRow(
                    rank: index + 1,
                    item: item,
                    ratio: ratio,
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.rank,
    required this.item,
    required this.ratio,
  });

  final int rank;
  final RankedMediaStat item;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$rank. ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${Formatters.formatWatchDuration(item.watchedMs)} · ${item.playCount}${AppStrings.statsPlaysSuffix}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: AppSpacing.progressBarHeight,
            backgroundColor: AppColors.progressTrack,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppColors.sapphireBright,
            ),
          ),
        ),
      ],
    );
  }
}
