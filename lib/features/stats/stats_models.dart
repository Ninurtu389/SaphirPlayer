class RankedMediaStat {
  const RankedMediaStat({
    required this.title,
    required this.watchedMs,
    required this.playCount,
  });

  final String title;
  final int watchedMs;
  final int playCount;
}

class DayWatchStat {
  const DayWatchStat({
    required this.dayKey,
    required this.watchedMs,
  });

  final String dayKey;
  final int watchedMs;
}

class StatsSummary {
  const StatsSummary({
    required this.totalWatchMs,
    required this.seriesWatchMs,
    required this.movieWatchMs,
    required this.completedEpisodes,
    required this.totalEpisodes,
    required this.completedMovies,
    required this.totalMovies,
    required this.weekdayWatchMs,
    required this.busiestDay,
    required this.busiestWeekdayIndex,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.topSeries,
    required this.topMovies,
  });

  static const StatsSummary empty = StatsSummary(
    totalWatchMs: 0,
    seriesWatchMs: 0,
    movieWatchMs: 0,
    completedEpisodes: 0,
    totalEpisodes: 0,
    completedMovies: 0,
    totalMovies: 0,
    weekdayWatchMs: [0, 0, 0, 0, 0, 0, 0],
    busiestDay: null,
    busiestWeekdayIndex: null,
    currentStreakDays: 0,
    longestStreakDays: 0,
    topSeries: [],
    topMovies: [],
  );

  final int totalWatchMs;
  final int seriesWatchMs;
  final int movieWatchMs;
  final int completedEpisodes;
  final int totalEpisodes;
  final int completedMovies;
  final int totalMovies;
  final List<int> weekdayWatchMs;
  final DayWatchStat? busiestDay;
  final int? busiestWeekdayIndex;
  final int currentStreakDays;
  final int longestStreakDays;
  final List<RankedMediaStat> topSeries;
  final List<RankedMediaStat> topMovies;

  bool get hasAnyData =>
      totalWatchMs > 0 || completedEpisodes > 0 || completedMovies > 0;
}
