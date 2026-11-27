import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import 'mkv_ebml_tag_parser.dart';

class EmbeddedMediaTags {
  const EmbeddedMediaTags({
    this.title,
    this.seriesTitle,
    this.artist,
    this.seasonNumber,
    this.episodeNumber,
    this.releaseYear,
    this.summary,
    this.durationMs,
  });

  final String? title;
  final String? seriesTitle;
  final String? artist;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? releaseYear;
  final String? summary;
  final int? durationMs;

  bool get hasAnyMetadata =>
      _hasText(title) ||
      _hasText(seriesTitle) ||
      _hasText(artist) ||
      _hasText(summary) ||
      seasonNumber != null ||
      episodeNumber != null ||
      releaseYear != null ||
      (durationMs ?? 0) > 0;

  static bool _hasText(String? v) => v != null && v.trim().isNotEmpty;
}

class MediaTagReaderService {
  MediaTagReaderService._();

  static bool _ffprobeResolved = false;
  static String? _cachedFfprobeExe;

  static final RegExp _yearRegex = RegExp(r'(?<!\d)(19\d{2}|20\d{2})(?!\d)');
  static final RegExp _sxxExxTagRegex =
      RegExp(r'[Ss]\d{1,2}[\s._-]*[Ee](\d{1,3})');
  static final RegExp _intRegex = RegExp(r'(\d+)');

  @visibleForTesting
  static void resetExecutableCacheForTesting() {
    _ffprobeResolved = false;
    _cachedFfprobeExe = null;
  }

  static Future<EmbeddedMediaTags?> readTags(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync() || file.lengthSync() <= 0) {
        return null;
      }
    } on FileSystemException {
      return null;
    }

    final ffprobeTags = await _readWithFfprobe(filePath);
    if (ffprobeTags != null && ffprobeTags.hasAnyMetadata) {
      return ffprobeTags;
    }

    if (p.extension(filePath).toLowerCase() == '.mkv') {
      final mkvTags = readMkvTags(filePath);
      if (mkvTags != null && mkvTags.hasAnyMetadata) {
        return mkvTags;
      }
    }
    return null;
  }

  static Future<String?> _resolveFfprobeExecutable() async {
    if (_ffprobeResolved) {
      return _cachedFfprobeExe;
    }
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final name in ['ffprobe.exe', 'ffprobe']) {
      final localExe = File(p.join(exeDir, name));
      if (localExe.existsSync()) {
        _cachedFfprobeExe = localExe.path;
        _ffprobeResolved = true;
        return _cachedFfprobeExe;
      }
    }
    Process? process;
    try {
      process = await Process.start(
        'ffprobe',
        const ['-version'],
        runInShell: false,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      final code = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.executableProbeTimeoutSeconds),
      );
      _cachedFfprobeExe = code == 0 ? 'ffprobe' : null;
    } on TimeoutException {
      process?.kill();
      _cachedFfprobeExe = null;
    } on ProcessException {
      _cachedFfprobeExe = null;
    }
    _ffprobeResolved = true;
    return _cachedFfprobeExe;
  }

  static Future<EmbeddedMediaTags?> _readWithFfprobe(String filePath) async {
    final ffprobeExe = await _resolveFfprobeExecutable();
    if (ffprobeExe == null) {
      return null;
    }
    Process? process;
    try {
      process = await Process.start(
        ffprobeExe,
        ['-v', 'quiet', '-print_format', 'json', '-show_format', filePath],
        runInShell: false,
      );
      final stdoutFuture =
          process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
      unawaited(process.stderr.drain<void>());
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.ffprobeTimeoutSeconds),
      );
      if (exitCode != 0) {
        return null;
      }
      return parseFfprobeJson(await stdoutFuture);
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    }
  }

  static EmbeddedMediaTags? parseFfprobeJson(String rawJson) {
    if (rawJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final format = decoded['format'];
      if (format is! Map<String, dynamic>) {
        return null;
      }
      int? durationMs;
      final rawDuration = format['duration'];
      final seconds = rawDuration is num
          ? rawDuration.toDouble()
          : (rawDuration is String ? double.tryParse(rawDuration.trim()) : null);
      if (seconds != null && seconds > 0 && seconds.isFinite) {
        durationMs = (seconds * AppSpacing.millisecondsPerSecond).round();
      }
      final tagMap = <String, String>{};
      final rawTags = format['tags'];
      if (rawTags is Map) {
        for (final entry in rawTags.entries) {
          final k = entry.key?.toString() ?? '';
          final v = entry.value?.toString() ?? '';
          if (k.trim().isNotEmpty && v.trim().isNotEmpty) {
            tagMap[k] = v;
          }
        }
      }
      return mapRawTags(tagMap, durationMs: durationMs);
    } on FormatException {
      return null;
    }
  }

  static EmbeddedMediaTags? readMkvTags(String filePath) {
    final extracted = MkvEbmlTagParser.readFile(filePath);
    if (extracted == null) return null;
    return mapRawTags(extracted.tags, durationMs: extracted.durationMs);
  }

  static EmbeddedMediaTags? parseMkvBytes(Uint8List bytes) {
    final extracted = MkvEbmlTagParser.parseBytes(bytes);
    if (extracted == null) return null;
    return mapRawTags(extracted.tags, durationMs: extracted.durationMs);
  }

  static EmbeddedMediaTags? mapRawTags(
    Map<String, String> rawTags, {
    int? durationMs,
  }) {
    final normalized = <String, String>{};
    for (final entry in rawTags.entries) {
      final key = entry.key.trim().toLowerCase();
      final val = entry.value.trim();
      if (key.isNotEmpty && val.isNotEmpty) {
        normalized.putIfAbsent(key, () => val);
      }
    }

    final title = _firstValue(normalized, const ['title']);
    final artist = _firstValue(
      normalized,
      const ['artist', 'album_artist', 'performer', 'director', 'author'],
    );
    final seasonNumber = _parseSeasonInt(
      _firstValue(normalized, const ['season', 'season_number', 'tvseason']),
    );
    final episodeNumber = _parseEpisodeInt(
      _firstValue(
        normalized,
        const ['episode', 'episode_sort', 'episode_id', 'part_number', 'track'],
      ),
    );
    var seriesTitle =
        _firstValue(normalized, const ['show', 'tvshow', 'series']);
    if (seriesTitle == null &&
        (seasonNumber != null || episodeNumber != null)) {
      seriesTitle = _firstValue(normalized, const ['album']);
    }
    final releaseYear = _parseYear(
      _firstValue(
        normalized,
        const ['date_released', 'year', 'date', 'creation_time'],
      ),
    );
    final rawSummary = _firstValue(
      normalized,
      const ['description', 'synopsis', 'comment', 'summary'],
    );
    final summary = rawSummary?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final safeDuration =
        (durationMs != null && durationMs > 0) ? durationMs : null;

    final result = EmbeddedMediaTags(
      title: title,
      seriesTitle: seriesTitle,
      artist: artist,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      releaseYear: releaseYear,
      summary: (summary != null && summary.isNotEmpty) ? summary : null,
      durationMs: safeDuration,
    );
    return result.hasAnyMetadata ? result : null;
  }

  static String? _firstValue(Map<String, String> map, List<String> keys) {
    for (final key in keys) {
      final val = map[key];
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    }
    return null;
  }

  static int? _parseSeasonInt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final head = raw.split('/').first.trim();
    final match = _intRegex.firstMatch(head);
    if (match == null) return null;
    final parsed = int.tryParse(match.group(1)!);
    return (parsed != null && parsed >= 0) ? parsed : null;
  }

  static int? _parseEpisodeInt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final head = raw.split('/').first.trim();
    final seMatch = _sxxExxTagRegex.firstMatch(head);
    if (seMatch != null) {
      final parsed = int.tryParse(seMatch.group(1)!);
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    final match = _intRegex.firstMatch(head);
    if (match == null) return null;
    final parsed = int.tryParse(match.group(1)!);
    return (parsed != null && parsed > 0) ? parsed : null;
  }

  static int? _parseYear(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = _yearRegex.firstMatch(raw);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
