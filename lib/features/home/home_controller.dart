import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/desktop_platform_service.dart';
import '../../core/storage/database_service.dart';
import '../library/library_models.dart';
import '../library/media_repository.dart';
import '../player/playback_session.dart';

class HomeController extends ChangeNotifier {
  HomeController(
    DatabaseService databaseService, {
    MediaRepository? repository,
  }) : _repository = repository ?? MediaRepository(databaseService);

  final MediaRepository _repository;
  final Random _random = Random();

  List<MediaCardItem> _continueWatching = const [];
  List<MediaCardItem> _rediscoverItems = const [];
  List<MediaCardItem> _recentlyAdded = const [];
  List<MediaCardItem> _seriesItems = const [];
  List<MediaCardItem> _movieItems = const [];
  MediaCardItem? _heroItem;
  String _searchQuery = '';

  List<MediaCardItem> get continueWatching => _filter(_continueWatching);
  List<MediaCardItem> get rediscoverItems => _filter(_rediscoverItems);
  List<MediaCardItem> get recentlyAdded => _filter(_recentlyAdded);
  List<MediaCardItem> get seriesItems => _filter(_seriesItems);
  List<MediaCardItem> get movieItems => _filter(_movieItems);
  MediaCardItem? get heroItem => _searchQuery.isNotEmpty ? null : _heroItem;
  String get searchQuery => _searchQuery;

  void updateSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  List<MediaCardItem> _filter(List<MediaCardItem> source) {
    if (_searchQuery.isEmpty) {
      return source;
    }
    return source
        .where(
          (item) =>
              item.title.toLowerCase().contains(_searchQuery) ||
              item.subtitle.toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  void refreshHomeFeeds() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final staleCutoffMs =
        nowMs - (AppSpacing.staleDaysDefault * AppSpacing.millisecondsPerDay);

    _continueWatching = _repository.loadContinueWatching();
    _rediscoverItems = _repository.loadRediscoverItems(staleCutoffMs);
    _recentlyAdded = _repository.loadRecentlyAdded();
    _heroItem = _continueWatching.isNotEmpty
        ? _continueWatching.first
        : (_recentlyAdded.isNotEmpty ? _recentlyAdded.first : null);
    _seriesItems = _repository.loadAllSeries(useWatchedFraction: false);
    _movieItems = _repository.loadAllMovies();

    notifyListeners();
  }

  int getMovieResumePositionMs(String mediaKey) =>
      _repository.loadResumePositionMs(mediaKey);

  MediaCardItem? pickRandomItem() {
    final pool = <MediaCardItem>[
      ..._rediscoverItems,
      ..._recentlyAdded,
      ..._movieItems,
    ];
    if (pool.isEmpty) {
      return null;
    }
    return pool[_random.nextInt(pool.length)];
  }

  SeriesDetailData? loadSeriesDetail(int seriesId) =>
      _repository.loadSeriesDetail(seriesId);

  void toggleEpisodeWatchedLocal(EpisodeEntry episode) =>
      toggleEpisodeWatched(episode, DesktopPlatformService.localHostname);

  void removeFromContinueWatching(MediaCardItem item, {String? deviceName}) {
    _repository.removeFromContinueWatching(
      item.mediaKey,
      deviceName ?? DesktopPlatformService.localHostname,
    );
    refreshHomeFeeds();
  }

  PlaybackSession buildSessionForCard(MediaCardItem item) {
    if (item.seriesId != null) {
      final detail = loadSeriesDetail(item.seriesId!);
      if (detail != null) {
        final flat = [for (final s in detail.seasons) ...s.episodes];
        if (flat.isNotEmpty) {
          var idx = -1;
          if (item.mediaType == 'series') {
            final resumeEp = detail.nextResumeEpisode;
            if (resumeEp != null) {
              idx = flat.indexWhere((e) => e.id == resumeEp.id);
            }
          } else {
            idx = flat.indexWhere((e) => e.filePath == item.filePath);
            if (idx < 0) {
              final resumeEp = detail.nextResumeEpisode;
              if (resumeEp != null) {
                idx = flat.indexWhere((e) => e.id == resumeEp.id);
              }
            }
          }
          return PlaybackSession.fromEpisodes(
            seriesTitle: detail.title,
            episodes: flat,
            startIndex: idx >= 0 ? idx : 0,
          );
        }
      }
    }
    return PlaybackSession(
      queue: [
        PlaybackQueueEntry(
          mediaKey: item.mediaKey,
          mediaType: item.mediaType,
          title: item.title,
          subtitle: item.subtitle,
          filePath: item.filePath,
          seriesId: item.seriesId,
          startPositionMs: item.mediaType == 'movie'
              ? getMovieResumePositionMs(item.mediaKey)
              : 0,
        ),
      ],
      initialIndex: 0,
    );
  }

  PlaybackSession buildSessionForEpisode(
    SeriesDetailData detail,
    EpisodeEntry selectedEpisode,
  ) {
    final flat = [for (final s in detail.seasons) ...s.episodes];
    final idx = flat.indexWhere((e) => e.id == selectedEpisode.id);
    return PlaybackSession.fromEpisodes(
      seriesTitle: detail.title,
      episodes: flat,
      startIndex: idx >= 0 ? idx : 0,
    );
  }

  void toggleEpisodeWatched(EpisodeEntry episode, String deviceName) {
    _repository.toggleEpisodeWatched(episode, deviceName);
    refreshHomeFeeds();
  }
}
