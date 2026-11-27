import '../../core/utils/formatters.dart';
import '../library/library_models.dart';

class PlaybackQueueEntry {
  const PlaybackQueueEntry({
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    required this.subtitle,
    required this.filePath,
    required this.seriesId,
    required this.startPositionMs,
  });

  final String mediaKey;
  final String mediaType;
  final String title;
  final String subtitle;
  final String filePath;
  final int? seriesId;
  final int startPositionMs;
}

class PlaybackSession {
  const PlaybackSession({
    required this.queue,
    required this.initialIndex,
  });

  final List<PlaybackQueueEntry> queue;
  final int initialIndex;

  static PlaybackSession fromEpisodes({
    required String seriesTitle,
    required List<EpisodeEntry> episodes,
    required int startIndex,
  }) {
    final queue = episodes
        .map(
          (ep) => PlaybackQueueEntry(
            mediaKey: ep.mediaKey,
            mediaType: 'episode',
            title: seriesTitle,
            subtitle: Formatters.formatEpisodeSubtitle(
              ep.seasonNumber,
              ep.episodeNumber,
              ep.title,
            ),
            filePath: ep.filePath,
            seriesId: ep.seriesId,
            startPositionMs: ep.isCompleted ? 0 : ep.positionMs,
          ),
        )
        .toList();

    return PlaybackSession(queue: queue, initialIndex: startIndex);
  }
}
