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
    String title,
  ) {
    return 'S${seasonNumber}E$episodeNumber · $title';
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
}
