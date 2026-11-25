String safePlaybackLabel(String? value, {String? username, String? password}) {
  if (value == null) return '';
  var text = value.replaceAll(
    RegExp(r'''(?:https?|rtsp|rtmp)://[^\s<>"']+''', caseSensitive: false),
    '[source]',
  );
  for (final secret in [username, password]) {
    if (secret != null && secret.isNotEmpty) {
      text = text.replaceAll(secret, '[redacted]');
    }
  }
  return text.length > 160 ? '${text.substring(0, 160)}...' : text;
}
