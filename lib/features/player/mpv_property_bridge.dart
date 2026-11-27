import 'dart:convert';
import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_strings.dart';
import 'player_models.dart';

abstract class IMpvPropertyBridge {
  Future<void> setProperty(String key, String value);
  Future<String?> getProperty(String key);
  Future<void> sendCommand(List<String> args);
  Future<void> setHardwareDecoding(bool enabled);
  Future<void> setAudioNightMode(bool enabled);
  Future<void> setVolumeMax(double maxPercent);
  Future<void> setAudioDelay(double seconds);
  Future<void> setSubtitleDelay(double seconds);
  Future<void> setSubtitleStyle({
    required double scale,
    required int pos,
    required double bgOpacity,
  });
  Future<void> setAspectMode(VideoAspectMode mode);
  Future<List<PlayerChapter>> readChapters();
  Future<PlayerDiagnostics> readDiagnostics();
}

class MpvPropertyBridge implements IMpvPropertyBridge {
  MpvPropertyBridge(this._player);

  final Player _player;

  static const String _nightModeFilter = 'lavfi=[dynaudnorm=f=150:g=15]';

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  @override
  Future<void> setProperty(String key, String value) async {
    final native = _native;
    if (native == null) {
      return;
    }
    try {
      await native.setProperty(key, value);
    } catch (_) {
      // Property write failures on unsupported/closing streams are non-fatal
    }
  }

  @override
  Future<String?> getProperty(String key) async {
    final native = _native;
    if (native == null) {
      return null;
    }
    try {
      return await native.getProperty(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> sendCommand(List<String> args) async {
    final native = _native;
    if (native == null || args.isEmpty) {
      return;
    }
    try {
      await native.command(args);
    } catch (_) {
      // Command failures during teardown or idle state are non-fatal
    }
  }

  @override
  Future<void> setHardwareDecoding(bool enabled) async {
    await setProperty('hwdec', enabled ? 'auto-safe' : 'no');
  }

  @override
  Future<void> setAudioNightMode(bool enabled) async {
    await sendCommand(['af', enabled ? 'add' : 'remove', _nightModeFilter]);
  }

  @override
  Future<void> setVolumeMax(double maxPercent) async {
    await setProperty('volume-max', maxPercent.round().toString());
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    await setProperty('audio-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    await setProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setSubtitleStyle({
    required double scale,
    required int pos,
    required double bgOpacity,
  }) async {
    final safeScale = scale.clamp(
      AppSpacing.subtitleScaleMin,
      AppSpacing.subtitleScaleMax,
    );
    final safePos = pos.clamp(
      AppSpacing.subtitlePositionMin,
      AppSpacing.subtitlePositionMax,
    );
    await setProperty('sub-scale', safeScale.toStringAsFixed(2));
    await setProperty('sub-pos', safePos.toString());
    await setProperty('sub-back-color', formatSubBackColor(bgOpacity));
  }

  static String formatSubBackColor(double bgOpacity) {
    final safeOpacity = bgOpacity.clamp(
      AppSpacing.subtitleBgOpacityMin,
      AppSpacing.subtitleBgOpacityMax,
    );
    final alpha = (safeOpacity * 255).round().clamp(0, 255);
    final alphaHex = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${alphaHex}000000';
  }

  @override
  Future<void> setAspectMode(VideoAspectMode mode) async {
    switch (mode) {
      case VideoAspectMode.original:
        await setProperty('panscan', '0');
        await setProperty('video-aspect-override', 'no');
      case VideoAspectMode.fillCrop:
        await setProperty('panscan', '1.0');
        await setProperty('video-aspect-override', 'no');
      case VideoAspectMode.ratio16x9:
        await setProperty('panscan', '0');
        await setProperty('video-aspect-override', '16:9');
      case VideoAspectMode.ratio21x9:
        await setProperty('panscan', '0');
        await setProperty('video-aspect-override', '21:9');
    }
  }

  @override
  Future<List<PlayerChapter>> readChapters() async {
    final raw = await getProperty('chapter-list');
    return parseChaptersJson(raw);
  }

  static List<PlayerChapter> parseChaptersJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final chapters = <PlayerChapter>[];
      for (var i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is! Map) {
          continue;
        }
        final timeVal = item['time'];
        final seconds = timeVal is num
            ? timeVal.toDouble()
            : double.tryParse(timeVal?.toString() ?? '');
        if (seconds == null || seconds.isNaN || seconds < 0) {
          continue;
        }
        final rawTitle = (item['title'] as String?)?.trim() ?? '';
        final title = rawTitle.isNotEmpty
            ? rawTitle
            : '${AppStrings.playerChapterPrefix} ${chapters.length + 1}';
        chapters.add(
          PlayerChapter(
            index: chapters.length,
            title: title,
            startMs: (seconds * AppSpacing.millisecondsPerSecond).round(),
          ),
        );
      }
      return chapters;
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<PlayerDiagnostics> readDiagnostics() async {
    final results = await Future.wait([
      getProperty('video-codec'),
      getProperty('audio-codec-name'),
      getProperty('video-params/w'),
      getProperty('video-params/h'),
      getProperty('estimated-vf-fps'),
      getProperty('hwdec-current'),
    ]);
    return parseDiagnosticsValues(
      videoCodec: results[0],
      audioCodec: results[1],
      widthRaw: results[2],
      heightRaw: results[3],
      fpsRaw: results[4],
      hwdec: results[5],
    );
  }

  static PlayerDiagnostics parseDiagnosticsValues({
    String? videoCodec,
    String? audioCodec,
    String? widthRaw,
    String? heightRaw,
    String? fpsRaw,
    String? hwdec,
  }) {
    final w = int.tryParse((widthRaw ?? '').trim());
    final h = int.tryParse((heightRaw ?? '').trim());
    final resolution = (w != null && h != null && w > 0 && h > 0)
        ? '${w}x$h'
        : AppStrings.diagUnknownValue;

    final fpsNum = double.tryParse((fpsRaw ?? '').trim());
    final fps = (fpsNum != null && fpsNum > 0)
        ? fpsNum.toStringAsFixed(1)
        : AppStrings.diagUnknownValue;

    String normalize(String? val) {
      final trimmed = val?.trim() ?? '';
      return trimmed.isEmpty ? AppStrings.diagUnknownValue : trimmed;
    }

    return PlayerDiagnostics(
      videoCodec: normalize(videoCodec),
      audioCodec: normalize(audioCodec),
      resolution: resolution,
      fps: fps,
      hwdec: normalize(hwdec),
    );
  }
}
