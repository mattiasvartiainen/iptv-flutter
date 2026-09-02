import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';

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

  test('webOS selection does not use the desktop media backend', () {
    final adapter = createPlatformPlaybackAdapter(webOs: true);
    addTearDown(adapter.dispose);

    expect(adapter, isA<WebOsPlaybackAdapterStub>());
  });
}
