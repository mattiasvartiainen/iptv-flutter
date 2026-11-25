enum PlaybackErrorKind {
  accessDenied,
  notFound,
  timeout,
  unsupportedFormat,
  network,
  configuration,
  unknown,
}

class PlaybackConfigurationError extends StateError {
  PlaybackConfigurationError()
    : super('Playback requires a securely built webOS package.');
}

/// A classified media failure without native messages or credential URLs.
class PlaybackException implements Exception {
  const PlaybackException(this.kind);

  factory PlaybackException.from(Object error) => error is PlaybackException
      ? error
      : PlaybackException(playbackErrorKind(error));

  final PlaybackErrorKind kind;

  @override
  String toString() => 'PlaybackException(${kind.name})';
}

/// Preserves typed failures before classifying legacy/native error text.
PlaybackErrorKind playbackErrorKind(Object error) {
  if (error is PlaybackException) return error.kind;
  if (error is PlaybackConfigurationError) {
    return PlaybackErrorKind.configuration;
  }
  if (error is UnsupportedError) return PlaybackErrorKind.unknown;
  return classifyPlaybackError(error.toString());
}

PlaybackErrorKind classifyPlaybackError(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('401') ||
      text.contains('403') ||
      text.contains('unauthorized') ||
      text.contains('forbidden') ||
      text.contains('access denied')) {
    return PlaybackErrorKind.accessDenied;
  }
  if (text.contains('404') || text.contains('not found')) {
    return PlaybackErrorKind.notFound;
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return PlaybackErrorKind.timeout;
  }
  if (text.contains('unsupported') ||
      text.contains('codec') ||
      text.contains('demux')) {
    return PlaybackErrorKind.unsupportedFormat;
  }
  if (text.contains('network') ||
      text.contains('connection') ||
      text.contains('dns') ||
      text.contains('socket') ||
      text.contains('unreachable') ||
      text.contains('host lookup')) {
    return PlaybackErrorKind.network;
  }
  return PlaybackErrorKind.unknown;
}
