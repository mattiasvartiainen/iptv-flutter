enum PlaybackErrorKind {
  accessDenied,
  notFound,
  timeout,
  unsupportedFormat,
  network,
  unknown,
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
