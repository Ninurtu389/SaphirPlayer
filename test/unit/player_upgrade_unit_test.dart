import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:saphir_player/core/constants/app_strings.dart';
import 'package:saphir_player/core/utils/formatters.dart';
import 'package:saphir_player/features/player/mpv_property_bridge.dart';
import 'package:saphir_player/features/player/track_preference_resolver.dart';

void main() {
  group('Formatters remaining & finish time', () {
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
    test('parseChaptersJson handles valid, empty, malformed, and fallback titles',
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
        TrackPreferenceResolver.matchesSubtitleLanguage(SubtitleTrack.no(), 'de'),
        isFalse,
      );

      final tracks = [SubtitleTrack.auto(), SubtitleTrack.no(), subFr, subEn, subDe];
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
  });
}
