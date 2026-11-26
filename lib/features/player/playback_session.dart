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
}
