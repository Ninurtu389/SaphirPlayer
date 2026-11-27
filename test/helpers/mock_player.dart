import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mocktail/mocktail.dart';
import 'package:saphir_player/features/player/player_models.dart';

class MockPlayer extends Mock implements Player {}

class MockPlayerStream extends Mock implements PlayerStream {}

class MockPlayerState extends Mock implements PlayerState {}

class MockVideoController extends Mock implements VideoController {}

class FakePlayerHarness {
  FakePlayerHarness() {
    _registerFallbacks();
    _wireMocks();
  }

  static bool _fallbacksRegistered = false;

  static void _registerFallbacks() {
    if (_fallbacksRegistered) {
      return;
    }
    registerFallbackValue(Media(''));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AudioTrack.auto());
    registerFallbackValue(SubtitleTrack.auto());
    _fallbacksRegistered = true;
  }

  final MockPlayer player = MockPlayer();
  final MockPlayerStream stream = MockPlayerStream();
  final MockPlayerState state = MockPlayerState();
  final MockVideoController videoController = MockVideoController();

  final playingController = StreamController<bool>.broadcast();
  final positionController = StreamController<Duration>.broadcast();
  final durationController = StreamController<Duration>.broadcast();
  final volumeController = StreamController<double>.broadcast();
  final tracksController = StreamController<Tracks>.broadcast();
  final trackController = StreamController<Track>.broadcast();
  final completedController = StreamController<bool>.broadcast();
  final errorController = StreamController<String>.broadcast();
  final rateController = StreamController<double>.broadcast();
  final widthController = StreamController<int?>.broadcast();
  final heightController = StreamController<int?>.broadcast();
  final playlistController = StreamController<Playlist>.broadcast();
  final bufferingController = StreamController<bool>.broadcast();
  final bufferController = StreamController<Duration>.broadcast();
  final audioParamsController = StreamController<AudioParams>.broadcast();
  final audioBitrateController = StreamController<double?>.broadcast();
  final videoParamsController = StreamController<VideoParams>.broadcast();
  final pitchController = StreamController<double>.broadcast();
  final logController = StreamController<PlayerLog>.broadcast();
  final subtitleController = StreamController<List<String>>.broadcast();

  final ValueNotifier<int?> videoIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<Rect?> videoRectNotifier = ValueNotifier<Rect?>(null);
  final ValueNotifier<PlatformVideoController?> videoNotifier =
      ValueNotifier<PlatformVideoController?>(null);
  final Completer<PlatformVideoController> videoPlatformCompleter =
      Completer<PlatformVideoController>();

  final List<Media> openedMedia = [];
  final List<Duration> seekTargets = [];
  final List<double> volumes = [];
  final List<double> rates = [];
  final List<AudioTrack> selectedAudioTracks = [];
  final List<SubtitleTrack> selectedSubtitleTracks = [];
  final List<bool> fullscreenStates = [];

  int playOrPauseCount = 0;
  int stoppedCount = 0;
  bool disposed = false;

  bool throwOnOpen = false;
  Object? openError;
  bool _currentPlaying = false;
  double _currentVolume = 100.0;
  Uint8List? screenshotBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  final List<bool> alwaysOnTopStates = [];
  final List<Rect> windowBoundsHistory = [];
  final List<Size> windowMinSizeHistory = [];
  Rect currentWindowBounds = const Rect.fromLTWH(100, 100, 1280, 800);
  String? pickedSubtitlePath;
  int dragCount = 0;

  PlayerWindowAdapter get windowAdapter => PlayerWindowAdapter(
        setFullScreen: onSetFullScreen,
        setAlwaysOnTop: (val) async => alwaysOnTopStates.add(val),
        getWindowBounds: () async => currentWindowBounds,
        setWindowBounds: (rect) async {
          currentWindowBounds = rect;
          windowBoundsHistory.add(rect);
        },
        setWindowMinimumSize: (size) async => windowMinSizeHistory.add(size),
        pickSubtitleFile: (_) async => pickedSubtitlePath,
        startWindowDragging: () async => dragCount++,
      );

  void _wireMocks() {
    when(() => player.stream).thenReturn(stream);
    when(() => player.state).thenReturn(state);
    when(() => player.platform).thenReturn(null);

    when(() => state.playing).thenAnswer((_) => _currentPlaying);
    when(() => state.completed).thenReturn(false);
    when(() => state.position).thenReturn(Duration.zero);
    when(() => state.duration).thenReturn(Duration.zero);
    when(() => state.volume).thenAnswer((_) => _currentVolume);
    when(() => state.rate).thenReturn(1.0);
    when(() => state.width).thenReturn(null);
    when(() => state.height).thenReturn(null);
    when(() => state.subtitle).thenReturn(const ['', '']);
    when(() => state.tracks).thenReturn(const Tracks());
    when(() => state.track).thenReturn(const Track());

    when(() => stream.playing).thenAnswer((_) => playingController.stream);
    when(() => stream.position).thenAnswer((_) => positionController.stream);
    when(() => stream.duration).thenAnswer((_) => durationController.stream);
    when(() => stream.volume).thenAnswer((_) => volumeController.stream);
    when(() => stream.tracks).thenAnswer((_) => tracksController.stream);
    when(() => stream.track).thenAnswer((_) => trackController.stream);
    when(() => stream.completed).thenAnswer((_) => completedController.stream);
    when(() => stream.error).thenAnswer((_) => errorController.stream);
    when(() => stream.rate).thenAnswer((_) => rateController.stream);
    when(() => stream.width).thenAnswer((_) => widthController.stream);
    when(() => stream.height).thenAnswer((_) => heightController.stream);
    when(() => stream.playlist).thenAnswer((_) => playlistController.stream);
    when(() => stream.buffering).thenAnswer((_) => bufferingController.stream);
    when(() => stream.buffer).thenAnswer((_) => bufferController.stream);
    when(() => stream.audioParams)
        .thenAnswer((_) => audioParamsController.stream);
    when(() => stream.audioBitrate)
        .thenAnswer((_) => audioBitrateController.stream);
    when(() => stream.videoParams)
        .thenAnswer((_) => videoParamsController.stream);
    when(() => stream.pitch).thenAnswer((_) => pitchController.stream);
    when(() => stream.log).thenAnswer((_) => logController.stream);
    when(() => stream.subtitle).thenAnswer((_) => subtitleController.stream);

    when(() => videoController.player).thenReturn(player);
    when(() => videoController.id).thenReturn(videoIdNotifier);
    when(() => videoController.rect).thenReturn(videoRectNotifier);
    when(() => videoController.notifier).thenReturn(videoNotifier);
    when(() => videoController.platform).thenReturn(videoPlatformCompleter);

    when(() => player.open(any(), play: any(named: 'play')))
        .thenAnswer((invocation) async {
      if (throwOnOpen) {
        throw openError ?? Exception('Unsupported codec or corrupt container');
      }
      final media = invocation.positionalArguments.first as Media;
      final play = invocation.namedArguments[#play] as bool? ?? true;
      openedMedia.add(media);
      if (play) {
        emitPlaying(true);
      }
    });

    when(() => player.play()).thenAnswer((_) async => emitPlaying(true));
    when(() => player.pause()).thenAnswer((_) async => emitPlaying(false));
    when(() => player.playOrPause()).thenAnswer((_) async {
      playOrPauseCount++;
      emitPlaying(!_currentPlaying);
    });
    when(() => player.seek(any())).thenAnswer((invocation) async {
      final target = invocation.positionalArguments.first as Duration;
      seekTargets.add(target);
      emitPosition(target);
    });
    when(() => player.setVolume(any())).thenAnswer((invocation) async {
      final vol = invocation.positionalArguments.first as double;
      _currentVolume = vol;
      volumes.add(vol);
      emitVolume(vol);
    });
    when(() => player.setRate(any())).thenAnswer((invocation) async {
      final rate = invocation.positionalArguments.first as double;
      rates.add(rate);
    });
    when(() => player.setAudioTrack(any())).thenAnswer((invocation) async {
      final track = invocation.positionalArguments.first as AudioTrack;
      selectedAudioTracks.add(track);
    });
    when(() => player.setSubtitleTrack(any())).thenAnswer((invocation) async {
      final track = invocation.positionalArguments.first as SubtitleTrack;
      selectedSubtitleTracks.add(track);
    });
    when(() => player.stop()).thenAnswer((_) async {
      stoppedCount++;
      emitPlaying(false);
    });
    when(
      () => player.screenshot(
        format: any(named: 'format'),
        includeLibassSubtitles: any(named: 'includeLibassSubtitles'),
      ),
    ).thenAnswer((_) async => screenshotBytes);
    when(() => player.dispose()).thenAnswer((_) async {
      disposed = true;
    });
  }

  Future<void> onSetFullScreen(bool fullscreen) async {
    fullscreenStates.add(fullscreen);
  }

  void emitPlaying(bool playing) {
    _currentPlaying = playing;
    if (!playingController.isClosed) {
      playingController.add(playing);
    }
  }

  void emitPosition(Duration pos) {
    if (!positionController.isClosed) {
      positionController.add(pos);
    }
  }

  void emitDuration(Duration dur) {
    if (!durationController.isClosed) {
      durationController.add(dur);
    }
  }

  void emitVolume(double vol) {
    _currentVolume = vol;
    if (!volumeController.isClosed) {
      volumeController.add(vol);
    }
  }

  void emitTracks(Tracks tracks) {
    if (!tracksController.isClosed) {
      tracksController.add(tracks);
    }
  }

  void emitTrack(Track track) {
    if (!trackController.isClosed) {
      trackController.add(track);
    }
  }

  void emitCompleted(bool completed) {
    if (!completedController.isClosed) {
      completedController.add(completed);
    }
  }

  void emitError(String message) {
    if (!errorController.isClosed) {
      errorController.add(message);
    }
  }

  Future<void> close() async {
    videoIdNotifier.dispose();
    videoRectNotifier.dispose();
    videoNotifier.dispose();
    await Future.wait([
      playingController.close(),
      positionController.close(),
      durationController.close(),
      volumeController.close(),
      tracksController.close(),
      trackController.close(),
      completedController.close(),
      errorController.close(),
      rateController.close(),
      widthController.close(),
      heightController.close(),
      playlistController.close(),
      bufferingController.close(),
      bufferController.close(),
      audioParamsController.close(),
      audioBitrateController.close(),
      videoParamsController.close(),
      pitchController.close(),
      logController.close(),
      subtitleController.close(),
    ]);
  }
}
