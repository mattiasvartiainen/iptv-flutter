String redactUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '[redacted URL]';
  }

  final pathSegments = [...uri.pathSegments];
  for (var index = 0; index < pathSegments.length; index++) {
    final segment = pathSegments[index].toLowerCase();
    if ((segment == 'live' || segment == 'movie' || segment == 'series') &&
        index + 2 < pathSegments.length) {
      pathSegments[index + 1] = '[redacted]';
      pathSegments[index + 2] = '[redacted]';
      index += 2;
    }
  }

  return uri
      .replace(
        userInfo: '',
        pathSegments: pathSegments,
        queryParameters: uri.hasQuery
            ? {
                for (final key in uri.queryParametersAll.keys)
                  key: const ['[redacted]'],
              }
            : null,
      )
      .toString();
}

String redactSensitiveText(String value) {
  final urlPattern = RegExp(
    r'''(?:https?|rtsp|rtmp)://[^\s<>"']+''',
    caseSensitive: false,
  );
  return value.replaceAllMapped(urlPattern, (match) => redactUrl(match[0]!));
}
