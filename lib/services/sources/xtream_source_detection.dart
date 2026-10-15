class XtreamServerAddress {
  const XtreamServerAddress._(this.baseUri, this.requiresSchemeConfirmation);

  final Uri baseUri;
  final bool requiresSchemeConfirmation;
}

class XtreamSourceCandidate {
  const XtreamSourceCandidate._({
    required this.originalUrl,
    required this.apiEndpoint,
    required this.username,
    required this.password,
    required this.requiresEndpointConfirmation,
  });

  final String originalUrl;
  final Uri apiEndpoint;
  final String username;
  final String password;
  final bool requiresEndpointConfirmation;
}

XtreamServerAddress? parseXtreamServerAddress(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final hasExplicitScheme = value.contains('://');
  final uri = _httpUri(hasExplicitScheme ? value : 'https://$value');
  if (uri == null || uri.hasQuery) return null;
  return XtreamServerAddress._(uri, !hasExplicitScheme);
}

XtreamSourceCandidate? detectXtreamSourceUrl(String input) {
  final uri = _httpUri(input.trim());
  if (uri == null) return null;
  try {
    final parameters = uri.queryParametersAll;
    final usernames = parameters['username'];
    final passwords = parameters['password'];
    if (usernames == null ||
        usernames.length != 1 ||
        passwords == null ||
        passwords.length != 1 ||
        usernames.single.trim().isEmpty ||
        passwords.single.isEmpty) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final endpoint = segments.last;
    if (!const ['.php', '.cgi', '.asp', '.aspx'].any(endpoint.endsWith)) {
      return null;
    }
    final recognized = endpoint == 'get.php' || endpoint == 'player_api.php';
    return XtreamSourceCandidate._(
      originalUrl: input,
      apiEndpoint: Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        pathSegments: [...segments.take(segments.length - 1), 'player_api.php'],
      ),
      username: usernames.single,
      password: passwords.single,
      requiresEndpointConfirmation: !recognized,
    );
  } on FormatException {
    return null;
  }
}

Uri? _httpUri(String value) {
  try {
    if (value.contains(RegExp(r'\s'))) return null;
    if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    if (uri.pathSegments.any(
      (segment) =>
          segment.contains('/') ||
          segment.contains('\\') ||
          segment.contains(RegExp(r'[\x00-\x1f\x7f]')),
    )) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}
