import 'dart:convert';
import 'package:media_kit/media_kit.dart';

enum TrackPreferenceMode {
  auto,
  off,
  specific,
}

String? normalizeTrackLanguageKey(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  final tokens = trimmed
      .split(RegExp(r'[^a-z0-9äöüß]+'))
      .where((token) => token.isNotEmpty)
      .toList();
  for (final token in tokens) {
    final mapped = _languageAliasToCanonical[token];
    if (mapped != null) {
      return mapped;
    }
  }
  return tokens.isNotEmpty ? tokens.first : trimmed;
}

String? inferTrackLanguageKey({String? language, String? title, String? id}) {
  final direct = normalizeTrackLanguageKey(language);
  if (direct != null && direct != 'und' && direct != 'unknown') {
    return direct;
  }
  for (final candidate in [title, id]) {
    if (candidate == null) continue;
    final tokens = candidate
        .trim()
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9äöüß]+'))
        .where((t) => t.isNotEmpty);
    for (final token in tokens) {
      final mapped = _languageAliasToCanonical[token];
      if (mapped != null) {
        return mapped;
      }
    }
  }
  return null;
}

const Map<String, String> _languageAliasToCanonical = {
  'de': 'de',
  'deu': 'de',
  'ger': 'de',
  'german': 'de',
  'deutsch': 'de',
  'en': 'en',
  'eng': 'en',
  'english': 'en',
  'englisch': 'en',
  'ja': 'ja',
  'jpn': 'ja',
  'japanese': 'ja',
  'japanisch': 'ja',
  'fr': 'fr',
  'fra': 'fr',
  'fre': 'fr',
  'french': 'fr',
  'franzoesisch': 'fr',
  'französisch': 'fr',
  'es': 'es',
  'spa': 'es',
  'spanish': 'es',
  'spanisch': 'es',
  'it': 'it',
  'ita': 'it',
  'italian': 'it',
  'italienisch': 'it',
  'ko': 'ko',
  'kor': 'ko',
  'korean': 'ko',
  'koreanisch': 'ko',
  'zh': 'zh',
  'zho': 'zh',
  'chi': 'zh',
  'chinese': 'zh',
  'chinesisch': 'zh',
};

class TrackPreferenceDescriptor {
  const TrackPreferenceDescriptor({
    required this.mode,
    this.language,
    this.title,
    this.codec,
    this.channels,
    this.isExternal = false,
    this.trackIdHint,
  });

  const TrackPreferenceDescriptor.auto() : this(mode: TrackPreferenceMode.auto);

  const TrackPreferenceDescriptor.off() : this(mode: TrackPreferenceMode.off);

  factory TrackPreferenceDescriptor.fromAudioTrack(AudioTrack track) {
    if (track.id == 'auto') {
      return const TrackPreferenceDescriptor.auto();
    }
    if (track.id == 'no') {
      return const TrackPreferenceDescriptor.off();
    }
    return TrackPreferenceDescriptor(
      mode: TrackPreferenceMode.specific,
      language: inferTrackLanguageKey(
        language: track.language,
        title: track.title,
        id: track.id,
      ),
      title: _normalizeText(track.title),
      codec: _normalizeLower(track.codec),
      channels: _normalizeChannels(track),
      isExternal: track.uri,
      trackIdHint: track.uri ? null : _normalizeText(track.id),
    );
  }

  factory TrackPreferenceDescriptor.fromSubtitleTrack(SubtitleTrack track) {
    if (track.id == 'auto') {
      return const TrackPreferenceDescriptor.auto();
    }
    if (track.id == 'no') {
      return const TrackPreferenceDescriptor.off();
    }
    final external = track.uri || track.data;
    return TrackPreferenceDescriptor(
      mode: TrackPreferenceMode.specific,
      language: inferTrackLanguageKey(
        language: track.language,
        title: track.title,
        id: track.id,
      ),
      title: _normalizeText(track.title),
      codec: _normalizeLower(track.codec),
      isExternal: external,
      trackIdHint: external ? null : _normalizeText(track.id),
    );
  }

  final TrackPreferenceMode mode;
  final String? language;
  final String? title;
  final String? codec;
  final String? channels;
  final bool isExternal;
  final String? trackIdHint;

  String get legacyTrackId {
    switch (mode) {
      case TrackPreferenceMode.auto:
        return 'auto';
      case TrackPreferenceMode.off:
        return 'no';
      case TrackPreferenceMode.specific:
        return trackIdHint ?? language ?? (isExternal ? 'external' : 'auto');
    }
  }

  static TrackPreferenceDescriptor? tryFromLegacyTrackId(String? rawId) {
    final trimmed = rawId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed == 'auto') {
      return const TrackPreferenceDescriptor.auto();
    }
    if (trimmed == 'no') {
      return const TrackPreferenceDescriptor.off();
    }
    return TrackPreferenceDescriptor(
      mode: TrackPreferenceMode.specific,
      language: inferTrackLanguageKey(id: trimmed),
      trackIdHint: trimmed,
    );
  }

  static TrackPreferenceDescriptor? tryFromJsonString(String? rawJson) {
    if (rawJson == null || rawJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final modeName = decoded['mode'];
      if (modeName == TrackPreferenceMode.auto.name) {
        return const TrackPreferenceDescriptor.auto();
      }
      if (modeName == TrackPreferenceMode.off.name) {
        return const TrackPreferenceDescriptor.off();
      }
      if (modeName != TrackPreferenceMode.specific.name) {
        return null;
      }
      return TrackPreferenceDescriptor(
        mode: TrackPreferenceMode.specific,
        language: normalizeTrackLanguageKey(decoded['language'] as String?),
        title: _normalizeText(decoded['title'] as String?),
        codec: _normalizeLower(decoded['codec'] as String?),
        channels: _normalizeLower(decoded['channels'] as String?),
        isExternal: decoded['isExternal'] == true,
        trackIdHint: _normalizeText(decoded['trackIdHint'] as String?),
      );
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        if (language != null) 'language': language,
        if (title != null) 'title': title,
        if (codec != null) 'codec': codec,
        if (channels != null) 'channels': channels,
        if (isExternal) 'isExternal': true,
        if (trackIdHint != null) 'trackIdHint': trackIdHint,
      };

  String toJsonString() => jsonEncode(toJson());

  static String? _normalizeText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _normalizeLower(String? value) {
    final trimmed = _normalizeText(value);
    return trimmed?.toLowerCase();
  }

  static String? _normalizeChannels(AudioTrack track) {
    final direct = _normalizeLower(track.channels);
    if (direct != null) return direct;
    final count = track.channelscount ?? track.audiochannels;
    return count != null && count > 0 ? count.toString() : null;
  }
}

class SeriesTrackPreferences {
  const SeriesTrackPreferences({
    this.audio,
    this.subtitle,
    this.introSkipSeconds = 0,
  });

  static const SeriesTrackPreferences empty = SeriesTrackPreferences();

  final TrackPreferenceDescriptor? audio;
  final TrackPreferenceDescriptor? subtitle;
  final int introSkipSeconds;
}
