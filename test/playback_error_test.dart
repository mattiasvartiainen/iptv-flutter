import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/playback_error.dart';

void main() {
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
