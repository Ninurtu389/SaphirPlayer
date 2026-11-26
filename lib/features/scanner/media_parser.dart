import 'package:path/path.dart' as p;

class ParsedEpisode {
  const ParsedEpisode({
    required this.seriesTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.filePath,
  });

  final String seriesTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeTitle;
  final String filePath;
}

class ParsedMovie {
  const ParsedMovie({
    required this.title,
    required this.releaseYear,
    required this.filePath,
  });

  final String title;
  final int? releaseYear;
  final String filePath;
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
  };

  static const Set<String> imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  static final RegExp _sxxExxPattern = RegExp(
    r'[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})',
  );

  static final RegExp _xPattern = RegExp(
    r'(?<![a-zA-Z0-9])(\d{1,2})x(\d{1,3})(?![a-zA-Z0-9])',
  );

  static final RegExp _exxPattern = RegExp(
    r'\b[Ee][Pp]?[\s._-]*(\d{1,3})\b',
  );

  static final RegExp _seasonFolderPattern = RegExp(
    r'(?:staffel|season|s)[\s._-]*(\d{1,2})',
    caseSensitive: false,
  );

  static final RegExp _yearPattern = RegExp(r'\b(19\d{2}|20\d{2})\b');

  static bool isVideoFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return videoExtensions.contains(ext);
  }

  static bool isImageFile(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return imageExtensions.contains(ext);
  }

  static ParsedEpisode? parseEpisode(String filePath, String rootFolderPath) {
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
      final xMatch = _xPattern.firstMatch(baseName);
      if (xMatch != null) {
        seasonNum = int.tryParse(xMatch.group(1) ?? '');
        episodeNum = int.tryParse(xMatch.group(2) ?? '');
        episodeMatch = xMatch;
      } else {
        final eMatch = _exxPattern.firstMatch(baseName);
        if (eMatch != null) {
          episodeNum = int.tryParse(eMatch.group(1) ?? '');
          episodeMatch = eMatch;
        }
      }
    }

    if (episodeNum == null) {
      return null;
    }

    if (seasonNum == null) {
      for (final segment in segments) {
        final folderMatch = _seasonFolderPattern.firstMatch(segment);
        if (folderMatch != null) {
          seasonNum = int.tryParse(folderMatch.group(1) ?? '');
          if (seasonNum != null) {
            break;
          }
        }
      }
    }

    final resolvedSeason = seasonNum ?? 1;
    final seriesTitle = _resolveSeriesTitle(segments, baseName);
    final episodeTitle =
        _resolveEpisodeTitle(baseName, episodeMatch, episodeNum);

    return ParsedEpisode(
      seriesTitle: seriesTitle,
      seasonNumber: resolvedSeason,
      episodeNumber: episodeNum,
      episodeTitle: episodeTitle,
      filePath: filePath,
    );
  }

  static ParsedMovie parseMovie(String filePath, String rootFolderPath) {
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
    );
  }

  static String _resolveSeriesTitle(List<String> segments, String baseName) {
    if (segments.length >= 3) {
      final candidate = _cleanTitle(segments[0]);
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }
    if (segments.length == 2) {
      final folder = segments[0];
      if (!_seasonFolderPattern.hasMatch(folder)) {
        final candidate = _cleanTitle(folder);
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
    }
    final beforeEpisode = baseName.split(_sxxExxPattern).first;
    final cleaned = _cleanTitle(beforeEpisode);
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
    return 'Folge $episodeNumber';
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'[._]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
