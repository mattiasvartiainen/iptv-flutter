import '../settings/settings_repository.dart' show PlaylistSourceConfig;
import 'source_contracts.dart';
import 'xtream_source_detection.dart';

class SourceVerificationCandidate {
  const SourceVerificationCandidate({
    required this.endpoint,
    required this.username,
    required this.password,
    required this.requiresConfirmation,
  });

  final Uri endpoint;
  final String username;
  final String password;
  final bool requiresConfirmation;

  String get host => endpoint.host;
  bool get insecure => endpoint.scheme == 'http';
}

SourceVerificationCandidate? sourceVerificationCandidate(
  PlaylistSourceConfig config,
) {
  if (config.kind == PlaylistSourceKind.url) {
    final detected = detectXtreamSourceUrl(config.url ?? '');
    if (detected == null) return null;
    return SourceVerificationCandidate(
      endpoint: detected.apiEndpoint,
      username: detected.username,
      password: detected.password,
      requiresConfirmation:
          detected.requiresEndpointConfirmation ||
          detected.apiEndpoint.scheme == 'http',
    );
  }
  final address = parseXtreamServerAddress(config.server ?? '');
  final username = config.username?.trim() ?? '';
  final password = config.password ?? '';
  if (address == null || username.isEmpty || password.isEmpty) return null;
  final base = address.baseUri;
  final segments = base.pathSegments.toList();
  while (segments.isNotEmpty && segments.last.isEmpty) {
    segments.removeLast();
  }
  return SourceVerificationCandidate(
    endpoint: Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: [...segments, 'player_api.php'],
    ),
    username: username,
    password: password,
    requiresConfirmation:
        address.requiresSchemeConfirmation || base.scheme == 'http',
  );
}
