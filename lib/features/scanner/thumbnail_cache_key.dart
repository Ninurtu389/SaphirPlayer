import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Klassifiziert Fehler bei der Thumbnail-Erzeugung für A08-Retry-Entscheidungen.
enum ThumbnailFailureKind {
  none,
  transient,
  permanent,
  cancelled,
}

/// Strukturiertes Ergebnis einer Thumbnail-Erzeugung inkl. Fehlerklassifikation.
class ThumbnailGenerationOutcome {
  const ThumbnailGenerationOutcome({
    this.fileName,
    this.durationMs,
    this.failureKind = ThumbnailFailureKind.none,
    this.errorMessage,
  });

  final String? fileName;
  final int? durationMs;
  final ThumbnailFailureKind failureKind;
  final String? errorMessage;

  bool get isSuccess => fileName != null && fileName!.isNotEmpty;
}

/// Normalisierte Cache-Keys, atomare Temp-Pfade und Magic-Byte-Validierung (A07).
class ThumbnailCacheKey {
  ThumbnailCacheKey._();

  static const int _minValidImageBytes = 16;

  /// Normalisiert Windows-Drive- und UNC-Pfade deterministisch.
  static String normalizeSourcePath(String filePath) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) return '';

    final slashUnified = trimmed.replaceAll('/', '\\');
    final isUnc = slashUnified.startsWith('\\\\');
    var normalized = p.windows.normalize(slashUnified);
    if (isUnc && !normalized.startsWith('\\\\')) {
      normalized = '\\\\${normalized.replaceFirst(RegExp(r'^\\+'), '')}';
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  /// Baut den Fingerabdruck-Eingabestring aus normiertem Pfad, Größe und Änderungszeit.
  static String buildFingerprintInput({
    required String filePath,
    required int fileSize,
    required int modifiedAt,
  }) {
    final normalizedPath = normalizeSourcePath(filePath);
    return '$normalizedPath|$fileSize|$modifiedAt';
  }

  /// Berechnet einen stabilen 64-Bit-Hex-Hash (16 Zeichen).
  static String stableHash(String input) {
    final bytes = utf8.encode(input);
    var hashA = 0x811c9dc5;
    var hashB = 0x9e3779b9;
    for (final byte in bytes) {
      hashA ^= byte;
      hashA = (hashA * 0x01000193) & 0xFFFFFFFF;
      hashB ^= (byte + 0x55) & 0xFF;
      hashB = (hashB * 0x85EBCA6B) & 0xFFFFFFFF;
    }
    hashA ^= bytes.length;
    hashA = (hashA * 0x01000193) & 0xFFFFFFFF;
    final hexA = hashA.toRadixString(16).padLeft(8, '0');
    final hexB = hashB.toRadixString(16).padLeft(8, '0');
    return '$hexA$hexB';
  }

  /// Baut den deterministischen Cache-Dateinamen inkl. Datei-Fingerabdruck.
  static String buildCacheFileName({
    required String prefix,
    required String filePath,
    required int fileSize,
    required int modifiedAt,
  }) {
    final fingerprint = buildFingerprintInput(
      filePath: filePath,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
    );
    return '${prefix}_${stableHash(fingerprint)}.jpg';
  }

  /// Erzeugt einen eindeutigen temporären `.jpg`-Pfad für atomares Schreiben.
  static String buildTempFilePath({
    required String cacheDir,
    required String finalFileName,
  }) {
    final stem = p.basenameWithoutExtension(finalFileName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(cacheDir, '.tmp_${stem}_${pid}_$stamp.jpg');
  }

  /// Prüft Dateiexistenz, Mindestgröße und JPEG/PNG/WebP-Magic-Bytes.
  static Future<bool> isValidImageFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < _minValidImageBytes) return false;

      final header = await file.openRead(0, 12).fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      if (header.length < 12) return false;

      // JPEG: FF D8 FF
      if (header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
        return true;
      }
      // PNG: 89 50 4E 47 0D 0A 1A 0A
      if (header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4E &&
          header[3] == 0x47 &&
          header[4] == 0x0D &&
          header[5] == 0x0A &&
          header[6] == 0x1A &&
          header[7] == 0x0A) {
        return true;
      }
      // WebP: RIFF....WEBP
      if (header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50) {
        return true;
      }
      return false;
    } on FileSystemException {
      return false;
    }
  }

  /// Bereinigt Fehlermeldungen für sichere Persistenz in `thumb_last_error`.
  static String sanitizeErrorMessage(String raw, {int maxLength = 240}) {
    final compact = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength - 3)}...';
  }
}
