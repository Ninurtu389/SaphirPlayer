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
          final rawPlot = match.group(1) ?? '';
          final cleaned = _decodeNfoText(rawPlot);
          if (cleaned.isNotEmpty) {
            return cleaned;
          }
        }
      } catch (_) {
        // Ignoriere fehlerhafte NFO-Strukturen
      }
    }

    return null;
  }

  static String _decodeNfoText(String raw) {
    var text = raw.replaceAllMapped(
      RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true),
      (m) => m.group(1) ?? '',
    );
    text = text
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '');
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '', radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAll('&amp;', '&');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
