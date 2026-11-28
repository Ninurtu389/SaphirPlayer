import 'package:path/path.dart' as p;
import '../../core/constants/app_strings.dart';
import '../../core/storage/sync_key_utils.dart';
import 'media_tag_reader_service.dart';

class ParsedEpisode {
  const ParsedEpisode({
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.filePath,
    this.syncKey = '',
    this.artist,
    this.durationMs = 0,
    this.fileSize = 0,
    this.modifiedAt = 0,
  });

  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeTitle;
  final String filePath;
  final String syncKey;
  final String? artist;
  final int durationMs;
  final int fileSize;
  final int modifiedAt;
}

class ParsedMovie {
  const ParsedMovie({
    required this.title,
    required this.releaseYear,
    required this.filePath,
    this.syncKey = '',
    this.artist,
    this.durationMs = 0,
    this.fileSize = 0,
    this.modifiedAt = 0,
  });

  final String title;
  final int? releaseYear;
  final String filePath;
  final String syncKey;
  final String? artist;
  final int durationMs;
  final int fileSize;
  final int modifiedAt;
}

class MediaParser {
  MediaParser._();

  static const Set<String> videoExtensions = {
    '.mkv',
    '.mp4',
    '.avi',
    '.mov',
    '.wmv',
    '.m4v',
    '.webm',
    '.ts',
    '.m2ts',
    '.mpg',
    '.mpeg',
    '.vob',
    '.flv',
    '.ogv',
  };

  static const Set<String> imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  static const Set<(int, int)> _excludedAspectRatios = {
    (16, 9),
    (4, 3),
    (4, 4),
    (21, 9),
  };

  static final RegExp _sxxExxPattern = RegExp(
    r'[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})',
  );

  static final RegExp _seasonEpisodeTextPattern = RegExp(
    r'(?:staffel|season)[\s._-]*(\d{1,2})[\s._\-–—:]*(?:folge|episode|ep?)[\s._-]*(\d{1,3})',
    caseSensitive: false,
  );

  static final RegExp _xPattern = RegExp(
    r'(?<![a-zA-Z0-9])(\d{1,2})x(\d{1,3})(?![a-zA-Z0-9])',
  );

  static final RegExp _dottedSeasonEpisodePattern = RegExp(
    r'^(\d{1,2})\.(\d{2,3})(?:[\s._\-–—:]+|$)',
  );

  static final RegExp _exxPattern = RegExp(
    r'(?<![a-zA-Z0-9])(?:episode|folge|ep)[\s._-]*(\d{1,3})(?![a-zA-Z0-9])',
    caseSensitive: false,
  );

  static final RegExp _leadingNumberPattern = RegExp(
    r'^(\d{1,3})(?:[\s._\-–—:]+|$)',
  );

  static final RegExp _seasonFolderPattern = RegExp(
    r'(?:^|[\s._\-\[\(])(?:staffel|season|s)[\s._-]*(\d{1,2})(?:$|[\s._\-\]\)])',
    caseSensitive: false,
  );

  static final RegExp _numericFolderPattern = RegExp(r'^\d{1,2}$');

  static final RegExp _technicalSubfolderPattern = RegExp(
    r'^(?:cd|disc|disk|dvd|part|teil|specials?|extras?|bonus)[\s._-]*\d*$',
    caseSensitive: false,
  );

  static final RegExp _yearPattern = RegExp(r'\b(19\d{2}|20\d{2})\b');

  static String buildStableSyncKey(
    String prefix,
    String filePath,
    String rootPath, {
    String? sourceId,
  }) {
    return SyncKeyUtils.buildStableSyncKey(
      prefix,
      filePath,
      rootPath,
      sourceId: sourceId,
    );
  }

  static Match? _findValidXMatch(String text) {
    for (final match in _xPattern.allMatches(text)) {
      final first = int.tryParse(match.group(1) ?? '');
      final second = int.tryParse(match.group(2) ?? '');
      if (first != null &&
          second != null &&
          !_excludedAspectRatios.contains((first, second))) {
        return match;
      }
    }
    return null;
  }

  static bool isNonSeriesSubfolder(String segment) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    return _seasonFolderPattern.hasMatch(trimmed) ||
        _numericFolderPattern.hasMatch(trimmed) ||
        _technicalSubfolderPattern.hasMatch(trimmed) ||
        _sxxExxPattern.hasMatch(trimmed) ||
        _findValidXMatch(trimmed) != null ||
        _exxPattern.hasMatch(trimmed);
  }

  static bool isVideoFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return videoExtensions.contains(ext);
  }

  static bool isImageFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return imageExtensions.contains(ext);
  }

  static ParsedEpisode? parseEpisode(
    String filePath,
    String rootFolderPath, {
    String? sourceId,
  }) {
    final baseName = p.basenameWithoutExtension(filePath);
    final relPath = p.relative(filePath, from: rootFolderPath);
    final segments = p.split(relPath);

    int? seasonNum;
    int? episodeNum;
    Match? episodeMatch;

    final sMatch = _sxxExxPattern.firstMatch(baseName);
    if (sMatch != null) {
      seasonNum = int.tryParse(sMatch.group(1) ?? '');
      episodeNum = int.tryParse(sMatch.group(2) ?? '');
      episodeMatch = sMatch;
    } else {
      final textMatch = _seasonEpisodeTextPattern.firstMatch(baseName);
      if (textMatch != null) {
        seasonNum = int.tryParse(textMatch.group(1) ?? '');
        episodeNum = int.tryParse(textMatch.group(2) ?? '');
        episodeMatch = textMatch;
      } else {
        final xMatch = _findValidXMatch(baseName);
        if (xMatch != null) {
          seasonNum = int.tryParse(xMatch.group(1) ?? '');
          episodeNum = int.tryParse(xMatch.group(2) ?? '');
          episodeMatch = xMatch;
        } else {
          final dotMatch = _dottedSeasonEpisodePattern.firstMatch(baseName);
          if (dotMatch != null) {
            seasonNum = int.tryParse(dotMatch.group(1) ?? '');
            episodeNum = int.tryParse(dotMatch.group(2) ?? '');
            episodeMatch = dotMatch;
          } else {
            final eMatch = _exxPattern.firstMatch(baseName);
            if (eMatch != null) {
              episodeNum = int.tryParse(eMatch.group(1) ?? '');
              episodeMatch = eMatch;
            }
          }
        }
      }
    }

    final folderSeason = _findSeasonFolder(segments);
    if (seasonNum == null && folderSeason != null) {
      seasonNum = folderSeason.$2;
    }

    if (episodeNum == null && folderSeason != null) {
      final leadingMatch = _leadingNumberPattern.firstMatch(baseName);
      if (leadingMatch != null) {
        episodeNum = int.tryParse(leadingMatch.group(1) ?? '');
        episodeMatch = leadingMatch;
      }
    }

    if (episodeNum == null) {
      return null;
    }

    final resolvedSeason = seasonNum ?? 1;
    final seriesTitle =
        _resolveSeriesTitle(segments, baseName, episodeMatch, folderSeason?.$1);
    final episodeTitle =
        _resolveEpisodeTitle(baseName, episodeMatch, episodeNum);

    return ParsedEpisode(
      seriesTitle: seriesTitle,
      seasonNumber: resolvedSeason,
      episodeNumber: episodeNum,
      episodeTitle: episodeTitle,
      filePath: filePath,
      syncKey: buildStableSyncKey(
        'ep',
        filePath,
        rootFolderPath,
        sourceId: sourceId,
      ),
    );
  }

  static (int, int)? _findSeasonFolder(List<String> segments) {
    for (var i = 0; i < segments.length - 1; i++) {
      final folderMatch = _seasonFolderPattern.firstMatch(segments[i]);
      if (folderMatch != null) {
        final parsed = int.tryParse(folderMatch.group(1) ?? '');
        if (parsed != null) {
          return (i, parsed);
        }
      }
    }
    if (segments.length >= 3) {
      for (var i = segments.length - 2; i >= 1; i--) {
        final trimmed = segments[i].trim();
        if (_numericFolderPattern.hasMatch(trimmed)) {
          final parsed = int.tryParse(trimmed);
          if (parsed != null) {
            return (i, parsed);
          }
        }
      }
    }
    return null;
  }

  static ParsedMovie parseMovie(
    String filePath,
    String rootFolderPath, {
    String? sourceId,
  }) {
    final baseName = p.basenameWithoutExtension(filePath);
    final relPath = p.relative(filePath, from: rootFolderPath);
    final segments = p.split(relPath);

    String rawTitle = baseName;
    if (segments.length >= 2 && _cleanTitle(segments.first).isNotEmpty) {
      final parentFolder = segments[segments.length - 2];
      if (_yearPattern.hasMatch(parentFolder)) {
        rawTitle = parentFolder;
      }
    }

    final yearMatch =
        _yearPattern.firstMatch(rawTitle) ?? _yearPattern.firstMatch(baseName);
    final releaseYear =
        yearMatch != null ? int.tryParse(yearMatch.group(1) ?? '') : null;

    var cleaned = rawTitle;
    if (yearMatch != null) {
      cleaned = cleaned.replaceAll(yearMatch.group(0)!, ' ');
    }
    cleaned = cleaned.replaceAll(RegExp(r'[\(\)\[\]]'), ' ');
    final title = _cleanTitle(cleaned);

    return ParsedMovie(
      title: title.isEmpty ? baseName : title,
      releaseYear: releaseYear,
      filePath: filePath,
      syncKey: buildStableSyncKey(
        'mv',
        filePath,
        rootFolderPath,
        sourceId: sourceId,
      ),
    );
  }

  static ParsedEpisode? parseEpisodeWithTags(
    String filePath,
    String rootFolderPath,
    EmbeddedMediaTags? tags, {
    required int fileSize,
    required int modifiedAt,
    String? sourceId,
  }) {
    final fromPath = parseEpisode(
      filePath,
      rootFolderPath,
      sourceId: sourceId,
    );
    final tagSeries = _nonEmpty(tags?.seriesTitle);
    final tagTitle = _nonEmpty(tags?.title);
    final tagArtist = _nonEmpty(tags?.artist);
    final tagSeason = tags?.seasonNumber;
    final tagEpisode = tags?.episodeNumber;
    final tagDurationMs = (tags?.durationMs != null && tags!.durationMs! > 0)
        ? tags.durationMs!
        : 0;

    final isTagEpisode = tagEpisode != null &&
        tagEpisode > 0 &&
        (tagSeries != null || tagSeason != null);

    if (fromPath == null && !isTagEpisode) {
      return null;
    }

    if (fromPath != null) {
      return ParsedEpisode(
        seriesTitle: tagSeries ?? fromPath.seriesTitle,
        seasonNumber: tagSeason ?? fromPath.seasonNumber,
        episodeNumber: (tagEpisode != null && tagEpisode > 0)
            ? tagEpisode
            : fromPath.episodeNumber,
        episodeTitle: tagTitle ?? fromPath.episodeTitle,
        filePath: filePath,
        syncKey: fromPath.syncKey,
        artist: tagArtist,
        durationMs: tagDurationMs,
        fileSize: fileSize,
        modifiedAt: modifiedAt,
      );
    }

    final baseName = p.basenameWithoutExtension(filePath);
    final relPath = p.relative(filePath, from: rootFolderPath);
    final segments = p.split(relPath);
    final folderSeason = _findSeasonFolder(segments);
    final resolvedSeason = tagSeason ?? folderSeason?.$2 ?? 1;
    final resolvedEpisode = tagEpisode!;
    final resolvedSeries = tagSeries ??
        _resolveSeriesTitle(segments, baseName, null, folderSeason?.$1);
    final cleanedBase = _cleanTitle(baseName);
    final resolvedTitle = tagTitle ??
        (cleanedBase.isNotEmpty
            ? cleanedBase
            : '${AppStrings.episodeFallbackPrefix} $resolvedEpisode');

    return ParsedEpisode(
      seriesTitle: resolvedSeries,
      seasonNumber: resolvedSeason,
      episodeNumber: resolvedEpisode,
      episodeTitle: resolvedTitle,
      filePath: filePath,
      syncKey: buildStableSyncKey(
        'ep',
        filePath,
        rootFolderPath,
        sourceId: sourceId,
      ),
      artist: tagArtist,
      durationMs: tagDurationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }

  static ParsedMovie parseMovieWithTags(
    String filePath,
    String rootFolderPath,
    EmbeddedMediaTags? tags, {
    required int fileSize,
    required int modifiedAt,
    String? sourceId,
  }) {
    final fromPath = parseMovie(
      filePath,
      rootFolderPath,
      sourceId: sourceId,
    );
    final tagTitle = _nonEmpty(tags?.title);
    final tagArtist = _nonEmpty(tags?.artist);
    final tagDurationMs = (tags?.durationMs != null && tags!.durationMs! > 0)
        ? tags.durationMs!
        : 0;

    return ParsedMovie(
      title: tagTitle ?? fromPath.title,
      releaseYear: tags?.releaseYear ?? fromPath.releaseYear,
      filePath: fromPath.filePath,
      syncKey: fromPath.syncKey,
      artist: tagArtist,
      durationMs: tagDurationMs,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  static String _resolveSeriesTitle(
    List<String> segments,
    String baseName,
    Match? episodeMatch,
    int? seasonFolderIndex,
  ) {
    final startIdx = (seasonFolderIndex != null && seasonFolderIndex >= 1)
        ? seasonFolderIndex - 1
        : segments.length - 2;
    for (var i = startIdx; i >= 0; i--) {
      final segment = segments[i];
      if (isNonSeriesSubfolder(segment)) {
        continue;
      }
      final candidate = _cleanTitle(segment);
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
    if (episodeMatch != null && episodeMatch.start > 0) {
      final beforeEpisode = baseName.substring(0, episodeMatch.start);
      final cleaned =
          _cleanTitle(beforeEpisode.replaceFirst(RegExp(r'[\s._\-–—:]+$'), ''));
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    final cleaned = _cleanTitle(baseName);
    return cleaned.isEmpty ? baseName : cleaned;
  }

  static String _resolveEpisodeTitle(
    String baseName,
    Match? match,
    int episodeNumber,
  ) {
    if (match != null && match.end < baseName.length) {
      var tail = baseName.substring(match.end);
      tail = tail.replaceFirst(RegExp(r'^[\s._\-–—:]+'), '');
      final cleaned = _cleanTitle(tail);
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    return '${AppStrings.episodeFallbackPrefix} $episodeNumber';
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'[._]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
