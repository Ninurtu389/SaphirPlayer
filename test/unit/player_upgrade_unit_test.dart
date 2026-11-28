import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/utils/formatters.dart';
import 'package:saphir_player/features/library/library_models.dart';
import 'package:saphir_player/features/player/mpv_property_bridge.dart';
import 'package:saphir_player/features/player/track_preference_models.dart';
import 'package:saphir_player/features/player/track_preference_resolver.dart';

void main() {
  group('Formatters remaining, finish time, playbackSpeed & UI helpers', () {
    test('formatPlaybackSpeed formats all speeds accurately without rounding',
        () {
      expect(Formatters.formatPlaybackSpeed(0.75), '0.75×');
      expect(Formatters.formatPlaybackSpeed(1.0), '1.0×');
      expect(Formatters.formatPlaybackSpeed(1.25), '1.25×');
      expect(Formatters.formatPlaybackSpeed(1.5), '1.5×');
      expect(Formatters.formatPlaybackSpeed(2.0), '2.0×');
    });

    test(
        'UI string formatters format remaining, episode row, series progress and hero line',
        () {
      expect(
        Formatters.formatRemainingMinutes(12),
        '12 ${AppStrings.remainingMinutesSuffix}',
      );
      expect(Formatters.formatEpisodeRowTitle(3, 'Kassa'), '3. Kassa');
      expect(
        Formatters.formatSeriesWatchedProgress(2, 8),
        '2 / 8 ${AppStrings.episodesCountLabel} ${AppStrings.watchedBadge.toLowerCase()}',
      );
      expect(
        Formatters.formatHeroInfoLine('S1E2 · Lüge', 20),
        'S1E2 · Lüge · 20 ${AppStrings.remainingMinutesSuffix}',
      );
      expect(Formatters.formatHeroInfoLine('Film · 2024', 0), 'Film · 2024');

      expect(
        Formatters.formatSeriesPlayButton(null),
        AppStrings.playEpisodeOneButton,
      );
      expect(
        Formatters.formatSeriesPlayButton(
          const EpisodeEntry(
            id: 1,
            seriesId: 1,
            seasonId: 1,
            seasonNumber: 2,
            episodeNumber: 5,
            title: 'Test',
            filePath: 'a.mkv',
            durationMs: 1000,
            thumbPath: null,
            positionMs: 500,
            isCompleted: false,
          ),
        ),
        '${AppStrings.resumeButton} (S02E05)',
      );
    });
    test('formatRemainingDuration formats negative remaining time', () {
      expect(
        Formatters.formatRemainingDuration(
          const Duration(minutes: 10, seconds: 15),
          const Duration(minutes: 29, seconds: 0),
        ),
        '-18:45',
      );
      expect(
        Formatters.formatRemainingDuration(
          const Duration(minutes: 30),
          const Duration(minutes: 20),
        ),
        '-00:00',
      );
    });

    test('formatEstimatedFinishTime accounts for playbackSpeed and midnight',
        () {
      final now = DateTime(2026, 11, 27, 23, 45);
      // 30 min remaining at 1.0x -> 00:15
      expect(
        Formatters.formatEstimatedFinishTime(
          Duration.zero,
          const Duration(minutes: 30),
          1.0,
          now,
        ),
        '${AppStrings.playerFinishTimePrefix} 00:15',
      );
      // 30 min remaining at 1.25x -> 24 min -> 00:09
      expect(
        Formatters.formatEstimatedFinishTime(
          Duration.zero,
          const Duration(minutes: 30),
          1.25,
          now,
        ),
        '${AppStrings.playerFinishTimePrefix} 00:09',
      );
      // 30 min remaining at 1.5x -> 20 min -> 00:05
      expect(
        Formatters.formatEstimatedFinishTime(
          Duration.zero,
          const Duration(minutes: 30),
          1.5,
          now,
        ),
        '${AppStrings.playerFinishTimePrefix} 00:05',
      );
      // 30 min remaining at 2.0x -> 15 min -> 00:00
      expect(
        Formatters.formatEstimatedFinishTime(
          Duration.zero,
          const Duration(minutes: 30),
          2.0,
          now,
        ),
        '${AppStrings.playerFinishTimePrefix} 00:00',
      );
    });
  });

  group('MpvPropertyBridge JSON & style helpers', () {
    test(
        'parseChaptersJson handles valid, empty, malformed, and fallback titles',
        () {
      expect(MpvPropertyBridge.parseChaptersJson(null), isEmpty);
      expect(MpvPropertyBridge.parseChaptersJson(''), isEmpty);
      expect(MpvPropertyBridge.parseChaptersJson('[]'), isEmpty);
      expect(MpvPropertyBridge.parseChaptersJson('{bad json'), isEmpty);

      const json = '''
      [
        {"title": "Intro", "time": 0.0},
        {"title": "", "time": 85.5},
        {"title": "Invalid", "time": -5},
        {"title": "Credits", "time": "1400.25"}
      ]
      ''';
      final chapters = MpvPropertyBridge.parseChaptersJson(json);
      expect(chapters.length, 3);
      expect(chapters[0].title, 'Intro');
      expect(chapters[0].startMs, 0);
      expect(chapters[1].title, '${AppStrings.playerChapterPrefix} 2');
      expect(chapters[1].startMs, 85500);
      expect(chapters[2].title, 'Credits');
      expect(chapters[2].startMs, 1400250);
    });

    test('formatSubBackColor encodes alpha hex accurately', () {
      expect(MpvPropertyBridge.formatSubBackColor(0.0), '#00000000');
      expect(MpvPropertyBridge.formatSubBackColor(0.85), '#D9000000');
    });
  });

  group('TrackPreferenceResolver language aliases & fallback', () {
    test('matches de and en aliases and falls back cleanly', () {
      final subDe = SubtitleTrack('1', 'Deutsch', 'ger');
      final subDe2 = SubtitleTrack('2', 'German SDH', 'deu');
      final subEn = SubtitleTrack('3', 'English', 'eng');
      final subFr = SubtitleTrack('4', 'Français', 'fre');

      expect(
        TrackPreferenceResolver.matchesSubtitleLanguage(subDe, 'de'),
        isTrue,
      );
      expect(
        TrackPreferenceResolver.matchesSubtitleLanguage(subDe2, 'de'),
        isTrue,
      );
      expect(
        TrackPreferenceResolver.matchesSubtitleLanguage(subEn, 'en'),
        isTrue,
      );
      expect(
        TrackPreferenceResolver.matchesSubtitleLanguage(
            SubtitleTrack.no(), 'de'),
        isFalse,
      );

      final tracks = [
        SubtitleTrack.auto(),
        SubtitleTrack.no(),
        subFr,
        subEn,
        subDe
      ];
      expect(
        TrackPreferenceResolver.findPreferredSubtitleTrack(tracks, 'de')?.id,
        '1',
      );
      expect(
        TrackPreferenceResolver.findPreferredSubtitleTrack(tracks, 'en')?.id,
        '3',
      );
      expect(
        TrackPreferenceResolver.findPreferredSubtitleTrack(tracks, 'auto')?.id,
        '4',
      );
      // Fallback to first real track if requested language is missing
      expect(
        TrackPreferenceResolver.findPreferredSubtitleTrack(tracks, 'ja')?.id,
        '4',
      );
    });

    test(
        'resolves swapped track IDs by stable language, title, codec and channels',
        () {
      const ep1Audio = AudioTrack(
        '2',
        'Deutsch',
        'deu',
        codec: 'eac3',
        channelscount: 6,
      );
      final descriptor = TrackPreferenceDescriptor.fromAudioTrack(ep1Audio);

      // Episode 2 has different numeric track IDs and 'ger' instead of 'deu'
      const ep2En =
          AudioTrack('1', 'English', 'eng', codec: 'eac3', channelscount: 6);
      const ep2DeCommentary = AudioTrack(
        '4',
        'Deutsch Kommentar',
        'ger',
        codec: 'aac',
        channelscount: 2,
      );
      const ep2DeMain = AudioTrack(
        '7',
        'Deutsch',
        'ger',
        codec: 'eac3',
        channelscount: 6,
      );

      final resolved = TrackPreferenceResolver.resolve(
        seriesPreferences: SeriesTrackPreferences(audio: descriptor),
        audioTracks: [AudioTrack.auto(), ep2En, ep2DeCommentary, ep2DeMain],
        subtitleTracks: [SubtitleTrack.auto(), SubtitleTrack.no()],
        activeAudioTrack: AudioTrack.auto(),
        activeSubtitleTrack: SubtitleTrack.auto(),
        subtitlesEnabledByDefault: false,
        preferredSubtitleLanguage: 'de',
      );
      expect(resolved.audio?.id, '7');
      expect(resolved.subtitle?.id, 'no');
    });

    test(
        'falls back to global subtitle preference when series language is absent',
        () {
      final resolved = TrackPreferenceResolver.resolve(
        seriesPreferences: const SeriesTrackPreferences(
          subtitle: TrackPreferenceDescriptor(
            mode: TrackPreferenceMode.specific,
            language: 'ja',
            title: 'Japanese',
            trackIdHint: '9',
          ),
        ),
        audioTracks: [AudioTrack.auto()],
        subtitleTracks: [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          const SubtitleTrack('1', 'Deutsch', 'deu'),
          const SubtitleTrack('2', 'English', 'eng'),
        ],
        activeAudioTrack: AudioTrack.auto(),
        activeSubtitleTrack: SubtitleTrack.auto(),
        subtitlesEnabledByDefault: true,
        preferredSubtitleLanguage: 'en',
      );
      expect(resolved.subtitle?.id, '2');
      expect(resolved.fromSeries, isFalse);
    });
  });
}
