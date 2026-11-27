import 'dart:io';

class SourceViolation {
  const SourceViolation({
    required this.filePath,
    required this.line,
    required this.category,
    required this.detail,
  });

  final String filePath;
  final int line;
  final String category;
  final String detail;

  @override
  String toString() => '$filePath:$line [$category] $detail';
}

class BuildMethodSpan {
  const BuildMethodSpan({
    required this.filePath,
    required this.startLine,
    required this.endLine,
    required this.lineCount,
  });

  final String filePath;
  final int startLine;
  final int endLine;
  final int lineCount;
}

class DartSourceAnalyzer {
  DartSourceAnalyzer._();

  static String normalizePath(String path) => path.replaceAll('\\', '/');

  static List<File> listLibDartFiles({String rootDir = 'lib'}) {
    final dir = Directory(rootDir);
    if (!dir.existsSync()) {
      return const [];
    }
    return dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  static bool isUiFile(String path) {
    final norm = normalizePath(path);
    return norm.endsWith('_view.dart') ||
        norm.contains('lib/widgets/') ||
        norm.contains('/widgets/');
  }

  static bool isServiceOrControllerFile(String path) {
    final norm = normalizePath(path);
    return norm.endsWith('_service.dart') ||
        norm.endsWith('_controller.dart') ||
        norm.endsWith('media_parser.dart') ||
        norm.endsWith('metadata_reader.dart');
  }

  static bool isTokenOrThemeFile(String path) {
    final norm = normalizePath(path);
    return norm.contains('lib/core/constants/') ||
        norm.contains('lib/core/theme/');
  }

  static List<BuildMethodSpan> findBuildMethods(File file) {
    final lines = file.readAsLinesSync();
    final spans = <BuildMethodSpan>[];
    final buildSig = RegExp(r'\bWidget\s+build\s*\(\s*BuildContext\b');

    for (var i = 0; i < lines.length; i++) {
      if (!buildSig.hasMatch(lines[i])) {
        continue;
      }
      var braceDepth = 0;
      var opened = false;
      var endIdx = i;

      for (var j = i; j < lines.length; j++) {
        final line = lines[j];
        for (var k = 0; k < line.length; k++) {
          final ch = line[k];
          if (ch == '{') {
            braceDepth++;
            opened = true;
          } else if (ch == '}') {
            braceDepth--;
            if (opened && braceDepth <= 0) {
              endIdx = j;
              break;
            }
          }
        }
        if (opened && braceDepth <= 0) {
          break;
        }
      }

      spans.add(
        BuildMethodSpan(
          filePath: normalizePath(file.path),
          startLine: i + 1,
          endLine: endIdx + 1,
          lineCount: endIdx - i + 1,
        ),
      );
    }

    return spans;
  }

  static List<SourceViolation> findHardcodedColors(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);
    final colorRegex = RegExp(
      r'\bColor\s*\(\s*0x[0-9A-Fa-f]+\s*\)|\bColor\.from(?:ARGB|RGBO)\s*\(|\bColors\.\w+',
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) {
        continue;
      }
      final match = colorRegex.firstMatch(line);
      if (match != null) {
        violations.add(
          SourceViolation(
            filePath: path,
            line: i + 1,
            category: 'HardcodedColor',
            detail: match.group(0)!,
          ),
        );
      }
    }
    return violations;
  }

  static List<SourceViolation> findHardcodedSpacingAndMagicNumbers(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);

    final patterns = [
      RegExp(r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\s*\([^)]*\b\d+(?:\.\d+)?\b'),
      RegExp(r'SizedBox\s*\([^)]*(?:width|height)\s*:\s*\d+(?:\.\d+)?\b'),
      RegExp(r'BorderRadius\.circular\s*\(\s*\d+(?:\.\d+)?\s*\)'),
      RegExp(r'Radius\.circular\s*\(\s*\d+(?:\.\d+)?\s*\)'),
      RegExp(r'\b(?:letterSpacing|radius)\s*:\s*\d+(?:\.\d+)?\b'),
      RegExp(r'\b(?:1024\s*\*\s*1024|3600|359999)\b'),
    ];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) {
        continue;
      }
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'HardcodedSpacingOrMagicNumber',
              detail: match.group(0)!.trim(),
            ),
          );
          break;
        }
      }
    }
    return violations;
  }

  static List<SourceViolation> findHardcodedFontSizes(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);
    final regex = RegExp(r'\bfontSize\s*:\s*\d+(?:\.\d+)?\b');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) {
        continue;
      }
      final match = regex.firstMatch(line);
      if (match != null) {
        violations.add(
          SourceViolation(
            filePath: path,
            line: i + 1,
            category: 'HardcodedFontSize',
            detail: match.group(0)!,
          ),
        );
      }
    }
    return violations;
  }

  static List<SourceViolation> findHardcodedUiStrings(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);
    final stringLiteralInUi = RegExp(
      r'''(?:Text|tooltip\s*:|labelText\s*:|hintText\s*:)\s*(?:\(\s*)?(['"])([^'"]+)\1''',
    );
    final standaloneUiLiteral = RegExp(r'''(['"])([^'"]*?[A-Za-zÄÖÜäöüß]{2,}[^'"]*?)\1''');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') ||
          trimmed.startsWith('import ') ||
          trimmed.startsWith('part ')) {
        continue;
      }
      final match = stringLiteralInUi.firstMatch(line);
      if (match != null) {
        final literal = match.group(2) ?? '';
        if (literal.contains(r'$') &&
            !RegExp(r'[A-Za-zÄÖÜäöüß]{3,}').hasMatch(
              literal.replaceAll(RegExp(r'\$\{?[\w.]+\}?'), ''),
            )) {
          continue;
        }
        violations.add(
          SourceViolation(
            filePath: path,
            line: i + 1,
            category: 'HardcodedUiString',
            detail: match.group(0)!.trim(),
          ),
        );
        continue;
      }

      // Catch multiline Text(\n 'Spur ${track.id}') or '${mb} MB' UI strings,
      // excluding mediaType comparisons and route/key identifiers.
      if (trimmed.contains('==') || trimmed.contains('!=')) {
        continue;
      }
      final litMatch = standaloneUiLiteral.firstMatch(line);
      if (litMatch != null) {
        final literal = litMatch.group(2) ?? '';
        final staticText =
            literal.replaceAll(RegExp(r'\$\{?[^}]+\}?'), '').trim();
        if (staticText.length >= 2 &&
            RegExp(r'[A-Za-zÄÖÜäöüß]{2,}').hasMatch(staticText) &&
            !RegExp(r'^(episode|movie|series)$').hasMatch(staticText)) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'HardcodedUiString',
              detail: litMatch.group(0)!.trim(),
            ),
          );
        }
      }
    }
    return violations;
  }

  static List<SourceViolation> findUiLogicSeparationViolations(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);

    if (isUiFile(path)) {
      final forbiddenImports = RegExp(
        r'''import\s+['"](?:dart:io|package:(?:sqlite3|sqflite|drift|path_provider|file_picker|window_manager)|.*core/storage/)''',
      );
      final forbiddenCalls = RegExp(
        r'\b(?:File|Directory)\s*\(|\bPlatform\.\w+|\bwindowManager\.\w+|\bFilePicker\.\w+',
      );

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (forbiddenImports.hasMatch(line)) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'ForbiddenUiImport',
              detail: line.trim(),
            ),
          );
        } else if (forbiddenCalls.hasMatch(line)) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'DirectIoOrSystemCallInUi',
              detail: line.trim(),
            ),
          );
        }
      }
    } else if (isServiceOrControllerFile(path) ||
        path.contains('lib/core/storage/')) {
      final forbiddenInBusiness = RegExp(
        r'''import\s+['"]package:(?:flutter/material\.dart|material_ui/material_ui\.dart)|\bBuildContext\b''',
      );
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (forbiddenInBusiness.hasMatch(line)) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'UiDependencyInBusinessLayer',
              detail: line.trim(),
            ),
          );
        }
      }
    }

    return violations;
  }

  static Set<String> detectMixedLayers(File file) {
    final content = file.readAsStringSync();
    final layers = <String>{};
    if (RegExp(r'\bWidget\s+build\s*\(').hasMatch(content)) {
      layers.add('UI');
    }
    if (RegExp(r'\bdb\.(?:select|execute)\s*\(').hasMatch(content)) {
      layers.add('Database');
    }
    if (RegExp(r'\b(?:File|Directory)\s*\(').hasMatch(content)) {
      layers.add('FileIO');
    }
    if (RegExp(r'\b(?:windowManager|FilePicker)\b').hasMatch(content)) {
      layers.add('PlatformSystem');
    }
    if (RegExp(r'\bPlayer\s*\(').hasMatch(content)) {
      layers.add('MediaEngine');
    }
    return layers;
  }

  static List<SourceViolation> findSyncIoCallsInUi(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);
    final syncIoRegex =
        RegExp(r'\.(?:existsSync|listSync|deleteSync|statSync)\s*\(');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      final match = syncIoRegex.firstMatch(line);
      if (match != null) {
        violations.add(
          SourceViolation(
            filePath: path,
            line: i + 1,
            category: 'SyncIoInUi',
            detail: match.group(0)!,
          ),
        );
      }
    }
    return violations;
  }

  static List<SourceViolation> findDirectPlatformOrNativeAccess(File file) {
    final lines = file.readAsLinesSync();
    final violations = <SourceViolation>[];
    final path = normalizePath(file.path);
    final forbiddenRegex = RegExp(
      r'''package:(?:window_manager|file_picker)/|\bNativePlayer\b''',
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      final match = forbiddenRegex.firstMatch(line);
      if (match != null) {
        violations.add(
          SourceViolation(
            filePath: path,
            line: i + 1,
            category: 'DirectNativeOrPlatformAccess',
            detail: line.trim(),
          ),
        );
      }
    }
    return violations;
  }

  static List<SourceViolation> findUnusedPublicTokens(List<File> libFiles) {
    const tokenFiles = {
      'lib/core/constants/app_colors.dart',
      'lib/core/constants/app_spacing.dart',
      'lib/core/constants/app_strings.dart',
      'lib/core/utils/formatters.dart',
    };
    final declRegex = RegExp(
      r'^\s*static\s+(?:const\s+\S+\s+|[\w<>?()]+\s+)([a-zA-Z][a-zA-Z0-9_]*)\s*(?:=|\(|=>)',
    );
    final contentsByPath = <String, String>{
      for (final f in libFiles) normalizePath(f.path): f.readAsStringSync(),
    };
    final violations = <SourceViolation>[];

    for (final file in libFiles) {
      final path = normalizePath(file.path);
      if (!tokenFiles.contains(path)) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = declRegex.firstMatch(lines[i]);
        if (match == null) continue;
        final name = match.group(1)!;
        if (name.startsWith('_')) continue;
        final wordRegex = RegExp('\\b$name\\b');
        var totalHits = 0;
        for (final content in contentsByPath.values) {
          totalHits += wordRegex.allMatches(content).length;
          if (totalHits > 1) break;
        }
        if (totalHits <= 1) {
          violations.add(
            SourceViolation(
              filePath: path,
              line: i + 1,
              category: 'UnusedPublicToken',
              detail: name,
            ),
          );
        }
      }
    }
    return violations;
  }
}
