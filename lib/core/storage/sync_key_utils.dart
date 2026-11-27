import 'dart:convert';
import 'package:path/path.dart' as p;

class SyncKeyUtils {
  SyncKeyUtils._();

  static String buildStableSyncKey(
    String prefix,
    String filePath,
    String rootPath,
  ) {
    final normalizedFile =
        p.normalize(filePath.trim()).replaceAll('\\', '/');
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

    final canonical = relativeOrFull
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();

    return '${prefix}_${_stableHash(canonical)}';
  }

  static String buildKeyFromRoots(
    String prefix,
    String filePath,
    List<String> roots,
  ) {
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
    return buildStableSyncKey(prefix, filePath, bestRoot ?? '');
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
