import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'source_dependencies.dart';

const _knownPlatformViolations = <String, Set<String>>{};

final _platformPatterns = <String, RegExp>{
  'defaultTargetPlatform': RegExp(r'\bdefaultTargetPlatform\b'),
  'TargetPlatform': RegExp(r'\bTargetPlatform\.'),
  'Platform.is': RegExp(r'\bPlatform\.is[A-Z]\w*'),
  'kIsWeb': RegExp(r'\bkIsWeb\b'),
  'fromEnvironment': RegExp(r'\b(?:bool|int|String)\.fromEnvironment\s*\('),
};

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

  test('UI does not expose native/data implementations through barrels', () {
    final violations = <String>[];
    for (final entry in sources.entries) {
      final isUiFile =
          entry.key == 'lib/app.dart' ||
          const [
            'lib/features',
            'lib/ui',
          ].any((directory) => p.posix.isWithin(directory, entry.key));
      if (!isUiFile) continue;
      for (final target in exposedDependencies(sources, entry.key)) {
        if (isForbiddenUiDependency(target)) {
          violations.add('${entry.key} -> $target');
        }
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
      if (isLogicFile &&
          exposedDependencies(
            sources,
            entry.key,
          ).contains('package:flutter/material.dart')) {
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
        exposedDependencies(sources, path).any(
          (target) =>
              p.posix.isWithin('lib/services', target) ||
              target == 'lib/features/player/player_controller.dart',
        ),
        isFalse,
        reason: '$path must not depend on playback behavior.',
      );
    }
    for (final path in [
      'lib/features/player/player_controller.dart',
      'lib/services/playback/playback_session.dart',
    ]) {
      expect(
        exposedDependencies(sources, path).any(
          (target) => const [
            'lib/features/player/player_layout.dart',
            'lib/ui/theme/player_theme.dart',
            'lib/ui/theme/app_theme.dart',
          ].contains(target),
        ),
        isFalse,
        reason: '$path must not depend on presentation policy.',
      );
    }
  });

  test('playback compatibility barrel exposes only contracts and errors', () {
    expect(
      exposedDependencies(
        sources,
        'lib/services/playback/playback_adapter.dart',
      ),
      {
        'lib/services/playback/playback_contract.dart',
        'lib/services/playback/playback_error.dart',
      },
    );
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
