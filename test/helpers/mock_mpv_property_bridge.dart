import 'package:saphir_player/features/player/mpv_property_bridge.dart';
import 'package:saphir_player/features/player/player_models.dart';

class MockMpvPropertyBridge implements IMpvPropertyBridge {
  final Map<String, String> properties = {};
  final List<List<String>> commands = [];
  final List<bool> hwdecHistory = [];
  final List<bool> nightModeHistory = [];
  final List<double> volumeMaxHistory = [];
  final List<double> audioDelayHistory = [];
  final List<double> subtitleDelayHistory = [];
  final List<({double scale, int pos, double bgOpacity})> subtitleStyleHistory =
      [];
  final List<VideoAspectMode> aspectModeHistory = [];

  List<PlayerChapter> chaptersToReturn = const [];
  PlayerDiagnostics diagnosticsToReturn = const PlayerDiagnostics(
    videoCodec: 'h264',
    audioCodec: 'aac',
    resolution: '1920x1080',
    fps: '24.0',
    hwdec: 'd3d11va',
  );
  int readDiagnosticsCount = 0;

  @override
  Future<void> setProperty(String key, String value) async {
    properties[key] = value;
  }

  @override
  Future<String?> getProperty(String key) async => properties[key];

  @override
  Future<void> sendCommand(List<String> args) async {
    commands.add(List<String>.from(args));
  }

  @override
  Future<void> setHardwareDecoding(bool enabled) async {
    hwdecHistory.add(enabled);
    await setProperty('hwdec', enabled ? 'auto-safe' : 'no');
  }

  @override
  Future<void> setAudioNightMode(bool enabled) async {
    nightModeHistory.add(enabled);
    await sendCommand([
      'af',
      enabled ? 'add' : 'remove',
      'lavfi=[dynaudnorm=f=150:g=15]',
    ]);
  }

  @override
  Future<void> setVolumeMax(double maxPercent) async {
    volumeMaxHistory.add(maxPercent);
    await setProperty('volume-max', maxPercent.round().toString());
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    audioDelayHistory.add(seconds);
    await setProperty('audio-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    subtitleDelayHistory.add(seconds);
    await setProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setSubtitleStyle({
    required double scale,
    required int pos,
    required double bgOpacity,
  }) async {
    subtitleStyleHistory.add((scale: scale, pos: pos, bgOpacity: bgOpacity));
    await setProperty('sub-scale', scale.toStringAsFixed(2));
    await setProperty('sub-pos', pos.toString());
    await setProperty(
      'sub-back-color',
      MpvPropertyBridge.formatSubBackColor(bgOpacity),
    );
  }

  @override
  Future<void> setAspectMode(VideoAspectMode mode) async {
    aspectModeHistory.add(mode);
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
  Future<List<PlayerChapter>> readChapters() async => chaptersToReturn;

  @override
  Future<PlayerDiagnostics> readDiagnostics() async {
    readDiagnosticsCount++;
    return diagnosticsToReturn;
  }
}
