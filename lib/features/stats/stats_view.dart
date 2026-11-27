import 'package:material_ui/material_ui.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/effect_mode.dart';
import '../../core/utils/formatters.dart';
import 'stats_controller.dart';
import 'stats_models.dart';
import 'widgets/stats_cards.dart';

class StatsView extends StatelessWidget {
  const StatsView({
    super.key,
    required this.statsController,
    required this.effectMode,
  });

  final StatsController statsController;
  final EffectMode effectMode;

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
                    StatsCard(
                      effectMode: effectMode,
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
                    WeekdayChartCard(
                      weekdayWatchMs: summary.weekdayWatchMs,
                      busiestIndex: summary.busiestWeekdayIndex,
                      effectMode: effectMode,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildTopLists(summary),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopLists(StatsSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= AppSpacing.heroContentMaxWidth;
        final seriesCard = RankedListCard(
          title: AppStrings.statsTopSeriesTitle,
          items: summary.topSeries,
          effectMode: effectMode,
        );
        final moviesCard = RankedListCard(
          title: AppStrings.statsTopMoviesTitle,
          items: summary.topMovies,
          effectMode: effectMode,
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
            ? AppSpacing.statsKpiColumnsWide
            : (constraints.maxWidth >= AppSpacing.searchBarExpandedWidth
                ? AppSpacing.statsKpiColumnsMedium
                : AppSpacing.statsKpiColumnsNarrow);
        final cardWidth =
            (constraints.maxWidth - (columns - 1) * AppSpacing.md) / columns;

        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: cardWidth,
              child: StatsKpiCard(
                icon: Icons.schedule,
                title: AppStrings.statsTotalWatchtimeTitle,
                value: Formatters.formatWatchDuration(summary.totalWatchMs),
                subtitle:
                    '${AppStrings.statsSeriesWatchtimeLabel}: ${Formatters.formatWatchDuration(summary.seriesWatchMs)} · ${AppStrings.statsMoviesWatchtimeLabel}: ${Formatters.formatWatchDuration(summary.movieWatchMs)}',
                effectMode: effectMode,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatsKpiCard(
                icon: Icons.calendar_today_outlined,
                title: AppStrings.statsTopDayTitle,
                value: busiestDay != null
                    ? Formatters.formatDayKey(busiestDay.dayKey)
                    : AppStrings.statsNoDataDash,
                subtitle: busiestDay != null
                    ? '${Formatters.formatWatchDuration(busiestDay.watchedMs)} · $busiestWeekdayLabel'
                    : AppStrings.statsNoDataDash,
                effectMode: effectMode,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatsKpiCard(
                icon: Icons.local_fire_department_outlined,
                title: AppStrings.statsStreakTitle,
                value:
                    '${summary.currentStreakDays} ${AppStrings.statsStreakDaysSuffix}',
                subtitle:
                    '${AppStrings.statsStreakBestPrefix} ${summary.longestStreakDays} ${AppStrings.statsDaysShort}',
                effectMode: effectMode,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatsKpiCard(
                icon: Icons.check_circle_outline,
                title: AppStrings.statsCompletedTitle,
                value:
                    '${summary.completedEpisodes}/${summary.totalEpisodes} ${AppStrings.episodesCountLabel}',
                subtitle:
                    '${summary.completedMovies}/${summary.totalMovies} ${AppStrings.moviesCountLabel}',
                effectMode: effectMode,
              ),
            ),
          ],
        );
      },
    );
  }
}
