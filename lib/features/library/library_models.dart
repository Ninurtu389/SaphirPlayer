import '../../core/utils/formatters.dart';

enum LibraryFilter {
  all,
  series,
  movies,
}

class MediaCardItem {
  const MediaCardItem({
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.progressRatio,
    required this.remainingMinutes,
    required this.isCompleted,
    required this.seriesId,
    required this.filePath,
    this.artist,
  });

  final String mediaKey;
  final String mediaType;
  final String title;
  final String subtitle;
  final String? imagePath;
  final double progressRatio;
  final int remainingMinutes;
  final bool isCompleted;
  final int? seriesId;
  final String filePath;
  final String? artist;

  String get monogram {
    final words = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return words.first.substring(0, words.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

class SeasonGroup {
  const SeasonGroup({
    required this.seasonId,
    required this.seasonNumber,
    required this.episodes,
  });

  final int seasonId;
  final int seasonNumber;
  final List<EpisodeEntry> episodes;
}

class EpisodeEntry {
  const EpisodeEntry({
    required this.id,
    required this.seriesId,
    required this.seasonId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.filePath,
    required this.durationMs,
    required this.thumbPath,
    required this.positionMs,
    required this.isCompleted,
    this.syncKey,
    this.artist,
  });

  final int id;
  final int seriesId;
  final int seasonId;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String filePath;
  final int durationMs;
  final String? thumbPath;
  final int positionMs;
  final bool isCompleted;
  final String? syncKey;
  final String? artist;

  String get mediaKey =>
      (syncKey != null && syncKey!.isNotEmpty)
          ? syncKey!
          : Formatters.episodeMediaKey(id);

  double get progressRatio {
    if (isCompleted) {
      return 1.0;
    }
    if (durationMs <= 0 || positionMs <= 0) {
      return 0.0;
    }
    final ratio = positionMs / durationMs;
    return ratio.clamp(0.0, 1.0);
  }

  String get formattedDuration =>
      Formatters.formatEpisodeDurationMinutes(durationMs);
}

class SeriesDetailData {
  const SeriesDetailData({
    required this.seriesId,
    required this.title,
    required this.folderPath,
    required this.posterPath,
    required this.summary,
    required this.seasons,
  });

  final int seriesId;
  final String title;
  final String folderPath;
  final String? posterPath;
  final String? summary;
  final List<SeasonGroup> seasons;

  int get totalEpisodes {
    var count = 0;
    for (final season in seasons) {
      count += season.episodes.length;
    }
    return count;
  }

  int get watchedEpisodes {
    var count = 0;
    for (final season in seasons) {
      for (final ep in season.episodes) {
        if (ep.isCompleted) {
          count++;
        }
      }
    }
    return count;
  }

  double get overallProgress {
    if (totalEpisodes <= 0) {
      return 0.0;
    }
    return (watchedEpisodes / totalEpisodes).clamp(0.0, 1.0);
  }

  EpisodeEntry? get nextResumeEpisode {
    EpisodeEntry? firstUnwatched;
    EpisodeEntry? firstAny;
    for (final season in seasons) {
      for (final ep in season.episodes) {
        firstAny ??= ep;
        if (ep.positionMs > 0 && !ep.isCompleted) {
          return ep;
        }
        if (!ep.isCompleted) {
          firstUnwatched ??= ep;
        }
      }
    }
    return firstUnwatched ?? firstAny;
  }
}
