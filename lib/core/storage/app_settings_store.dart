import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';
import '../models/status_feedback_models.dart';
import '../theme/effect_mode.dart';
import '../utils/formatters.dart';
import 'database_backup_service.dart';

class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    required this.nasPaths,
    required this.effectMode,
    required this.perDeviceEffect,
    required this.subtitlesEnabledByDefault,
    required this.preferredSubtitleLanguage,
    required this.subtitleScale,
    required this.subtitlePosition,
    required this.subtitleBgOpacity,
    required this.hardwareAccelerationEnabled,
    this.lastNasSyncAtMs,
    this.lastNasSyncTarget,
    this.fieldWarnings = const [],
  });

  factory AppSettingsSnapshot.defaults() => const AppSettingsSnapshot(
        nasPaths: <String>[],
        effectMode: EffectMode.glass,
        perDeviceEffect: true,
        subtitlesEnabledByDefault: false,
        preferredSubtitleLanguage: AppStrings.subtitleLangCodeDe,
        subtitleScale: AppSpacing.subtitleScaleDefault,
        subtitlePosition: AppSpacing.subtitlePositionDefault,
        subtitleBgOpacity: AppSpacing.subtitleBgOpacityDefault,
        hardwareAccelerationEnabled: true,
      );

  final List<String> nasPaths;
  final EffectMode effectMode;
  final bool perDeviceEffect;
  final bool subtitlesEnabledByDefault;
  final String preferredSubtitleLanguage;
  final double subtitleScale;
  final int subtitlePosition;
  final double subtitleBgOpacity;
  final bool hardwareAccelerationEnabled;
  final int? lastNasSyncAtMs;
  final String? lastNasSyncTarget;
  final List<String> fieldWarnings;
}

class AppSettingsStore {
  AppSettingsStore._();

  static const String nasPathKey = 'nas_root_path';
  static const String nasPathsKey = 'nas_root_paths';
  static const String globalEffectKey = 'effect_mode_global';
  static const String subtitlesDefaultKey = 'subtitles_default_enabled';
  static const String preferredSubtitleLangKey = 'preferred_subtitle_language';
  static const String subtitleScaleKey = 'subtitle_scale';
  static const String subtitlePositionKey = 'subtitle_position';
  static const String subtitleBgOpacityKey = 'subtitle_bg_opacity';
  static const String lastNasSyncAtKey = 'last_nas_sync_at';
  static const String lastNasSyncTargetKey = 'last_nas_sync_target';

  static AppSettingsSnapshot loadAll(
    Database db, {
    required String deviceEffectKey,
    required String deviceHwdecKey,
  }) {
    final warnings = <String>[];
    final loadedPaths = _loadNasPaths(db, warnings);

    final deviceEffectRaw = readSetting(db, deviceEffectKey);
    final bool perDeviceEffect;
    final EffectMode effectMode;
    if (deviceEffectRaw != null) {
      perDeviceEffect = true;
      effectMode = _parseEffectMode(deviceEffectRaw, deviceEffectKey, warnings);
    } else {
      perDeviceEffect = false;
      effectMode = _parseEffectMode(
        readSetting(db, globalEffectKey),
        globalEffectKey,
        warnings,
      );
    }

    final subDefRaw = readSetting(db, subtitlesDefaultKey);
    final subtitlesDefault = _parseBoolSetting(
      subDefRaw,
      key: subtitlesDefaultKey,
      defaultValue: false,
      warnings: warnings,
    );

    final langRaw = readSetting(db, preferredSubtitleLangKey);
    final lang = _parseSubtitleLang(langRaw, warnings);

    final scale = _parseDoubleClamped(
      readSetting(db, subtitleScaleKey),
      key: subtitleScaleKey,
      defaultValue: AppSpacing.subtitleScaleDefault,
      min: AppSpacing.subtitleScaleMin,
      max: AppSpacing.subtitleScaleMax,
      warnings: warnings,
    );
    final position = _parseIntClamped(
      readSetting(db, subtitlePositionKey),
      key: subtitlePositionKey,
      defaultValue: AppSpacing.subtitlePositionDefault,
      min: AppSpacing.subtitlePositionMin,
      max: AppSpacing.subtitlePositionMax,
      warnings: warnings,
    );
    final bgOpacity = _parseDoubleClamped(
      readSetting(db, subtitleBgOpacityKey),
      key: subtitleBgOpacityKey,
      defaultValue: AppSpacing.subtitleBgOpacityDefault,
      min: AppSpacing.subtitleBgOpacityMin,
      max: AppSpacing.subtitleBgOpacityMax,
      warnings: warnings,
    );

    final hwdec = _parseBoolSetting(
      readSetting(db, deviceHwdecKey),
      key: deviceHwdecKey,
      defaultValue: true,
      warnings: warnings,
    );

    final lastSyncAtRaw = readSetting(db, lastNasSyncAtKey);
    int? lastSyncAt;
    if (lastSyncAtRaw != null && lastSyncAtRaw.trim().isNotEmpty) {
      lastSyncAt = int.tryParse(lastSyncAtRaw.trim());
      if (lastSyncAt == null || lastSyncAt < 0) {
        lastSyncAt = null;
        warnings.add('$lastNasSyncAtKey: ungültiger Zeitstempel');
      }
    }
    final lastSyncTarget = readSetting(db, lastNasSyncTargetKey);

    return AppSettingsSnapshot(
      nasPaths: loadedPaths,
      effectMode: effectMode,
      perDeviceEffect: perDeviceEffect,
      subtitlesEnabledByDefault: subtitlesDefault,
      preferredSubtitleLanguage: lang,
      subtitleScale: scale,
      subtitlePosition: position,
      subtitleBgOpacity: bgOpacity,
      hardwareAccelerationEnabled: hwdec,
      lastNasSyncAtMs: lastSyncAt,
      lastNasSyncTarget: lastSyncTarget,
      fieldWarnings: List.unmodifiable(warnings),
    );
  }

  static List<String> _loadNasPaths(Database db, List<String> warnings) {
    final loadedPaths = <String>[];
    final multiRaw = readSetting(db, nasPathsKey);
    if (multiRaw != null) {
      try {
        final decoded = jsonDecode(multiRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.trim().isNotEmpty) {
              addUniquePath(loadedPaths, item.trim());
            } else {
              warnings.add('$nasPathsKey: ungültiger Pfad-Eintrag ignoriert');
            }
          }
        } else {
          warnings.add('$nasPathsKey: JSON ist keine Liste');
        }
      } on FormatException {
        warnings.add('$nasPathsKey: beschädigtes JSON');
      }
    }

    if (loadedPaths.isEmpty) {
      final legacyPath = readSetting(db, nasPathKey)?.trim() ?? '';
      if (legacyPath.isNotEmpty) {
        loadedPaths.add(legacyPath);
      }
    }
    return loadedPaths;
  }

  static EffectMode _parseEffectMode(
    String? raw,
    String key,
    List<String> warnings,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return EffectMode.glass;
    }
    final norm = raw.trim().toLowerCase();
    if (norm != 'glass' && norm != 'lean') {
      warnings.add('$key: unbekannter Wert "$raw"');
    }
    return EffectMode.fromStorage(raw);
  }

  static bool _parseBoolSetting(
    String? raw, {
    required String key,
    required bool defaultValue,
    required List<String> warnings,
  }) {
    if (raw == null || raw.trim().isEmpty) return defaultValue;
    final norm = raw.trim().toLowerCase();
    if (norm == '1' || norm == 'true') return true;
    if (norm == '0' || norm == 'false') return false;
    warnings.add('$key: ungültiger Wahrheitswert "$raw"');
    return defaultValue;
  }

  static String _parseSubtitleLang(String? raw, List<String> warnings) {
    if (raw == null || raw.trim().isEmpty) {
      return AppStrings.subtitleLangCodeDe;
    }
    final norm = raw.trim().toLowerCase();
    if (norm == AppStrings.subtitleLangCodeDe ||
        norm == AppStrings.subtitleLangCodeEn ||
        norm == AppStrings.subtitleLangCodeAuto) {
      return norm;
    }
    warnings.add('$preferredSubtitleLangKey: unbekannte Sprache "$raw"');
    return AppStrings.subtitleLangCodeDe;
  }

  static double _parseDoubleClamped(
    String? raw, {
    required String key,
    required double defaultValue,
    required double min,
    required double max,
    required List<String> warnings,
  }) {
    if (raw == null || raw.trim().isEmpty) return defaultValue;
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) {
      warnings.add('$key: ungültige Zahl "$raw"');
      return defaultValue;
    }
    final clamped = parsed.clamp(min, max).toDouble();
    if (clamped != parsed) {
      warnings.add('$key: Wert $parsed auf Bereich [$min..$max] begrenzt');
    }
    return clamped;
  }

  static int _parseIntClamped(
    String? raw, {
    required String key,
    required int defaultValue,
    required int min,
    required int max,
    required List<String> warnings,
  }) {
    if (raw == null || raw.trim().isEmpty) return defaultValue;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      warnings.add('$key: ungültige Ganzzahl "$raw"');
      return defaultValue;
    }
    final clamped = parsed.clamp(min, max).toInt();
    if (clamped != parsed) {
      warnings.add('$key: Wert $parsed auf Bereich [$min..$max] begrenzt');
    }
    return clamped;
  }

  static String? readSetting(Database db, String key) {
    final rows = db.select(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1;',
      [key],
    );
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  static void upsertSetting(Database db, String key, String value) {
    db.execute(
      '''
      INSERT INTO app_settings (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value;
      ''',
      [key, value],
    );
  }

  static void deleteSetting(Database db, String key) {
    db.execute('DELETE FROM app_settings WHERE key = ?;', [key]);
  }

  static void persistNasSyncMeta(
    Database db, {
    required int timestampMs,
    required String targetPath,
  }) {
    upsertSetting(db, lastNasSyncAtKey, timestampMs.toString());
    upsertSetting(db, lastNasSyncTargetKey, targetPath);
  }

  static void persistEffectMode(
    Database db, {
    required bool perDeviceEffect,
    required String deviceEffectKey,
    required EffectMode effectMode,
  }) {
    if (perDeviceEffect) {
      upsertSetting(db, deviceEffectKey, effectMode.toStorage());
    } else {
      deleteSetting(db, deviceEffectKey);
      upsertSetting(db, globalEffectKey, effectMode.toStorage());
    }
  }

  static ({double scale, int position, double bgOpacity}) saveSubtitleStyle(
    Database db, {
    required double currentScale,
    required int currentPosition,
    required double currentBgOpacity,
    double? scale,
    int? position,
    double? bgOpacity,
  }) {
    var nextScale = currentScale;
    var nextPos = currentPosition;
    var nextBg = currentBgOpacity;
    if (scale != null) {
      nextScale =
          scale.clamp(AppSpacing.subtitleScaleMin, AppSpacing.subtitleScaleMax);
      upsertSetting(db, subtitleScaleKey, nextScale.toStringAsFixed(2));
    }
    if (position != null) {
      nextPos = position.clamp(
        AppSpacing.subtitlePositionMin,
        AppSpacing.subtitlePositionMax,
      );
      upsertSetting(db, subtitlePositionKey, nextPos.toString());
    }
    if (bgOpacity != null) {
      nextBg = bgOpacity.clamp(
        AppSpacing.subtitleBgOpacityMin,
        AppSpacing.subtitleBgOpacityMax,
      );
      upsertSetting(db, subtitleBgOpacityKey, nextBg.toStringAsFixed(2));
    }
    return (scale: nextScale, position: nextPos, bgOpacity: nextBg);
  }

  static void saveAll(
    Database db, {
    required List<String> nasPaths,
    required String nasPath,
    required bool perDeviceEffect,
    required String deviceEffectKey,
    required EffectMode effectMode,
    required bool subtitlesEnabledByDefault,
    required String preferredSubtitleLanguage,
    required double subtitleScale,
    required int subtitlePosition,
    required double subtitleBgOpacity,
    required String deviceHwdecKey,
    required bool hardwareAccelerationEnabled,
  }) {
    upsertSetting(db, nasPathsKey, jsonEncode(nasPaths));
    upsertSetting(db, nasPathKey, nasPath);
    persistEffectMode(
      db,
      perDeviceEffect: perDeviceEffect,
      deviceEffectKey: deviceEffectKey,
      effectMode: effectMode,
    );
    upsertSetting(
        db, subtitlesDefaultKey, subtitlesEnabledByDefault ? '1' : '0');
    upsertSetting(db, preferredSubtitleLangKey, preferredSubtitleLanguage);
    upsertSetting(db, subtitleScaleKey, subtitleScale.toStringAsFixed(2));
    upsertSetting(db, subtitlePositionKey, subtitlePosition.toString());
    upsertSetting(
        db, subtitleBgOpacityKey, subtitleBgOpacity.toStringAsFixed(2));
    upsertSetting(db, deviceHwdecKey, hardwareAccelerationEnabled ? '1' : '0');
  }

  static bool addUniquePath(List<String> target, String candidate) {
    final normalized = candidate.toLowerCase();
    final exists = target.any((p) => p.toLowerCase() == normalized);
    if (exists) return false;
    target.add(candidate);
    return true;
  }

  static String normalizeSubtitleLang(String? raw) {
    if (raw == AppStrings.subtitleLangCodeEn ||
        raw == AppStrings.subtitleLangCodeAuto) {
      return raw!;
    }
    return AppStrings.subtitleLangCodeDe;
  }

  static String formatLastSuccessfulSync(SyncFeedbackSummary? last) {
    if (last == null) return AppStrings.syncLastNasNoneLabel;
    final suffix = last.targetPath.isNotEmpty
        ? ' · ${Formatters.formatCompactPath(last.targetPath)}'
        : '';
    return '${AppStrings.syncLastNasPrefix} '
        '${Formatters.formatDateTimeShort(last.timestampMs)}$suffix';
  }

  static String formatLatestBackup(BackupInfo? backup) {
    if (backup == null) return AppStrings.backupNoneLabel;
    return '${AppStrings.backupLatestPrefix} '
        '${Formatters.formatDateTimeShort(backup.createdAt.millisecondsSinceEpoch)} '
        '(${Formatters.formatCacheSize(backup.sizeBytes)})';
  }
}
