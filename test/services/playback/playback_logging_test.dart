import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_logging.dart';

void main() {
  test('position and duration updates do not count as log transitions', () {
    const previous = PlaybackState(
      status: PlaybackStatus.playing,
      position: Duration(seconds: 2),
      duration: Duration(minutes: 10),
    );
    const positionUpdate = PlaybackState(
      status: PlaybackStatus.playing,
      position: Duration(seconds: 3),
      duration: Duration(minutes: 10),
    );

    expect(isPlaybackLogTransition(previous, positionUpdate), isFalse);
  });

  test('status and buffering changes count as log transitions', () {
    const previous = PlaybackState(status: PlaybackStatus.playing);

    expect(
      isPlaybackLogTransition(
        previous,
        const PlaybackState(status: PlaybackStatus.paused),
      ),
      isTrue,
    );
    expect(
      isPlaybackLogTransition(
        previous,
        const PlaybackState(status: PlaybackStatus.playing, isBuffering: true),
      ),
      isTrue,
    );
  });
}
