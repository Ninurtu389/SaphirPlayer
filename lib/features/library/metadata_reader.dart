import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class MetadataReader {
  MetadataReader._();

  static String? readSeriesSummary(String seriesFolderPath) {
    final jsonFile = File(p.join(seriesFolderPath, 'info.json'));
    if (jsonFile.existsSync()) {
      try {
        final raw = jsonFile.readAsStringSync();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final plot =
              decoded['summary'] ?? decoded['plot'] ?? decoded['description'];
          if (plot is String && plot.trim().isNotEmpty) {
            return plot.trim();
          }
        }
      } catch (_) {
        // Ignoriere fehlerhafte JSON-Strukturen
      }
    }

    final nfoFile = File(p.join(seriesFolderPath, 'tvshow.nfo'));
    if (nfoFile.existsSync()) {
      try {
        final content = nfoFile.readAsStringSync();
        final match = RegExp(
          r'<(?:plot|outline)>(.*?)</(?:plot|outline)>',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(content);
        if (match != null) {
          final cleaned =
              match.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (cleaned != null && cleaned.isNotEmpty) {
            return cleaned;
          }
        }
      } catch (_) {
        // Ignoriere fehlerhafte NFO-Strukturen
      }
    }

    return null;
  }
}
