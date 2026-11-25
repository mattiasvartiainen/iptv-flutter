import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:iptv_flutter/platform/webos_playback_adapter.dart';
import 'package:iptv_flutter/services/playback/fake_playback.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/video_player_playback.dart';

void main() {
  const item = ContentItem(
    id: 'test-stream',
    title: 'Test stream',
    type: ContentType.live,
    streamUrl: 'https://example.com/live.m3u8',
    group: 'Tests',
  );

  test('fake adapter transitions from loading to playing', () async {
    final adapter = FakePlaybackAdapter(transitionDelay: Duration.zero);
    addTearDown(adapter.dispose);

    await adapter.load(item);

    expect(adapter.state.status, PlaybackStatus.playing);
    expect(adapter.state.item, item);
    expect(adapter.state.loadStartedAt, isNotNull);
    expect(adapter.state.playbackStartedAt, isNotNull);
  });

  test('fake adapter preserves item and telemetry across controls', () async {
    final adapter = FakePlaybackAdapter(transitionDelay: Duration.zero);
    addTearDown(adapter.dispose);
    await adapter.load(item);

    await adapter.seek(const Duration(minutes: 2));
    expect(adapter.state.position, const Duration(minutes: 2));
    expect(adapter.state.item, item);
    expect(adapter.state.playbackStartedAt, isNotNull);

    await adapter.pause();
    expect(adapter.state.status, PlaybackStatus.paused);
    expect(adapter.state.position, const Duration(minutes: 2));
    expect(adapter.state.item, item);

    await adapter.play();
    expect(adapter.state.status, PlaybackStatus.playing);
    expect(adapter.state.position, const Duration(minutes: 2));
  });

  test('fake initialization cancellation prevents late autoplay', () async {
    final adapter = FakePlaybackAdapter(
      transitionDelay: const Duration(milliseconds: 20),
    );
    addTearDown(adapter.dispose);
    final loading = adapter.load(item);
    await adapter.stop();
    await loading;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(adapter.state.status, PlaybackStatus.stopped);
    await adapter.play();
    expect(adapter.state.status, PlaybackStatus.playing);
  });

  test(
    'fake disposal cancels initialization and closes its stream once',
    () async {
      final adapter = FakePlaybackAdapter(
        transitionDelay: const Duration(milliseconds: 20),
      );
      final loading = adapter.load(item);
      final observed = <PlaybackState>[];
      final subscription = adapter.states.listen(observed.add);
      await Future<void>.delayed(Duration.zero);
      observed.clear();
      final disposal = adapter.dispose();
      expect(adapter.dispose(), same(disposal));
      await loading;
      await disposal;
      await adapter.play();
      await adapter.load(item);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(observed, isEmpty);
      await subscription.cancel();
    },
  );

  test('webOS profile selects the dedicated playback adapter', () {
    final adapter = platformProfileFor(
      AppPlatform.webos,
    ).createPlaybackAdapter();
    addTearDown(adapter.dispose);

    expect(adapter, isA<WebOsPlaybackAdapter>());
  });

  test('Android profile selects the video_player adapter', () {
    final adapter = platformProfileFor(
      AppPlatform.android,
    ).createPlaybackAdapter();
    addTearDown(adapter.dispose);

    expect(adapter, isA<VideoPlayerPlaybackAdapter>());
  });
}
