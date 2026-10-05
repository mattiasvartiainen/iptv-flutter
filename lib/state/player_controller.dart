import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../models/content_item.dart';
import '../services/logging/app_logger.dart';
import '../services/playback/playback_adapter.dart';
import '../services/security/url_redaction.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.playbackAdapter,
    required this.navigationController,
    AppLogger logger = const DebugAppLogger(),
  }) : _logger = logger {
    _observedRoute = navigationController.currentRoute;
    navigationController.addListener(_handleNavigationChanged);
  }

  static const ContentItem playbackSpikeItem = ContentItem(
    id: 'playback-spike-live-hls',
    title: 'Playback Spike - Live HLS',
    type: ContentType.live,
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    group: 'Playback Spike',
    description:
        'Public HLS stream used to validate player integration before full catalog wiring.',
  );

  final PlaybackAdapter playbackAdapter;
  final NavigationController navigationController;
  final AppLogger _logger;
  late AppRoute _observedRoute;
  int _playbackLoadGeneration = 0;

  Future<void> openPlayer(ContentItem item) => _openPlayerFor(item);

  Future<void> openPlaybackSpike() => _openPlayerFor(playbackSpikeItem);

  Future<void> _openPlayerFor(ContentItem item) async {
    final generation = ++_playbackLoadGeneration;
    final route = PlayerRoute(item);
    navigationController.push(route);
    try {
      await playbackAdapter.load(item);
      if (generation != _playbackLoadGeneration ||
          !identical(navigationController.currentRoute, route)) {
        await _stopPlayback();
      }
    } catch (error, stackTrace) {
      _logger.error(
        'playback_load_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText(stackTrace.toString()),
        ),
      );
    }
  }

  void _handleNavigationChanged() {
    final route = navigationController.currentRoute;
    if (_observedRoute is PlayerRoute && !identical(_observedRoute, route)) {
      _playbackLoadGeneration++;
      unawaited(_stopPlayback());
    }
    _observedRoute = route;
  }

  Future<void> _stopPlayback() async {
    try {
      await playbackAdapter.stop();
    } catch (error, stackTrace) {
      _logger.error(
        'playback_stop_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    navigationController.removeListener(_handleNavigationChanged);
    playbackAdapter.dispose();
    super.dispose();
  }
}
