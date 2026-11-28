import 'dart:convert';
import 'package:path/path.dart' as p;

class SyncKeyUtils {
  SyncKeyUtils._();

  static const int currentKeyVersion = 2;
  static const String defaultSourceId = 'default_source';

  static String normalizeSourceId(String raw) {
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      return defaultSourceId;
    }
    return normalized.length > 64 ? normalized.substring(0, 64) : normalized;
  }

  static String deriveDefaultSourceId(String rootPath) {
    var normalized = p
        .normalize(rootPath.trim())
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty || normalized == '.') {
      return defaultSourceId;
    }

    // UNC-Server-Präfix (//server/share -> share) oder Drive-Präfix (Z:/share -> share)
    if (normalized.startsWith('//')) {
      final withoutPrefix = normalized.substring(2);
      final parts =
          withoutPrefix.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) {
        return normalizeSourceId(parts.last);
      }
      if (parts.length == 1) {
        return normalizeSourceId(parts.first);
      }
      return defaultSourceId;
    }

    normalized = normalized.replaceFirst(RegExp(r'^[a-zA-Z]:/?'), '');
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      return defaultSourceId;
    }
    return normalizeSourceId(parts.last);
  }

  static String canonicalizeRelativePath(String filePath, String rootPath) {
    final normalizedFile = p.normalize(filePath.trim()).replaceAll('\\', '/');
    final trimmedRoot = rootPath.trim();

    var relativeOrFull = normalizedFile;
    if (trimmedRoot.isNotEmpty) {
      final normalizedRoot = p
          .normalize(trimmedRoot)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/+$'), '');
      final fileLower = normalizedFile.toLowerCase();
      final rootLower = normalizedRoot.toLowerCase();
      if (fileLower == rootLower) {
        relativeOrFull = p.posix.basename(normalizedFile);
      } else if (fileLower.startsWith('$rootLower/')) {
        relativeOrFull = normalizedFile.substring(normalizedRoot.length + 1);
      }
    }

    return relativeOrFull
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
  }

  static String buildLegacyV1SyncKey(
    String prefix,
    String filePath,
    String rootPath,
  ) {
    final canonical = canonicalizeRelativePath(filePath, rootPath);
    return '${prefix}_${_stableHash(canonical)}';
  }

  static String buildStableSyncKey(
    String prefix,
    String filePath,
    String rootPath, {
    String? sourceId,
  }) {
    final canonical = canonicalizeRelativePath(filePath, rootPath);
    final effectiveSourceId = (sourceId != null && sourceId.trim().isNotEmpty)
        ? normalizeSourceId(sourceId)
        : deriveDefaultSourceId(rootPath);
    return '${prefix}_v${currentKeyVersion}_${_stableHash('$effectiveSourceId::$canonical')}';
  }

  static String buildKeyFromRoots(
    String prefix,
    String filePath,
    List<String> roots, {
    Map<String, String>? sourceIdsByRoot,
  }) {
    final normalizedFile =
        p.normalize(filePath.trim()).replaceAll('\\', '/').toLowerCase();
    String? bestRoot;
    for (final root in roots) {
      final trimmed = root.trim();
      if (trimmed.isEmpty) continue;
      final normalizedRoot = p
          .normalize(trimmed)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/+$'), '')
          .toLowerCase();
      if (normalizedFile == normalizedRoot ||
          normalizedFile.startsWith('$normalizedRoot/')) {
        if (bestRoot == null || trimmed.length > bestRoot.length) {
          bestRoot = trimmed;
        }
      }
    }
    String? resolvedSourceId;
    if (bestRoot != null && sourceIdsByRoot != null) {
      final bestNorm = normalizeRootPath(bestRoot);
      for (final entry in sourceIdsByRoot.entries) {
        if (normalizeRootPath(entry.key) == bestNorm) {
          resolvedSourceId = entry.value;
          break;
        }
      }
    }
    return buildStableSyncKey(
      prefix,
      filePath,
      bestRoot ?? '',
      sourceId: resolvedSourceId,
    );
  }

  static String normalizeRootPath(String rootPath) {
    return p
        .normalize(rootPath.trim())
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
  }

  static bool isV2SyncKey(String? key) {
    if (key == null) return false;
    return key.startsWith('ep_v${currentKeyVersion}_') ||
        key.startsWith('mv_v${currentKeyVersion}_');
  }

  static String _stableHash(String input) {
    final bytes = utf8.encode(input);
    var hashA = 0x811c9dc5;
    var hashB = 0x9e3779b9;
    for (final byte in bytes) {
      hashA ^= byte;
      hashA = (hashA * 0x01000193) & 0xFFFFFFFF;
      hashB ^= (byte + 0x55) & 0xFF;
      hashB = (hashB * 0x85EBCA6B) & 0xFFFFFFFF;
    }
    final hexA = hashA.toRadixString(16).padLeft(8, '0');
    final hexB = hashB.toRadixString(16).padLeft(8, '0');
    return '$hexA$hexB';
  }
}
