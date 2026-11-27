import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_strings.dart';

class TrackPreferenceResolver {
  TrackPreferenceResolver._();

  static const Map<String, List<String>> languageAliases = {
    AppStrings.subtitleLangCodeDe: ['de', 'deu', 'ger', 'german', 'deutsch'],
    AppStrings.subtitleLangCodeEn: ['en', 'eng', 'english', 'englisch'],
  };

  static bool matchesSubtitleLanguage(
    SubtitleTrack track,
    String preferredLanguage,
  ) {
    if (track.id == 'auto' || track.id == 'no') {
      return false;
    }
    final normalizedPref = preferredLanguage.trim().toLowerCase();
    if (normalizedPref.isEmpty ||
        normalizedPref == AppStrings.subtitleLangCodeAuto) {
      return true;
    }

    final aliases = languageAliases[normalizedPref] ?? [normalizedPref];
    final lang = (track.language ?? '').trim().toLowerCase();
    final title = (track.title ?? '').trim().toLowerCase();
    final tokens = <String>{
      if (lang.isNotEmpty) ...lang.split(RegExp(r'[^a-z0-9]+')),
      if (title.isNotEmpty) ...title.split(RegExp(r'[^a-z0-9]+')),
    }..removeWhere((t) => t.isEmpty);

    for (final alias in aliases) {
      if (tokens.contains(alias) || lang == alias) {
        return true;
      }
    }
    return false;
  }

  static SubtitleTrack? findPreferredSubtitleTrack(
    List<SubtitleTrack> tracks,
    String preferredLanguage,
  ) {
    final realTracks =
        tracks.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (realTracks.isEmpty) {
      return null;
    }
    final normalizedPref = preferredLanguage.trim().toLowerCase();
    if (normalizedPref == AppStrings.subtitleLangCodeAuto) {
      return realTracks.first;
    }
    for (final track in realTracks) {
      if (matchesSubtitleLanguage(track, normalizedPref)) {
        return track;
      }
    }
    return realTracks.first;
  }

  static ({AudioTrack? audio, SubtitleTrack? subtitle, bool fromSeries})
      resolve({
    required ({String? audioTrack, String? subtitleTrack, int introSkipSeconds})?
        seriesPreferences,
    required List<AudioTrack> audioTracks,
    required List<SubtitleTrack> subtitleTracks,
    required AudioTrack activeAudioTrack,
    required SubtitleTrack activeSubtitleTrack,
    required bool subtitlesEnabledByDefault,
    required String preferredSubtitleLanguage,
  }) {
    AudioTrack? targetAudio;
    SubtitleTrack? targetSubtitle;
    var fromSeries = false;

    final savedAudioId = seriesPreferences?.audioTrack;
    if (savedAudioId != null && savedAudioId.isNotEmpty) {
      for (final track in audioTracks) {
        if (track.id == savedAudioId && activeAudioTrack.id != savedAudioId) {
          targetAudio = track;
          break;
        }
      }
    }

    final savedSubtitleId = seriesPreferences?.subtitleTrack;
    if (savedSubtitleId != null && savedSubtitleId.isNotEmpty) {
      fromSeries = true;
      if (savedSubtitleId == 'no') {
        if (activeSubtitleTrack.id != 'no') {
          targetSubtitle = SubtitleTrack.no();
        }
      } else {
        for (final track in subtitleTracks) {
          if (track.id == savedSubtitleId &&
              activeSubtitleTrack.id != savedSubtitleId) {
            targetSubtitle = track;
            break;
          }
        }
      }
      return (
        audio: targetAudio,
        subtitle: targetSubtitle,
        fromSeries: fromSeries,
      );
    }

    if (!subtitlesEnabledByDefault) {
      if (activeSubtitleTrack.id != 'no') {
        targetSubtitle = SubtitleTrack.no();
      }
    } else {
      final chosen = findPreferredSubtitleTrack(
        subtitleTracks,
        preferredSubtitleLanguage,
      );
      if (chosen != null && activeSubtitleTrack.id != chosen.id) {
        targetSubtitle = chosen;
      }
    }

    return (
      audio: targetAudio,
      subtitle: targetSubtitle,
      fromSeries: fromSeries,
    );
  }
}
