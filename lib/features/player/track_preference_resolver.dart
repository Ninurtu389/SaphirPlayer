import 'package:media_kit/media_kit.dart';
import '../../core/constants/app_strings.dart';
import 'track_preference_models.dart';

class TrackPreferenceResolver {
  TrackPreferenceResolver._();

  static final RegExp _commentaryPattern = RegExp(
    r'\b(?:commentary|kommentar|directors?)\b',
    caseSensitive: false,
  );
  static final RegExp _forcedPattern = RegExp(
    r'\b(?:forced|erzwungen)\b',
    caseSensitive: false,
  );

  static bool matchesSubtitleLanguage(
    SubtitleTrack track,
    String preferredLanguage,
  ) {
    if (track.id == 'auto' || track.id == 'no') {
      return false;
    }
    final normalizedPref = normalizeTrackLanguageKey(preferredLanguage);
    if (normalizedPref == null ||
        normalizedPref == AppStrings.subtitleLangCodeAuto) {
      return true;
    }
    final candidateLang = inferTrackLanguageKey(
      language: track.language,
      title: track.title,
      id: track.id,
    );
    return candidateLang == normalizedPref;
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
    final normalizedPref = normalizeTrackLanguageKey(preferredLanguage);
    if (normalizedPref == null ||
        normalizedPref == AppStrings.subtitleLangCodeAuto) {
      final defaultTrack = realTracks.where((t) => t.isDefault == true);
      return defaultTrack.isNotEmpty ? defaultTrack.first : realTracks.first;
    }
    final matches = realTracks
        .where((t) => matchesSubtitleLanguage(t, normalizedPref))
        .toList();
    if (matches.isNotEmpty) {
      final nonForced = matches.where(
        (t) => !_forcedPattern.hasMatch(t.title ?? ''),
      );
      if (nonForced.isNotEmpty) {
        return nonForced.first;
      }
      return matches.first;
    }
    return realTracks.first;
  }

  static int scoreCandidate({
    required TrackPreferenceDescriptor descriptor,
    required String trackId,
    required String? language,
    required String? title,
    required String? codec,
    required String? channels,
    required bool isExternal,
  }) {
    if (trackId == 'auto' ||
        trackId == 'no' ||
        descriptor.mode != TrackPreferenceMode.specific) {
      return 0;
    }

    var score = 0;
    final candLang = inferTrackLanguageKey(
      language: language,
      title: title,
      id: trackId,
    );

    if (descriptor.language != null) {
      if (candLang != null && candLang != descriptor.language) {
        return 0;
      }
      if (candLang == descriptor.language) {
        score += 100;
      }
    }

    final prefTitle = descriptor.title?.trim().toLowerCase();
    final candTitle = title?.trim().toLowerCase();
    if (prefTitle != null && candTitle != null && candTitle.isNotEmpty) {
      if (prefTitle == candTitle) {
        score += 40;
      }
      score += _flagAffinity(prefTitle, candTitle, _commentaryPattern);
      score += _flagAffinity(prefTitle, candTitle, _forcedPattern);
    }

    final candCodec = codec?.trim().toLowerCase();
    if (descriptor.codec != null &&
        candCodec != null &&
        candCodec.isNotEmpty &&
        descriptor.codec == candCodec) {
      score += 15;
    }

    final candChannels = channels?.trim().toLowerCase();
    if (descriptor.channels != null &&
        candChannels != null &&
        candChannels.isNotEmpty &&
        descriptor.channels == candChannels) {
      score += 15;
    }

    final hasSemanticMatch = score > 0;
    if (!hasSemanticMatch &&
        descriptor.language == null &&
        descriptor.title == null &&
        descriptor.trackIdHint == trackId) {
      score += 60;
    } else if (hasSemanticMatch && descriptor.trackIdHint == trackId) {
      score += 5;
    }

    if (score > 0 && descriptor.isExternal == isExternal) {
      score += 10;
    }

    return score < 0 ? 0 : score;
  }

  static int _flagAffinity(String a, String b, RegExp pattern) {
    final aHas = pattern.hasMatch(a);
    final bHas = pattern.hasMatch(b);
    if (!aHas && !bHas) return 0;
    return aHas == bHas ? 15 : -25;
  }

  static AudioTrack? findBestAudioTrack(
    List<AudioTrack> tracks,
    TrackPreferenceDescriptor descriptor,
  ) {
    AudioTrack? best;
    var bestScore = 0;
    for (final track in tracks) {
      final chan = track.channels?.trim().isNotEmpty == true
          ? track.channels
          : (track.channelscount ?? track.audiochannels)?.toString();
      final score = scoreCandidate(
        descriptor: descriptor,
        trackId: track.id,
        language: track.language,
        title: track.title,
        codec: track.codec,
        channels: chan,
        isExternal: track.uri,
      );
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  static SubtitleTrack? findBestSubtitleTrack(
    List<SubtitleTrack> tracks,
    TrackPreferenceDescriptor descriptor,
  ) {
    SubtitleTrack? best;
    var bestScore = 0;
    for (final track in tracks) {
      final score = scoreCandidate(
        descriptor: descriptor,
        trackId: track.id,
        language: track.language,
        title: track.title,
        codec: track.codec,
        channels: null,
        isExternal: track.uri || track.data,
      );
      if (score > bestScore) {
        bestScore = score;
        best = track;
      }
    }
    return best;
  }

  /// Prioritätskette:
  /// 1. Serienpräferenz (off / spezifische Spur via stabile Merkmale)
  /// 2. Globale Nutzerpräferenz (bei fehlender Serienpräferenz oder `auto` oder nicht mehr vorhandener Serienspur)
  /// 3. Player-/Medienstandard
  static ({AudioTrack? audio, SubtitleTrack? subtitle, bool fromSeries})
      resolve({
    required SeriesTrackPreferences? seriesPreferences,
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

    final audioPref = seriesPreferences?.audio;
    if (audioPref != null) {
      if (audioPref.mode == TrackPreferenceMode.off) {
        if (activeAudioTrack.id != 'no') {
          targetAudio = AudioTrack.no();
        }
      } else if (audioPref.mode == TrackPreferenceMode.auto) {
        if (activeAudioTrack.id != 'auto') {
          targetAudio = AudioTrack.auto();
        }
      } else {
        final matchedAudio = findBestAudioTrack(audioTracks, audioPref);
        if (matchedAudio != null && activeAudioTrack.id != matchedAudio.id) {
          targetAudio = matchedAudio;
        }
      }
    }

    final subPref = seriesPreferences?.subtitle;
    if (subPref != null) {
      if (subPref.mode == TrackPreferenceMode.off) {
        fromSeries = true;
        if (activeSubtitleTrack.id != 'no') {
          targetSubtitle = SubtitleTrack.no();
        }
        return (
          audio: targetAudio,
          subtitle: targetSubtitle,
          fromSeries: fromSeries,
        );
      } else if (subPref.mode == TrackPreferenceMode.specific) {
        final matchedSub = findBestSubtitleTrack(subtitleTracks, subPref);
        if (matchedSub != null) {
          fromSeries = true;
          if (activeSubtitleTrack.id != matchedSub.id) {
            targetSubtitle = matchedSub;
          }
          return (
            audio: targetAudio,
            subtitle: targetSubtitle,
            fromSeries: fromSeries,
          );
        }
      }
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
