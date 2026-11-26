import 'dart:io';
import 'package:flutter/painting.dart';

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
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      FileImage(file),
    );
  }
}
