import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_http_headers.dart';
import 'package:iptv_flutter/services/playback/video_player_playback.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native playback receives the shared desktop request headers', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _RecordingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final adapter = VideoPlayerPlaybackAdapter();
    addTearDown(() async {
      adapter.dispose();
      await platform.disposed.future;
      VideoPlayerPlatform.instance = originalPlatform;
    });

    const item = ContentItem(
      id: 'stream',
      title: 'Test stream',
      type: ContentType.live,
      streamUrl: 'https://example.com/live.m3u8',
      group: 'Tests',
    );
    await adapter.load(item);

    expect(platform.source?.uri, item.streamUrl);
    expect(platform.source?.sourceType, DataSourceType.network);
    expect(platform.source?.httpHeaders, playbackHttpHeaders);
    expect(platform.source?.httpHeaders['User-Agent'], 'IPTV-Flutter/0.1');
    expect(
      platform.source?.httpHeaders['Accept'],
      'application/x-mpegURL,application/vnd.apple.mpegurl,*/*',
    );
    expect(platform.playCalls, greaterThan(0));
    expect(adapter.state.status, PlaybackStatus.playing);
  });
}

class _RecordingVideoPlayerPlatform extends VideoPlayerPlatform {
  DataSource? source;
  int playCalls = 0;
  final disposed = Completer<void>();

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 1),
      size: const Size(1280, 720),
    ),
  );

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    disposed.complete();
  }
}
