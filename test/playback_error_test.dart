import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/playback_error.dart';

void main() {
  for (final kind in PlaybackErrorKind.values) {
    test('typed $kind classification survives safe exception text', () {
      final error = PlaybackException(kind);
      expect(playbackErrorKind(error), kind);
      expect(PlaybackException.from(error), same(error));
      expect(error.toString(), 'PlaybackException(${kind.name})');
    });
  }

  test('safe native error conversion retains only the classification', () {
    final native = StateError(
      'HTTP 403 https://example.com/live/user/pass?token=test',
    );
    final error = PlaybackException.from(native);
    expect(error.kind, PlaybackErrorKind.accessDenied);
    expect(error.toString(), isNot(contains('https')));
    expect(error.toString(), isNot(contains('pass')));
    expect(
      playbackErrorKind(PlaybackConfigurationError()),
      PlaybackErrorKind.configuration,
    );
    expect(
      playbackErrorKind(UnsupportedError('Unsupported volume')),
      PlaybackErrorKind.unknown,
    );
  });

  test('classifies access errors before generic network failures', () {
    expect(
      classifyPlaybackError('HTTP 403: network request forbidden'),
      PlaybackErrorKind.accessDenied,
    );
    expect(
      classifyPlaybackError('401 Unauthorized'),
      PlaybackErrorKind.accessDenied,
    );
  });

  test('classifies missing streams, timeouts, and unsupported formats', () {
    expect(
      classifyPlaybackError('HTTP 404: not found'),
      PlaybackErrorKind.notFound,
    );
    expect(
      classifyPlaybackError('Connection timed out'),
      PlaybackErrorKind.timeout,
    );
    expect(
      classifyPlaybackError('No supported codec or demuxer'),
      PlaybackErrorKind.unsupportedFormat,
    );
  });

  test('classifies common network failures and falls back to unknown', () {
    expect(
      classifyPlaybackError('DNS lookup failed for stream host'),
      PlaybackErrorKind.network,
    );
    expect(
      classifyPlaybackError('Unexpected player state'),
      PlaybackErrorKind.unknown,
    );
  });
}
