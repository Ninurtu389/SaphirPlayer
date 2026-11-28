import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_strings.dart';
import '../../core/controllers/settings_controller.dart';
import 'playback_persistence_service.dart';
import 'playback_session.dart';
import 'player_models.dart';
import 'player_overlays_controller.dart';
import 'track_preference_models.dart';
import 'track_preference_resolver.dart';

class PlayerTracksDelegate {
  PlayerTracksDelegate({
    required Player player,
    required PlaybackPersistenceService persistence,
    required PlayerOverlaysController overlays,
    required SettingsController? settingsController,
    required void Function(int seconds) onIntroSkipSecondsLoaded,
    required VoidCallback onChanged,
  })  : _player = player,
        _persistence = persistence,
        _overlays = overlays,
        _settingsController = settingsController,
        _onIntroSkipSecondsLoaded = onIntroSkipSecondsLoaded,
        _onChanged = onChanged;

  final Player _player;
  final PlaybackPersistenceService _persistence;
  final PlayerOverlaysController _overlays;
  final SettingsController? _settingsController;
  final void Function(int seconds) _onIntroSkipSecondsLoaded;
  final VoidCallback _onChanged;

  List<AudioTrack> audioTracks = const [];
  List<SubtitleTrack> subtitleTracks = const [];
  AudioTrack activeAudioTrack = AudioTrack.auto();
  SubtitleTrack activeSubtitleTrack = SubtitleTrack.auto();

  void resetForEntry() {
    audioTracks = const [];
    subtitleTracks = const [];
    activeAudioTrack = AudioTrack.auto();
    activeSubtitleTrack = SubtitleTrack.auto();
  }

  void onAvailableTracksChanged(
    Tracks tracks, {
    required PlaybackQueueEntry? entry,
    required bool Function() isStale,
  }) {
    audioTracks = tracks.audio;
    subtitleTracks = tracks.subtitle;
    unawaited(_applyTrackPreferences(entry: entry, isStale: isStale));
    _onChanged();
  }

  void onActiveTrackChanged(Track track) {
    activeAudioTrack = track.audio;
    activeSubtitleTrack = track.subtitle;
    _onChanged();
  }

  void setExternalSubtitleActive(SubtitleTrack track) {
    activeSubtitleTrack = track;
    _onChanged();
  }

  Future<void> _applyTrackPreferences({
    required PlaybackQueueEntry? entry,
    required bool Function() isStale,
  }) async {
    final sid = entry?.seriesId;
    final prefs =
        sid != null ? _persistence.loadSeriesTrackPreferences(sid) : null;
    if (prefs != null) {
      _onIntroSkipSecondsLoaded(prefs.introSkipSeconds);
    }
    final resolved = TrackPreferenceResolver.resolve(
      seriesPreferences: prefs,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      activeAudioTrack: activeAudioTrack,
      activeSubtitleTrack: activeSubtitleTrack,
      subtitlesEnabledByDefault:
          _settingsController?.subtitlesEnabledByDefault ?? false,
      preferredSubtitleLanguage:
          _settingsController?.preferredSubtitleLanguage ??
              AppStrings.subtitleLangCodeDe,
    );
    if (resolved.audio != null) {
      try {
        await _player.setAudioTrack(resolved.audio!);
        if (isStale()) return;
      } catch (_) {
        // Automatisches Fallback ignoriert einen nicht anwendbaren Track still
      }
    }
    if (resolved.subtitle != null) {
      try {
        await _player.setSubtitleTrack(resolved.subtitle!);
      } catch (_) {
        // Automatisches Fallback ignoriert einen nicht anwendbaren Track still
      }
    }
  }

  Future<void> selectAudioTrack(
    AudioTrack track, {
    required PlaybackQueueEntry? entry,
    required bool Function() isStale,
  }) async {
    try {
      await _player.setAudioTrack(track);
    } catch (_) {
      if (!isStale()) {
        _overlays.showActionOsd(
          PlayerActionOsdKind.error,
          AppStrings.playerAudioTrackSwitchFailedOsd,
        );
      }
      return;
    }
    if (isStale()) return;
    activeAudioTrack = track;
    final seriesId = entry?.seriesId;
    if (seriesId != null) {
      _persistence.saveSeriesTrackPreferences(
        seriesId,
        audio: TrackPreferenceDescriptor.fromAudioTrack(track),
      );
    }
    _onChanged();
  }

  Future<void> selectSubtitleTrack(
    SubtitleTrack track, {
    required PlaybackQueueEntry? entry,
    required bool Function() isStale,
  }) async {
    try {
      await _player.setSubtitleTrack(track);
    } catch (_) {
      if (!isStale()) {
        _overlays.showActionOsd(
          PlayerActionOsdKind.error,
          AppStrings.playerSubtitleTrackSwitchFailedOsd,
        );
      }
      return;
    }
    if (isStale()) return;
    activeSubtitleTrack = track;
    final seriesId = entry?.seriesId;
    if (seriesId != null) {
      _persistence.saveSeriesTrackPreferences(
        seriesId,
        subtitle: TrackPreferenceDescriptor.fromSubtitleTrack(track),
      );
    }
    _onChanged();
  }
}
