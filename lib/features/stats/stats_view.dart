import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import 'stats_controller.dart';
import 'stats_models.dart';

class StatsView extends StatelessWidget {
  const StatsView({
    super.key,
    required this.statsController,
    required this.effectMode,
  });

  final StatsController statsController;
  final EffectMode effectMode;

  String _formatDuration(int ms) {
    if (ms <= 0) {
      return '0 ${AppStrings.statsMinutesShort}';
    }
    final totalMinutes = (ms / AppSpacing.millisecondsPerMinute).round();
    final hours = totalMinutes ~/ AppSpacing.secondsPerMinute;
    final minutes = totalMinutes % AppSpacing.secondsPerMinute;
    if (hours > 0) {
      return '$hours ${AppStrings.statsHoursShort} $minutes ${AppStrings.statsMinutesShort}';
    }
    return '$minutes ${AppStrings.statsMinutesShort}';
  }

  String _formatDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      return dayKey;
    }
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: statsController,
      builder: (context, _) {
        final summary = statsController.summary;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.statsMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.statsPageTitle,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (!summary.hasAnyData)
                    _StatsCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                        child: Center(
                          child: Text(
                            AppStrings.statsEmptyMessage,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    _buildKpiGrid(context, summary),
                    const SizedBox(height: AppSpacing.md),
                    _WeekdayChartCard(
                      weekdayWatchMs: summary.weekdayWatchMs,
                      busiestIndex: summary.busiestWeekdayIndex,
                      formatDuration: _formatDuration,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide =
                            constraints.maxWidth >= AppSpacing.heroContentMaxWidth;
                        final seriesCard = _RankedListCard(
                          title: AppStrings.statsTopSeriesTitle,
                          items: summary.topSeries,
                          formatDuration: _formatDuration,
                        );
                        final moviesCard = _RankedListCard(
                          title: AppStrings.statsTopMoviesTitle,
                          items: summary.topMovies,
                          formatDuration: _formatDuration,
                        );
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: seriesCard),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(child: moviesCard),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            seriesCard,
                            const SizedBox(height: AppSpacing.md),
                            moviesCard,
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiGrid(BuildContext context, StatsSummary summary) {
    final busiestDay = summary.busiestDay;
    final busiestWeekdayIdx = summary.busiestWeekdayIndex;
    final busiestWeekdayLabel = busiestWeekdayIdx != null
        ? AppStrings.statsWeekdayFullNames[busiestWeekdayIdx]
        : AppStrings.statsNoDataDash;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= AppSpacing.maxSettingsWidth
            ? 4
            : (constraints.maxWidth >= AppSpacing.searchBarExpandedWidth ? 2 : 1);
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.schedule,
                title: AppStrings.statsTotalWatchtimeTitle,
                value: _formatDuration(summary.totalWatchMs),
                subtitle:
                    '${AppStrings.statsSeriesWatchtimeLabel}: ${_formatDuration(summary.seriesWatchMs)} · ${AppStrings.statsMoviesWatchtimeLabel}: ${_formatDuration(summary.movieWatchMs)}',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.calendar_today_outlined,
                title: AppStrings.statsTopDayTitle,
                value: busiestDay != null
                    ? _formatDayKey(busiestDay.dayKey)
                    : AppStrings.statsNoDataDash,
                subtitle: busiestDay != null
                    ? '${_formatDuration(busiestDay.watchedMs)} · $busiestWeekdayLabel'
                    : AppStrings.statsNoDataDash,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.local_fire_department_outlined,
                title: AppStrings.statsStreakTitle,
                value:
                    '${summary.currentStreakDays} ${AppStrings.statsStreakDaysSuffix}',
                subtitle:
                    '${AppStrings.statsStreakBestPrefix} ${summary.longestStreakDays} ${AppStrings.statsDaysShort}',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _KpiCard(
                icon: Icons.check_circle_outline,
                title: AppStrings.statsCompletedTitle,
                value:
                    '${summary.completedEpisodes}/${summary.totalEpisodes} ${AppStrings.episodesCountLabel}',
                subtitle:
                    '${summary.completedMovies}/${summary.totalMovies} ${AppStrings.moviesCountLabel}',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.child});

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

class _KpiCard extends StatelessWidget {
  const _KpiCard({
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
    return _StatsCard(
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

class _WeekdayChartCard extends StatelessWidget {
  const _WeekdayChartCard({
    required this.weekdayWatchMs,
    required this.busiestIndex,
    required this.formatDuration,
  });

  final List<int> weekdayWatchMs;
  final int? busiestIndex;
  final String Function(int ms) formatDuration;

  @override
  Widget build(BuildContext context) {
    var maxMs = 0;
    for (final ms in weekdayWatchMs) {
      if (ms > maxMs) {
        maxMs = ms;
      }
    }

    return _StatsCard(
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
            children: List.generate(weekdayWatchMs.length, (index) {
              final ms = weekdayWatchMs[index];
              final ratio = maxMs > 0 ? (ms / maxMs).clamp(0.0, 1.0) : 0.0;
              final barHeight = ms > 0
                  ? (ratio * AppSpacing.statsBarMaxHeight)
                      .clamp(AppSpacing.xs, AppSpacing.statsBarMaxHeight)
                  : AppSpacing.xxs;
              final isTop = busiestIndex == index && ms > 0;

              return Expanded(
                child: Tooltip(
                  message:
                      '${AppStrings.statsWeekdayFullNames[index]}: ${formatDuration(ms)}',
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
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSm),
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
                              fontWeight:
                                  isTop ? FontWeight.w700 : FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _RankedListCard extends StatelessWidget {
  const _RankedListCard({
    required this.title,
    required this.items,
    required this.formatDuration,
  });

  final String title;
  final List<RankedMediaStat> items;
  final String Function(int ms) formatDuration;

  @override
  Widget build(BuildContext context) {
    final topMs = items.isNotEmpty ? items.first.watchedMs : 0;

    return _StatsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${index + 1}. ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${formatDuration(item.watchedMs)} · ${item.playCount}${AppStrings.statsPlaysSuffix}',
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
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}
