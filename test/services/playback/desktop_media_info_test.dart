import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/desktop_media_kit_playback.dart';
import 'package:iptv_flutter/services/playback/playback_labels.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('auto exposes only facts shared by possible source tracks', () {
    final info = desktopPlaybackMediaInfo(
      const PlayerState(
        tracks: Tracks(
          video: [
            VideoTrack('auto', null, null),
            VideoTrack('1', null, null, codec: 'h264', fps: 25),
          ],
          audio: [
            AudioTrack('auto', null, null),
            AudioTrack('1', null, 'en', codec: 'aac'),
            AudioTrack('2', null, 'sv', codec: 'aac'),
          ],
        ),
      ),
    );
    expect(info.fps, 25);
    expect(info.videoCodec, 'h264');
    expect(info.audioCodec, 'aac');
    final mixed = desktopPlaybackMediaInfo(
      const PlayerState(
        tracks: Tracks(
          audio: [
            AudioTrack('1', null, null, codec: 'aac'),
            AudioTrack('2', null, null, codec: 'ac3'),
          ],
        ),
      ),
    );
    expect(mixed.audioCodec, isEmpty);
  });
  test('stream facts come from reported params and selected source tracks', () {
    const video = VideoTrack('1', null, null, codec: 'h264', fps: 23.976);
    const audio = AudioTrack('2', 'English', 'en', codec: 'aac');
    final info = desktopPlaybackMediaInfo(
      const PlayerState(
        videoParams: VideoParams(w: 1920, h: 1080, pixelformat: 'yuv420p'),
        audioParams: AudioParams(format: 'float', channels: '5.1'),
        track: Track(video: video, audio: audio),
        tracks: Tracks(
          video: [video],
          audio: [audio],
          subtitle: [
            SubtitleTrack('no', null, null),
            SubtitleTrack('3', null, 'sv'),
          ],
        ),
      ),
    );
    expect(info.width, 1920);
    expect(info.height, 1080);
    expect(info.fps, 23.976);
    expect(info.videoCodec, 'h264');
    expect(info.audioCodec, 'aac');
    expect(info.channelLayout, '5.1');
    expect(info.subtitleTracks.map((track) => track.label), ['Off', 'sv']);
  });

  test('unknown codec/FPS/layout remain absent rather than guessed', () {
    final info = desktopPlaybackMediaInfo(
      const PlayerState(
        audioParams: AudioParams(format: 'float', channelCount: 6),
        videoParams: VideoParams(pixelformat: 'yuv420p'),
      ),
    );
    expect(info.fps, isNull);
    expect(info.videoCodec, isEmpty);
    expect(info.audioCodec, isEmpty);
    expect(info.channelLayout, isEmpty);
  });

  test('labels never expose URLs, known secrets or unbounded text', () {
    expect(
      safePlaybackLabel(
        'English https://example.invalid/user/pass/1 rtsp://user:pass@host/1',
      ),
      'English [source] [source]',
    );
    expect(
      safePlaybackLabel('user pass', username: 'user', password: 'pass'),
      '[redacted] [redacted]',
    );
    expect(safePlaybackLabel('x' * 1000).length, 163);
  });
}
