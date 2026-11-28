import 'dart:convert';
import 'sync_models.dart';

enum SyncParseStatus {
  ok,
  corrupt,
  incompatibleVersion,
  oversized,
}

class SyncParseResult {
  const SyncParseResult({
    required this.status,
    this.document,
    this.errorMessage,
    this.issues = const [],
  });

  final SyncParseStatus status;
  final SyncDocument? document;
  final String? errorMessage;
  final List<SyncValidationIssue> issues;

  bool get isOk => status == SyncParseStatus.ok && document != null;
}

class SyncValidator {
  SyncValidator._();

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F]');

  static SyncParseResult parseFileBytes(List<int> bytes) {
    if (bytes.length > SyncSchema.maxFileSizeBytes) {
      return SyncParseResult(
        status: SyncParseStatus.oversized,
        errorMessage:
            'Sync-Datei überschreitet Maximalgröße (${bytes.length} > ${SyncSchema.maxFileSizeBytes} Bytes).',
      );
    }

    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (error) {
      return SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Ungültige UTF-8-Kodierung: ${error.message}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      return SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Ungültiges JSON: ${error.message}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return const SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Top-Level-JSON muss ein Objekt sein.',
      );
    }

    final version = decoded['version'];
    if (version is! int) {
      return const SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Pflichtfeld "version" fehlt oder ist kein Integer.',
      );
    }
    if (version < SyncSchema.minSupportedVersion) {
      return SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Ungültige Sync-Version: $version.',
      );
    }
    if (version > SyncSchema.currentVersion) {
      return SyncParseResult(
        status: SyncParseStatus.incompatibleVersion,
        errorMessage:
            'Nicht unterstützte Sync-Version $version (max. ${SyncSchema.currentVersion}).',
      );
    }

    final rawEntries = decoded['entries'];
    if (rawEntries is! Map<String, dynamic>) {
      return const SyncParseResult(
        status: SyncParseStatus.corrupt,
        errorMessage: 'Pflichtfeld "entries" fehlt oder ist kein Objekt.',
      );
    }
    if (rawEntries.length > SyncSchema.maxEntriesCount) {
      return SyncParseResult(
        status: SyncParseStatus.oversized,
        errorMessage:
            'Zu viele Sync-Einträge (${rawEntries.length} > ${SyncSchema.maxEntriesCount}).',
      );
    }

    final docUpdatedAt = _parseBoundedInt(
          decoded['updated_at'],
          min: 0,
          max: SyncSchema.maxPlausibleTimestampMs,
        ) ??
        0;
    final generation = _parseBoundedInt(
          decoded['generation'],
          min: 0,
          max: 1 << 30,
        ) ??
        0;
    final rawWriter = decoded['writer_id'];
    final writerId = rawWriter is String
        ? _sanitizeDeviceName(rawWriter, fallback: 'remote')
        : 'remote';

    final validEntries = <String, SyncEntry>{};
    final issues = <SyncValidationIssue>[];

    for (final mapEntry in rawEntries.entries) {
      final key = mapEntry.key;
      final value = mapEntry.value;
      final parsed = _validateEntry(key, value);
      if (parsed.issue != null) {
        issues.add(parsed.issue!);
      } else if (parsed.entry != null) {
        validEntries[key] = parsed.entry!;
      }
    }

    return SyncParseResult(
      status: SyncParseStatus.ok,
      document: SyncDocument(
        version: version,
        updatedAt: docUpdatedAt,
        generation: generation,
        writerId: writerId,
        entries: validEntries,
        isolatedIssues: issues,
      ),
      issues: issues,
    );
  }

  static ({SyncEntry? entry, SyncValidationIssue? issue}) _validateEntry(
    String key,
    Object? rawValue,
  ) {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty ||
        trimmedKey.length > SyncSchema.maxKeyLength ||
        _controlChars.hasMatch(trimmedKey) ||
        trimmedKey != key) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key.length > 64 ? '${key.substring(0, 64)}...' : key,
          reason: 'Ungültiger media_key (leer, zu lang oder Steuerzeichen).',
        ),
      );
    }

    if (rawValue is! Map<String, dynamic>) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Eintrag ist kein JSON-Objekt.',
        ),
      );
    }

    final rawMediaType = rawValue['media_type'];
    if (rawMediaType is! String) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'media_type muss ein String sein.',
        ),
      );
    }
    final mediaType = rawMediaType.trim().toLowerCase();
    if (!SyncSchema.allowedMediaTypes.contains(mediaType)) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Unbekannter media_type "$rawMediaType".',
        ),
      );
    }

    final positionMs = _parseBoundedInt(
      rawValue['position_ms'],
      min: 0,
      max: SyncSchema.maxDurationMs,
    );
    if (positionMs == null) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Ungültige position_ms.',
        ),
      );
    }

    final durationMs = _parseBoundedInt(
      rawValue['duration_ms'],
      min: 0,
      max: SyncSchema.maxDurationMs,
    );
    if (durationMs == null) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Ungültige duration_ms.',
        ),
      );
    }

    final completed = _parseStrictBool(rawValue['completed']);
    if (completed == null) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Ungültiger completed-Wert.',
        ),
      );
    }

    final updatedAt = _parseBoundedInt(
      rawValue['updated_at'],
      min: 0,
      max: SyncSchema.maxPlausibleTimestampMs,
    );
    if (updatedAt == null) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Ungültiger updated_at-Zeitstempel.',
        ),
      );
    }

    final rawDevice = rawValue['source_device'];
    if (rawDevice != null && rawDevice is! String) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'source_device hat keinen gültigen String-Typ.',
        ),
      );
    }
    final sourceDevice =
        _sanitizeDeviceName(rawDevice as String?, fallback: 'remote');

    final rawRevision = rawValue['revision'];
    final revision = rawRevision == null
        ? 0
        : _parseBoundedInt(rawRevision, min: 0, max: 1 << 30);
    if (revision == null) {
      return (
        entry: null,
        issue: SyncValidationIssue(
          entryKey: key,
          reason: 'Ungültige revision.',
        ),
      );
    }

    return (
      entry: SyncEntry(
        mediaKey: key,
        mediaType: mediaType,
        positionMs: positionMs,
        durationMs: durationMs,
        completed: completed,
        updatedAt: updatedAt,
        sourceDevice: sourceDevice,
        revision: revision,
      ),
      issue: null,
    );
  }

  static int? _parseBoundedInt(
    Object? value, {
    required int min,
    required int max,
  }) {
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is double) {
      if (value.isNaN || value.isInfinite) return null;
      parsed = value.round();
    } else if (value is String) {
      final trimmed = value.trim();
      if (!RegExp(r'^-?\d+$').hasMatch(trimmed)) return null;
      parsed = int.tryParse(trimmed);
    }
    if (parsed == null || parsed < min || parsed > max) {
      return null;
    }
    return parsed;
  }

  static bool? _parseStrictBool(Object? value) {
    if (value is bool) return value;
    if (value is int) {
      if (value == 0) return false;
      if (value == 1) return true;
      return null;
    }
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    return null;
  }

  static String _sanitizeDeviceName(
    String? raw, {
    required String fallback,
  }) {
    if (raw == null) return fallback;
    final cleaned = raw.replaceAll(_controlChars, '').trim();
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > SyncSchema.maxDeviceNameLength
        ? cleaned.substring(0, SyncSchema.maxDeviceNameLength)
        : cleaned;
  }
}
