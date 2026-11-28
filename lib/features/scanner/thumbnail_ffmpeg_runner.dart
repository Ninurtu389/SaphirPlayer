import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/constants/app_spacing.dart';
import 'thumbnail_cache_key.dart';

/// Kapselt externe FFmpeg- und FFprobe-Prozesse für die Thumbnail-Erzeugung.
class ThumbnailFfmpegRunner {
  ThumbnailFfmpegRunner._();

  static bool _ffmpegResolved = false;
  static String? _cachedFfmpegExe;
  static bool _ffprobeResolved = false;
  static String? _cachedFfprobeExe;
  static final Set<Process> _activeProcesses = <Process>{};

  static void killActiveProcesses() {
    for (final process in _activeProcesses.toList()) {
      try {
        process.kill();
      } catch (_) {}
    }
    _activeProcesses.clear();
  }

  static void resetExecutableCache() {
    _ffmpegResolved = false;
    _cachedFfmpegExe = null;
    _ffprobeResolved = false;
    _cachedFfprobeExe = null;
  }

  static Future<bool> tryGenerate({
    required String videoFilePath,
    required int seekSeconds,
    required String outputPath,
    required bool Function() isPlaybackActive,
  }) async {
    if (isPlaybackActive()) return false;
    final ffmpegExe = await _resolveFfmpeg();
    if (ffmpegExe == null || isPlaybackActive()) return false;

    Process? process;
    try {
      process = await Process.start(
        ffmpegExe,
        [
          '-y',
          '-ss',
          seekSeconds.toString(),
          '-i',
          videoFilePath,
          '-frames:v',
          '1',
          '-vf',
          'scale=${AppSpacing.thumbWidth.toInt()}:${AppSpacing.thumbHeight.toInt()}:force_original_aspect_ratio=decrease,pad=${AppSpacing.thumbWidth.toInt()}:${AppSpacing.thumbHeight.toInt()}:(ow-iw)/2:(oh-ih)/2:black',
          '-q:v',
          '5',
          outputPath,
        ],
        runInShell: false,
      );
      _activeProcesses.add(process);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());

      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.ffmpegTimeoutSeconds),
      );
      final outFile = File(outputPath);
      if (exitCode == 0 &&
          !isPlaybackActive() &&
          await ThumbnailCacheKey.isValidImageFile(outFile)) {
        return true;
      }
      await deleteIfExists(outFile);
      return false;
    } on TimeoutException {
      process?.kill();
      await deleteIfExists(File(outputPath));
      return false;
    } on ProcessException {
      return false;
    } finally {
      if (process != null) _activeProcesses.remove(process);
    }
  }

  static Future<int?> probeDurationMs(String videoFilePath) async {
    final ffprobeExe = await _resolveFfprobe();
    if (ffprobeExe == null) return null;

    Process? process;
    try {
      process = await Process.start(
        ffprobeExe,
        [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          videoFilePath,
        ],
        runInShell: false,
      );
      _activeProcesses.add(process);
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      unawaited(process.stderr.drain<void>());
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: AppSpacing.ffmpegTimeoutSeconds),
      );
      if (exitCode != 0) return null;
      final seconds = double.tryParse((await stdoutFuture).trim());
      if (seconds != null && seconds > 0 && seconds.isFinite) {
        return (seconds * AppSpacing.millisecondsPerSecond).round();
      }
      return null;
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    } finally {
      if (process != null) _activeProcesses.remove(process);
    }
  }

  static Future<void> deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Unvollständige Cache-Datei ignorieren
    }
  }

  static Future<String?> _resolveFfmpeg() async {
    if (_ffmpegResolved) return _cachedFfmpegExe;
    _cachedFfmpegExe = await _probeExecutable('ffmpeg', 'ffmpeg.exe');
    _ffmpegResolved = true;
    return _cachedFfmpegExe;
  }

  static Future<String?> _resolveFfprobe() async {
    if (_ffprobeResolved) return _cachedFfprobeExe;
    _cachedFfprobeExe = await _probeExecutable('ffprobe', 'ffprobe.exe');
    _ffprobeResolved = true;
    return _cachedFfprobeExe;
  }

  static Future<String?> _probeExecutable(
    String command,
    String winName,
  ) async {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final localExe = File(p.join(exeDir, winName));
    if (localExe.existsSync()) return localExe.path;

    Process? process;
    try {
      process = await Process.start(
        command,
        const ['-version'],
        runInShell: false,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      final code = await process.exitCode.timeout(const Duration(seconds: 2));
      return code == 0 ? command : null;
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    }
  }
}
