import 'package:flutter_test/flutter_test.dart';

import 'source_dependencies.dart';

void main() {
  test('reads imports, exports, parts and every conditional branch', () {
    final dependencies = sourceDependencies('''
      import 'contract.dart'
          if (dart.library.io == 'true') 'native.dart'
          if (dart.library.html) "web.dart" show Player;
      export
        'package:iptv_flutter/services/playback/playback_contract.dart';
      part 'part.dart';
      part of 'owner.dart';
    ''');
    expect(dependencies.map((d) => (d.kind, d.uri)), [
      ('import', 'contract.dart'),
      ('import', 'native.dart'),
      ('import', 'web.dart'),
      (
        'export',
        'package:iptv_flutter/services/playback/playback_contract.dart',
      ),
      ('part', 'part.dart'),
    ]);
  });

  test('comments and string contents are not dependencies', () {
    expect(
      sourceDependencies('''
        // import 'bad.dart';
        /* export 'bad.dart'; */
        /* nested /* comment */ export 'bad.dart'; */
        const text = "import 'bad.dart';";
        const multiline = """export 'bad.dart';""";
        import /* comment */ r'good.dart'; export "also_good.dart";
      ''').map((d) => d.uri),
      ['good.dart', 'also_good.dart'],
    );
  });

  test('resolves relative and self-package paths to the same local key', () {
    expect(
      resolveDependency('lib/features/player/screen.dart', '../../api.dart'),
      'lib/api.dart',
    );
    expect(
      resolveDependency(
        'lib/features/player/screen.dart',
        'package:iptv_flutter/api.dart',
      ),
      'lib/api.dart',
    );
    expect(
      resolveDependency(
        'lib/api.dart',
        'package:video_player/video_player.dart',
      ),
      'package:video_player/video_player.dart',
    );
  });

  test('detects nested export leaks and terminates on export cycles', () {
    final sources = {
      'lib/ui/screen.dart': "import '../api.dart';",
      'lib/api.dart': "export 'nested.dart';",
      'lib/nested.dart':
          "export 'api.dart'; export 'package:video_player/video_player.dart';",
    };
    final targets = exposedDependencies(sources, 'lib/ui/screen.dart');
    expect(targets.where(isForbiddenUiDependency), [
      'package:video_player/video_player.dart',
    ]);
  });

  test('conditional and part exports cannot bypass boundary checks', () {
    final sources = {
      'lib/ui/screen.dart': "export '../api.dart';",
      'lib/api.dart':
          "export 'safe.dart' if (dart.library.io) 'native.dart'; part 'api_part.dart';",
      'lib/safe.dart': '',
      'lib/native.dart': "export 'package:http/http.dart';",
      'lib/api_part.dart': "export 'package:sqflite/sqlite_api.dart';",
    };
    expect(
      exposedDependencies(
        sources,
        'lib/ui/screen.dart',
      ).where(isForbiddenUiDependency).toSet(),
      {'package:http/http.dart', 'package:sqflite/sqlite_api.dart'},
    );
  });

  test('safe contract exports pass without traversing private imports', () {
    final sources = {
      'lib/ui/screen.dart': "import '../api.dart';",
      'lib/api.dart': "import 'private.dart'; export 'contract.dart';",
      'lib/private.dart': "import 'package:sqflite/sqflite.dart';",
      'lib/contract.dart': "export 'errors.dart';",
      'lib/errors.dart': '',
    };
    expect(exposedDependencies(sources, 'lib/ui/screen.dart'), {
      'lib/api.dart',
      'lib/contract.dart',
      'lib/errors.dart',
    });
  });

  test('missing local files fail rather than silently skipping the rule', () {
    expect(
      () => exposedDependencies({
        'lib/ui/screen.dart': "import '../missing.dart';",
      }, 'lib/ui/screen.dart'),
      throwsStateError,
    );
  });

  test('Material and presentation policy exports remain visible to rules', () {
    final sources = {
      'lib/services/consumer.dart': "import '../api.dart';",
      'lib/api.dart':
          "export 'package:flutter/material.dart';"
          " export 'ui/theme/player_theme.dart';",
      'lib/ui/theme/player_theme.dart': '',
    };
    expect(exposedDependencies(sources, 'lib/services/consumer.dart'), {
      'lib/api.dart',
      'package:flutter/material.dart',
      'lib/ui/theme/player_theme.dart',
    });
  });

  test('unsupported nonliteral URI spellings fail explicitly', () {
    for (final source in [r"import 'a\$b.dart';", r"import '${name}.dart';"]) {
      expect(() => sourceDependencies(source), throwsFormatException);
    }
  });

  test('native packages and concrete implementations are blocked', () {
    for (final path in [
      'dart:io',
      'package:video_player_drm/video_player.dart',
      'package:sqflite_common/sqlite_api.dart',
      'package:media_kit_video/media_kit_video.dart',
      'package:dio/dio.dart',
      'package:flutter_secure_storage/flutter_secure_storage.dart',
      'lib/platform/webos_playback_adapter.dart',
      'lib/platform/platform_profile.dart',
      'lib/platform/new_native_adapter.dart',
      'lib/services/playback/video_player_playback.dart',
      'lib/services/playback/fake_playback.dart',
      'lib/services/metadata/sqlite_movie_metadata_repository.dart',
    ]) {
      expect(isForbiddenUiDependency(path), isTrue, reason: path);
    }
    for (final path in [
      'package:flutter/widgets.dart',
      'lib/platform/platform_capabilities.dart',
      'lib/platform/app_environment.dart',
      'lib/services/playback/playback_contract.dart',
      'lib/services/catalog/catalog_query_service.dart',
    ]) {
      expect(isForbiddenUiDependency(path), isFalse, reason: path);
    }
  });
}
