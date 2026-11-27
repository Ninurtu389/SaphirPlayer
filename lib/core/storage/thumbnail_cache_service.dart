import 'dart:io';
import 'database_service.dart';
import 'portable_paths.dart';

class ThumbnailCacheService {
  const ThumbnailCacheService();

  Future<int> calculateCacheBytes() async {
    final cachePath = await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);
    var totalBytes = 0;

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
          } on FileSystemException {
            // Einzelne gesperrte Datei ignorieren
          }
        }
      }
    }
    return totalBytes;
  }

  Future<void> clearCache(DatabaseService databaseService) async {
    final cachePath = await PortablePaths.getCacheDirectory();
    final cacheDir = Directory(cachePath);

    if (await cacheDir.exists()) {
      await for (final entity
          in cacheDir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Einzelne gesperrte Datei überspringen
          }
        }
      }
    }

    final db = databaseService.instance;
    db.execute("UPDATE episodes SET thumb_path = NULL, thumb_status = 'pending';");
    db.execute("UPDATE movies SET thumb_path = NULL, thumb_status = 'pending';");
  }
}
