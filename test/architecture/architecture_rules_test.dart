import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _knownPlatformViolations = <String, Set<String>>{};

final _platformPatterns = <String, RegExp>{
  'defaultTargetPlatform': RegExp(r'\bdefaultTargetPlatform\b'),
  'TargetPlatform': RegExp(r'\bTargetPlatform\.'),
  'Platform.is': RegExp(r'\bPlatform\.is[A-Z]\w*'),
  'kIsWeb': RegExp(r'\bkIsWeb\b'),
  'fromEnvironment': RegExp(r'\b(?:bool|int|String)\.fromEnvironment\s*\('),
};

final _forbiddenUiImport = RegExp(
  r'''^\s*import\s+['"](?:dart:io|package:(?:sqflite(?:_[^/]+)?|sqlite3|media_kit(?:_[^/]+)?|video_player(?:_[^/]+)?)/|[^'"]*(?:sqlite_catalog_repository|storage_bootstrap)\.dart)['"]''',
  multiLine: true,
);

final _forbiddenMaterialImport = RegExp(
  r'''^\s*import\s+['"]package:flutter/material\.dart['"]''',
  multiLine: true,
);

void main() {
  final sources = _readDartSources();

  test('platform selection stays within the known boundary exceptions', () {
    final violations = <String, Set<String>>{};
    for (final entry in sources.entries) {
      if (p.posix.isWithin('lib/platform', entry.key)) continue;
      final matches = _platformPatterns.entries
          .where((pattern) => pattern.value.hasMatch(entry.value))
          .map((pattern) => pattern.key)
          .toSet();
      if (matches.isNotEmpty) violations[entry.key] = matches;
    }

    expect(
      violations.keys.toSet(),
      equals(_knownPlatformViolations.keys.toSet()),
      reason: 'Update the allowlist when platform checks are moved or added.',
    );
    for (final entry in _knownPlatformViolations.entries) {
      expect(
        violations[entry.key],
        equals(entry.value),
        reason: 'Review platform references in ${entry.key}.',
      );
    }
  });

  test('UI files do not import platform or persistence implementations', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final isUiFile = const [
        'lib/features',
        'lib/ui',
      ].any((directory) => p.posix.isWithin(directory, entry.key));
      if (isUiFile && _forbiddenUiImport.hasMatch(entry.value)) {
        violations.add(entry.key);
      }
    }

    expect(violations, isEmpty);
  });

  test('state and services do not import Flutter Material widgets', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final isLogicFile = const [
        'lib/state',
        'lib/services',
      ].any((directory) => p.posix.isWithin(directory, entry.key));
      if (isLogicFile && _forbiddenMaterialImport.hasMatch(entry.value)) {
        violations.add(entry.key);
      }
    }

    expect(violations, isEmpty);
  });

  test('player presentation policy stays independent of playback behavior', () {
    for (final path in [
      'lib/features/player/player_layout.dart',
      'lib/ui/theme/player_theme.dart',
    ]) {
      expect(
        RegExp(
          r'''^\s*import\s+['"][^'"]*(?:services/[^'"]*|player_controller\.dart)['"]''',
          multiLine: true,
        ).hasMatch(sources[path]!),
        isFalse,
        reason: '$path must not depend on playback behavior.',
      );
    }
    for (final path in [
      'lib/features/player/player_controller.dart',
      'lib/services/playback/playback_session.dart',
    ]) {
      expect(
        RegExp(
          r'''^\s*import\s+['"][^'"]*(?:player_layout|player_theme|app_theme)\.dart['"]''',
          multiLine: true,
        ).hasMatch(sources[path]!),
        isFalse,
        reason: '$path must not depend on presentation policy.',
      );
    }
  });
}

Map<String, String> _readDartSources() {
  final root = Directory.current.absolute.path;
  final libDirectory = Directory(p.join(root, 'lib'));
  return {
    for (final entity in libDirectory.listSync(recursive: true))
      if (entity is File && p.extension(entity.path) == '.dart')
        p.posix.joinAll(p.split(p.relative(entity.path, from: root))): entity
            .readAsStringSync(),
  };
}
