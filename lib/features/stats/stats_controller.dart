import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/storage/database_service.dart';
import 'stats_models.dart';

class StatsController extends ChangeNotifier {
  StatsController(this._databaseService);

  final DatabaseService _databaseService;
  StatsSummary _summary = StatsSummary.empty;

  StatsSummary get summary => _summary;

  void refreshStats() {
    final db = _databaseService.instance;

    final typeRows = db.select(
      '''
      SELECT media_type, COALESCE(SUM(watched_ms), 0) AS total_ms
      FROM watch_history
      GROUP BY media_type;
      ''',
    );

    var seriesWatchMs = 0;
    var movieWatchMs = 0;
    for (final row in typeRows) {
      final type = row['media_type'] as String;
      final totalMs = (row['total_ms'] as int?) ?? 0;
      if (type == 'episode') {
        seriesWatchMs += totalMs;
      } else if (type == 'movie') {
        movieWatchMs += totalMs;
      }
    }
    final totalWatchMs = seriesWatchMs + movieWatchMs;

    final weekdayWatchMs = List<int>.filled(7, 0);
    final weekdayRows = db.select(
      '''
      SELECT weekday, COALESCE(SUM(watched_ms), 0) AS total_ms
      FROM watch_history
      GROUP BY weekday;
      ''',
    );
    for (final row in weekdayRows) {
      final wd = row['weekday'] as int;
      final totalMs = (row['total_ms'] as int?) ?? 0;
      if (wd >= 1 && wd <= 7) {
        weekdayWatchMs[wd - 1] = totalMs;
      }
    }

    int? busiestWeekdayIndex;
    var maxWeekdayMs = 0;
    for (var i = 0; i < weekdayWatchMs.length; i++) {
      if (weekdayWatchMs[i] > maxWeekdayMs) {
        maxWeekdayMs = weekdayWatchMs[i];
        busiestWeekdayIndex = i;
      }
    }

    final dayRows = db.select(
      '''
      SELECT day_key, COALESCE(SUM(watched_ms), 0) AS total_ms
      FROM watch_history
      GROUP BY day_key
      ORDER BY day_key ASC;
      ''',
    );

    DayWatchStat? busiestDay;
    final dayDates = <DateTime>[];
    for (final row in dayRows) {
      final dayKey = row['day_key'] as String;
      final totalMs = (row['total_ms'] as int?) ?? 0;
      if (totalMs > 0) {
        if (busiestDay == null || totalMs > busiestDay.watchedMs) {
          busiestDay = DayWatchStat(dayKey: dayKey, watchedMs: totalMs);
        }
        final parsed = _parseDayKey(dayKey);
        if (parsed != null) {
          dayDates.add(parsed);
        }
      }
    }

    final (currentStreak, longestStreak) = _computeStreaks(dayDates);

    final topSeriesRows = db.select(
      '''
      SELECT
        COALESCE(s.title, wh.title) AS display_title,
        COALESCE(SUM(wh.watched_ms), 0) AS total_ms,
        COUNT(*) AS play_count
      FROM watch_history wh
      LEFT JOIN series s ON s.id = wh.series_id
      WHERE wh.media_type = 'episode'
      GROUP BY COALESCE(s.title, wh.title)
      HAVING total_ms > 0
      ORDER BY total_ms DESC
      LIMIT ?;
      ''',
      [AppSpacing.statsTopListLimit],
    );

    final topSeries = topSeriesRows
        .map(
          (r) => RankedMediaStat(
            title: r['display_title'] as String,
            watchedMs: (r['total_ms'] as int?) ?? 0,
            playCount: (r['play_count'] as int?) ?? 0,
          ),
        )
        .toList();

    final topMovieRows = db.select(
      '''
      SELECT
        COALESCE(m.title, wh.title) AS display_title,
        COALESCE(SUM(wh.watched_ms), 0) AS total_ms,
        COUNT(*) AS play_count
      FROM watch_history wh
      LEFT JOIN movies m ON wh.media_key = 'movie_' || m.id
      WHERE wh.media_type = 'movie'
      GROUP BY wh.media_key, COALESCE(m.title, wh.title)
      HAVING total_ms > 0
      ORDER BY total_ms DESC
      LIMIT ?;
      ''',
      [AppSpacing.statsTopListLimit],
    );

    final topMovies = topMovieRows
        .map(
          (r) => RankedMediaStat(
            title: r['display_title'] as String,
            watchedMs: (r['total_ms'] as int?) ?? 0,
            playCount: (r['play_count'] as int?) ?? 0,
          ),
        )
        .toList();

    final totalEpRow = db.select('SELECT COUNT(*) AS cnt FROM episodes;').first;
    final completedEpRow = db
        .select(
          "SELECT COUNT(*) AS cnt FROM watch_progress WHERE media_type = 'episode' AND completed = 1;",
        )
        .first;
    final totalMovieRow = db.select('SELECT COUNT(*) AS cnt FROM movies;').first;
    final completedMovieRow = db
        .select(
          "SELECT COUNT(*) AS cnt FROM watch_progress WHERE media_type = 'movie' AND completed = 1;",
        )
        .first;

    _summary = StatsSummary(
      totalWatchMs: totalWatchMs,
      seriesWatchMs: seriesWatchMs,
      movieWatchMs: movieWatchMs,
      completedEpisodes: (completedEpRow['cnt'] as int?) ?? 0,
      totalEpisodes: (totalEpRow['cnt'] as int?) ?? 0,
      completedMovies: (completedMovieRow['cnt'] as int?) ?? 0,
      totalMovies: (totalMovieRow['cnt'] as int?) ?? 0,
      weekdayWatchMs: weekdayWatchMs,
      busiestDay: busiestDay,
      busiestWeekdayIndex: busiestWeekdayIndex,
      currentStreakDays: currentStreak,
      longestStreakDays: longestStreak,
      topSeries: topSeries,
      topMovies: topMovies,
    );

    notifyListeners();
  }

  static DateTime? _parseDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static (int, int) _computeStreaks(List<DateTime> sortedDates) {
    if (sortedDates.isEmpty) {
      return (0, 0);
    }

    var longest = 1;
    var currentRun = 1;
    for (var i = 1; i < sortedDates.length; i++) {
      final diffDays = sortedDates[i].difference(sortedDates[i - 1]).inDays;
      if (diffDays == 1) {
        currentRun += 1;
        if (currentRun > longest) {
          longest = currentRun;
        }
      } else if (diffDays > 1) {
        currentRun = 1;
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDate = sortedDates.last;
    final daysSinceLast = today.difference(lastDate).inDays;
    final currentStreak = daysSinceLast <= 1 ? currentRun : 0;

    return (currentStreak, longest);
  }
}
