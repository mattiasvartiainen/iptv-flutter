import 'package:path/path.dart' as p;

final _tokens = RegExp(
  r'''//[^\r\n]*|/\*[\s\S]*?\*/|r?"""[\s\S]*?"""|r?'''
  "'''[\\s\\S]*?'''|"
  r'''r?"(?:\\.|[^"\\])*"|r?'(?:\\.|[^'\\])*'|[A-Za-z_]\w*|[^\s]''',
);

class SourceDependency {
  const SourceDependency(this.kind, this.uri);
  final String kind;
  final String uri;
}

List<SourceDependency> sourceDependencies(String source) {
  final tokens = <String>[];
  var commentEnd = 0;
  for (final match in _tokens.allMatches(source)) {
    if (match.start < commentEnd) continue;
    final token = match.group(0)!;
    if (token.startsWith('//')) continue;
    if (token.startsWith('/*')) {
      var depth = 0;
      for (final marker in RegExp(r'/\*|\*/').allMatches(source, match.start)) {
        depth += marker.group(0) == '/*' ? 1 : -1;
        if (depth == 0) {
          commentEnd = marker.end;
          break;
        }
      }
      if (depth != 0) throw FormatException('Unterminated source comment.');
      continue;
    }
    tokens.add(token);
  }
  final result = <SourceDependency>[];
  for (var i = 0; i < tokens.length; i++) {
    final kind = tokens[i];
    if (!const ['import', 'export', 'part'].contains(kind)) continue;
    if (i + 1 < tokens.length && tokens[i + 1] == 'of') continue;
    var firstUri = true;
    for (i++; i < tokens.length && tokens[i] != ';'; i++) {
      final token = tokens[i];
      final literal = token.startsWith('r') ? token.substring(1) : token;
      if (!literal.startsWith("'") && !literal.startsWith('"')) continue;
      if (!firstUri && tokens[i - 1] != ')') continue;
      final quoteLength = literal.startsWith("'''") || literal.startsWith('"""')
          ? 3
          : 1;
      final uri = literal.substring(quoteLength, literal.length - quoteLength);
      if (uri.contains(r'\') || uri.contains(r'$')) {
        throw FormatException(
          'Architecture checks require literal library URIs.',
        );
      }
      result.add(SourceDependency(kind, uri));
      firstUri = false;
    }
  }
  return result;
}

String resolveDependency(String sourcePath, String uri) {
  final parsed = Uri.parse(uri);
  if (parsed.scheme == 'package' &&
      parsed.pathSegments.first == 'iptv_flutter') {
    return p.posix.joinAll(['lib', ...parsed.pathSegments.skip(1)]);
  }
  if (parsed.hasScheme) return uri;
  return p.posix.normalize(
    p.posix.join(p.posix.dirname(sourcePath), Uri.decodeComponent(uri)),
  );
}

/// Finds exposed dependencies, following local exports/parts, not all imports.
///
/// A contract may import an implementation internally without exporting it.
/// This is a source-level guard, not type resolution or whole-program analysis.
Set<String> exposedDependencies(Map<String, String> sources, String root) {
  final exposed = <String>{};
  final pending = sourceDependencies(
    sources[root]!,
  ).map((dependency) => resolveDependency(root, dependency.uri)).toList();
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!exposed.add(path)) continue;
    final source = sources[path];
    if (source == null) {
      if (p.posix.isWithin('lib', path)) {
        throw StateError('Unresolved local architecture dependency: $path');
      }
      continue;
    }
    pending.addAll(
      sourceDependencies(source)
          .where((dependency) => dependency.kind != 'import')
          .map((dependency) => resolveDependency(path, dependency.uri)),
    );
  }
  return exposed;
}

bool isForbiddenUiDependency(String path) {
  if (path == 'dart:io') return true;
  if (p.posix.isWithin('lib/platform', path) &&
      !const {
        'lib/platform/app_environment.dart',
        'lib/platform/platform_capabilities.dart',
      }.contains(path)) {
    return true;
  }
  if (RegExp(
    r'^package:(?:sqflite(?:_[^/]+)?|sqlite3|media_kit(?:_[^/]+)?|video_player(?:_[^/]+)?|http|dio|flutter_secure_storage(?:_[^/]+)?|shared_preferences(?:_[^/]+)?|path_provider(?:_[^/]+)?)/',
  ).hasMatch(path)) {
    return true;
  }
  return RegExp(
    r'(?:^|/)(?:sqlite_[^/]+|storage_bootstrap|database_adapter|storage_migrations|secure_storage_service|desktop_media_kit_playback|video_player_playback|fake_playback|webos_playback_adapter|windows_playlist_secret_store|telemetry_settings_store)\.dart$',
  ).hasMatch(path);
}
