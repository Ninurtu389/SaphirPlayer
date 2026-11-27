import '../../features/library/library_models.dart';
import '../../features/player/player_models.dart';
import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';

class Formatters {
  Formatters._();

  static String formatCacheSize(int bytes) {
    final mb = bytes / AppSpacing.bytesPerMegabyte;
    return '${mb.toStringAsFixed(1)} ${AppStrings.megabytesUnit}';
  }

  static String formatPlayerDuration(Duration value) {
    final totalSeconds =
        value.inSeconds.clamp(0, AppSpacing.maxPlayerDurationSeconds);
    final hours = totalSeconds ~/ AppSpacing.secondsPerHour;
    final minutes =
        (totalSeconds % AppSpacing.secondsPerHour) ~/ AppSpacing.secondsPerMinute;
    final seconds = totalSeconds % AppSpacing.secondsPerMinute;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  static String formatWatchDuration(int ms) {
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

  static String formatDayKey(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) {
      return dayKey;
    }
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  static String formatEpisodeSubtitle(
    int seasonNumber,
    int episodeNumber,
    String title, {
    String? artist,
  }) {
    final base =
        'S${seasonNumber}E$episodeNumber${AppStrings.metadataSeparator}$title';
    final cleanArtist = artist?.trim();
    if (cleanArtist != null && cleanArtist.isNotEmpty) {
      return '$base${AppStrings.metadataSeparator}$cleanArtist';
    }
    return base;
  }

  static String formatMovieSubtitle(int? releaseYear, String? artist) {
    final parts = <String>[AppStrings.movieTypeBadge];
    if (releaseYear != null) {
      parts.add('$releaseYear');
    }
    final cleanArtist = artist?.trim();
    if (cleanArtist != null && cleanArtist.isNotEmpty) {
      parts.add(cleanArtist);
    }
    return parts.join(AppStrings.metadataSeparator);
  }

  static String formatEpisodeRowMeta(int durationMs, String? artist) {
    final parts = <String>[];
    if (durationMs > 0) {
      final minutes = (durationMs / AppSpacing.millisecondsPerMinute).round();
      parts.add('$minutes ${AppStrings.statsMinutesShort}');
    }
    final cleanArtist = artist?.trim();
    if (cleanArtist != null && cleanArtist.isNotEmpty) {
      parts.add(cleanArtist);
    }
    return parts.join(AppStrings.metadataSeparator);
  }

  static String formatPlayerHudSubtitle(String subtitle, String? artist) {
    final cleanSub = subtitle.trim();
    final cleanArtist = artist?.trim() ?? '';
    if (cleanArtist.isEmpty) {
      return cleanSub;
    }
    if (cleanSub.isEmpty) {
      return cleanArtist;
    }
    if (cleanSub.toLowerCase().contains(cleanArtist.toLowerCase())) {
      return cleanSub;
    }
    return '$cleanSub${AppStrings.metadataSeparator}$cleanArtist';
  }

  static String episodeMediaKey(int episodeId) => 'episode_$episodeId';

  static String formatAudioTrackLabel(
    String? title,
    String? language,
    String id,
  ) {
    return title ?? language ?? '${AppStrings.playerTrackPrefix} $id';
  }

  static String formatSubtitleTrackLabel(
    String? title,
    String? language,
    String id,
  ) {
    return title ?? language ?? '${AppStrings.playerSubtitleTrackPrefix} $id';
  }

  static String formatRemainingDuration(
    Duration position,
    Duration duration,
  ) {
    final remainingMs =
        (duration.inMilliseconds - position.inMilliseconds).clamp(0, 1 << 30);
    return '-${formatPlayerDuration(Duration(milliseconds: remainingMs))}';
  }

  static String formatEstimatedFinishTime(
    Duration position,
    Duration duration,
    double playbackSpeed,
    DateTime now,
  ) {
    final remainingMs =
        (duration.inMilliseconds - position.inMilliseconds).clamp(0, 1 << 30);
    final safeSpeed = playbackSpeed > 0 ? playbackSpeed : 1.0;
    final adjustedMs = (remainingMs / safeSpeed).round();
    final finish = now.add(Duration(milliseconds: adjustedMs));
    final hh = finish.hour.toString().padLeft(2, '0');
    final mm = finish.minute.toString().padLeft(2, '0');
    return '${AppStrings.playerFinishTimePrefix} $hh:$mm';
  }

  static String formatDelayMs(int delayMs) {
    final sign = delayMs > 0 ? '+' : '';
    return '$sign$delayMs ${AppStrings.playerDelayUnitMs}';
  }

  static String formatSubtitleScale(double scale) {
    return '${scale.toStringAsFixed(1)}${AppStrings.timesSymbol}';
  }

  static String formatPlaybackSpeed(double speed) {
    final roundedHundredths = (speed * 100).round();
    final formatted = roundedHundredths % 10 != 0
        ? speed.toStringAsFixed(2)
        : speed.toStringAsFixed(1);
    return '$formatted${AppStrings.timesSymbol}';
  }

  static String formatRemainingMinutes(int minutes) {
    return '$minutes ${AppStrings.remainingMinutesSuffix}';
  }

  static String formatEpisodeRowTitle(int episodeNumber, String title) {
    return '$episodeNumber. $title';
  }

  static String formatSeriesPlayButton(EpisodeEntry? resumeEp) {
    if (resumeEp != null && resumeEp.positionMs > 0) {
      final s = resumeEp.seasonNumber.toString().padLeft(2, '0');
      final e = resumeEp.episodeNumber.toString().padLeft(2, '0');
      return '${AppStrings.resumeButton} (S${s}E$e)';
    }
    return AppStrings.playEpisodeOneButton;
  }

  static String formatSeriesWatchedProgress(int watched, int total) {
    return '$watched / $total ${AppStrings.episodesCountLabel} ${AppStrings.watchedBadge.toLowerCase()}';
  }

  static String formatHeroInfoLine(String subtitle, int remainingMinutes) {
    if (remainingMinutes > 0) {
      return '$subtitle · ${formatRemainingMinutes(remainingMinutes)}';
    }
    return subtitle;
  }

  static String formatPercent(num fractionOrPercent, {bool isFraction = true}) {
    final pct = isFraction
        ? (fractionOrPercent * 100).round()
        : fractionOrPercent.round();
    return '$pct${AppStrings.percentSymbol}';
  }

  static String formatVolumePercent(double volume) {
    return '${volume.round()}${AppStrings.percentSymbol}';
  }

  static String formatSeekOsd(int deltaSeconds) {
    final sign = deltaSeconds > 0 ? '+' : '';
    return '$sign$deltaSeconds ${AppStrings.autoNextSecondsSuffix}';
  }

  static String formatSleepTimerRemaining(Duration remaining) {
    final mins = remaining.inMinutes.clamp(1, 999);
    return '$mins ${AppStrings.statsMinutesShort}';
  }

  static String formatAspectModeLabel(VideoAspectMode mode) {
    switch (mode) {
      case VideoAspectMode.original:
        return AppStrings.aspectOriginalLabel;
      case VideoAspectMode.fillCrop:
        return AppStrings.aspectFillCropLabel;
      case VideoAspectMode.ratio16x9:
        return AppStrings.aspect16x9Label;
      case VideoAspectMode.ratio21x9:
        return AppStrings.aspect21x9Label;
    }
  }

  static String formatSleepTimerOptionLabel(SleepTimerOption option) {
    switch (option) {
      case SleepTimerOption.off:
        return AppStrings.sleepTimerOffLabel;
      case SleepTimerOption.endOfEpisode:
        return AppStrings.sleepTimerEndOfEpisodeLabel;
      case SleepTimerOption.minutes30:
        return AppStrings.sleepTimer30MinLabel;
      case SleepTimerOption.minutes60:
        return AppStrings.sleepTimer60MinLabel;
    }
  }
}
