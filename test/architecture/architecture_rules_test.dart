import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_source_analyzer.dart';

void main() {
  final libFiles = DartSourceAnalyzer.listLibDartFiles();

  group('Architecture: Monoliths & God-Classes', () {
    test('UI widget/view files must not exceed 400 lines', () {
      final violations = <String>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path)) {
          continue;
        }
        final lineCount = file.readAsLinesSync().length;
        if (lineCount > 400) {
          violations.add('$path:1 ($lineCount lines > 400 max)');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'UI monoliths found:\n${violations.join('\n')}',
      );
    });

    test('Service and controller files must not exceed 500 lines', () {
      final violations = <String>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isServiceOrControllerFile(path)) {
          continue;
        }
        final lineCount = file.readAsLinesSync().length;
        if (lineCount > 500) {
          violations.add('$path:1 ($lineCount lines > 500 max)');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Service/controller monoliths found:\n${violations.join('\n')}',
      );
    });

    test('build() methods must not exceed 100 lines', () {
      final violations = <String>[];
      for (final file in libFiles) {
        for (final span in DartSourceAnalyzer.findBuildMethods(file)) {
          if (span.lineCount > 100) {
            violations.add(
              '${span.filePath}:${span.startLine}-${span.endLine} '
              '(${span.lineCount} lines > 100 max)',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Overlong build() methods found:\n${violations.join('\n')}',
      );
    });

    test('files must not mix 3 or more architectural layers (God-Class check)',
        () {
      final violations = <String>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (path.endsWith('main.dart')) {
          continue;
        }
        final layers = DartSourceAnalyzer.detectMixedLayers(file);
        if (layers.length >= 3) {
          violations.add('$path:1 mixes layers: ${layers.join(', ')}');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'God-classes detected:\n${violations.join('\n')}',
      );
    });
  });

  group('Architecture: Hardcoded UI Tokens', () {
    test('UI files must not contain hardcoded Color(...) or Colors.*', () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path) ||
            DartSourceAnalyzer.isTokenOrThemeFile(path)) {
          continue;
        }
        violations.addAll(DartSourceAnalyzer.findHardcodedColors(file));
      }
      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded colors in UI:\n${violations.join('\n')}',
      );
    });

    test('UI files must not contain hardcoded spacing, radii, or magic numbers',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path) ||
            DartSourceAnalyzer.isTokenOrThemeFile(path)) {
          continue;
        }
        violations.addAll(
          DartSourceAnalyzer.findHardcodedSpacingAndMagicNumbers(file),
        );
      }
      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded spacing/magic numbers in UI:\n${violations.join('\n')}',
      );
    });

    test('UI files must not contain hardcoded fontSize literals', () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path) ||
            DartSourceAnalyzer.isTokenOrThemeFile(path)) {
          continue;
        }
        violations.addAll(DartSourceAnalyzer.findHardcodedFontSizes(file));
      }
      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded font sizes in UI:\n${violations.join('\n')}',
      );
    });

    test('UI files must not contain hardcoded UI strings instead of AppStrings',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path) ||
            DartSourceAnalyzer.isTokenOrThemeFile(path)) {
          continue;
        }
        violations.addAll(DartSourceAnalyzer.findHardcodedUiStrings(file));
      }
      expect(
        violations,
        isEmpty,
        reason: 'Hardcoded UI strings:\n${violations.join('\n')}',
      );
    });
  });

  group('Architecture: Strict UI vs Business Logic Separation', () {
    test('UI files must not import storage/IO/window/picker or call File/Platform',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path)) {
          continue;
        }
        violations
            .addAll(DartSourceAnalyzer.findUiLogicSeparationViolations(file));
      }
      expect(
        violations,
        isEmpty,
        reason: 'UI/Logic separation violations in UI:\n${violations.join('\n')}',
      );
    });

    test('Business/Service/Storage files must not import Material UI or BuildContext',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (DartSourceAnalyzer.isUiFile(path)) {
          continue;
        }
        violations
            .addAll(DartSourceAnalyzer.findUiLogicSeparationViolations(file));
      }
      expect(
        violations,
        isEmpty,
        reason:
            'UI dependencies in business/service/storage layer:\n${violations.join('\n')}',
      );
    });

    test(
        'UI files must not call synchronous filesystem IO (existsSync/listSync/deleteSync/statSync)',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path)) {
          continue;
        }
        violations.addAll(DartSourceAnalyzer.findSyncIoCallsInUi(file));
      }
      expect(
        violations,
        isEmpty,
        reason: 'Sync filesystem IO in UI:\n${violations.join('\n')}',
      );
    });

    test(
        'UI and Controller files must not directly import window_manager, file_picker, or NativePlayer',
        () {
      final violations = <SourceViolation>[];
      for (final file in libFiles) {
        final path = DartSourceAnalyzer.normalizePath(file.path);
        if (!DartSourceAnalyzer.isUiFile(path) &&
            !path.endsWith('_controller.dart')) {
          continue;
        }
        violations
            .addAll(DartSourceAnalyzer.findDirectPlatformOrNativeAccess(file));
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Uncapsulated platform/native access:\n${violations.join('\n')}',
      );
    });

    test('Constant tokens and Formatters must have no unused public members',
        () {
      final violations = DartSourceAnalyzer.findUnusedPublicTokens(libFiles);
      expect(
        violations,
        isEmpty,
        reason: 'Unused public tokens/methods:\n${violations.join('\n')}',
      );
    });
  });
}
