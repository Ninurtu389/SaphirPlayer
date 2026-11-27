import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import '../storage/portable_paths.dart';

enum PlayableFileStatus {
  ok,
  missing,
  empty,
}

class LocalFileService {
  LocalFileService._();

  static Future<PlayableFileStatus> checkPlayableFile(String filePath) async {
    final file = File(filePath);
    try {
      if (!await file.exists()) {
        return PlayableFileStatus.missing;
      }
      if (await file.length() == 0) {
        return PlayableFileStatus.empty;
      }
      return PlayableFileStatus.ok;
    } on FileSystemException {
      return PlayableFileStatus.missing;
    }
  }

  static ImageProvider? imageProviderForPath(
    String? path, {
    int? cacheWidth,
    int? cacheHeight,
  }) {
    if (path == null || path.isEmpty) {
      return null;
    }
    return ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      FileImage(File(path)),
    );
  }

  static Future<String?> saveScreenshotBytes({
    required Uint8List bytes,
    required String title,
    DateTime? timestamp,
  }) async {
    if (bytes.isEmpty) {
      return null;
    }
    final sanitized = _sanitizeFileName(title);
    final now = timestamp ?? DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    try {
      final dir = await PortablePaths.getScreenshotsDirectory();
      final outPath = p.join(dir, '${sanitized}_$stamp.png');
      await File(outPath).writeAsBytes(bytes, flush: true);
      return outPath;
    } on FileSystemException {
      return null;
    }
  }

  static String _sanitizeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (cleaned.isEmpty) {
      return 'saphir_shot';
    }
    return cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
  }
}
