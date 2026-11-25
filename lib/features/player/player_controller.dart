import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/navigation/app_route.dart';
import '../../app/navigation/navigation_controller.dart';
import '../../models/content_item.dart';
import '../../services/catalog/favorite_repository.dart';
import '../../services/logging/app_logger.dart';
import '../../services/playback/playback_contract.dart';
import '../../services/playback/playback_labels.dart';
import '../../services/playback/playback_session.dart';
import '../../services/security/url_redaction.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required PlaybackAdapter playbackAdapter,
    required this.navigationController,
    AppLogger logger = const DebugAppLogger(),
    this.favorites,
  }) : playbackAdapter = PlaybackSession(playbackAdapter, logger: logger),
       _logger = logger,
       _playbackState = ValueNotifier<PlaybackState>(playbackAdapter.state) {
    _observedRoute = navigationController.currentRoute;
    navigationController.addListener(_handleNavigationChanged);
    _statesSubscription = this.playbackAdapter.states.listen(
      _handlePlaybackState,
    );
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleStateChanged,
    );
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
  final FavoriteRepository? favorites;
  bool? _favorite;
  bool _favoriteBusy = false;
  bool _favoriteLoading = false;
  String? _controlError;
  bool get canFavorite =>
      favorites != null &&
      _playbackState.value.item?.catalogPlaylistId != null &&
      _playbackState.value.item?.catalogItemKey != null;
  bool? get favorite => _favorite;
  bool get favoriteBusy => _favoriteBusy || _favoriteLoading;
  String? get controlError => _controlError;
  int get playbackSession => _playbackLoadGeneration;
  final ValueNotifier<PlaybackState> _playbackState;
  late final AppLifecycleListener _lifecycleListener;
  late AppRoute _observedRoute;
  late final StreamSubscription<PlaybackState> _statesSubscription;
  int _playbackLoadGeneration = 0;
  int? _backgroundedLoadGeneration;
  String? _backgroundedItemId;
  bool _isBackgrounded = false;
  bool _resumeVodOnForeground = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  Object? _backHandlerOwner;
  bool Function()? _backRequestHandler;

  ValueListenable<PlaybackState> get playbackState => _playbackState;

  /// The completion of native cleanup after synchronous controller disposal.
  Future<void> get disposalComplete => _disposeFuture ?? Future<void>.value();

  PlaybackCapabilities get capabilities => playbackAdapter.capabilities;

  Widget? get videoView => _disposed ? null : playbackAdapter.buildVideoView();

  void registerBackRequestHandler(Object owner, bool Function() handler) {
    _backHandlerOwner = owner;
    _backRequestHandler = handler;
  }

  void unregisterBackRequestHandler(Object owner) {
    if (!identical(_backHandlerOwner, owner)) return;
    _backHandlerOwner = null;
    _backRequestHandler = null;
  }

  bool handleBackRequest() => _backRequestHandler?.call() ?? false;

  Future<void> openPlayer(ContentItem item) {
    if (_disposed) return Future<void>.value();
    navigationController.push(PlayerRoute(item));
    return open(item);
  }

  Future<void> openPlaybackSpike() => openPlayer(playbackSpikeItem);

  Future<void> open(ContentItem item) async {
    if (_disposed) return;
    final generation = ++_playbackLoadGeneration;
    _favorite = null;
    _favoriteBusy = false;
    _favoriteLoading = false;
    _controlError = null;
    notifyListeners();
    unawaited(_loadFavorite(item, generation));
    try {
      final loading = playbackAdapter.load(item);
      if (_isBackgrounded) await _stopPlayback();
      await loading;
      if (_disposed || generation != _playbackLoadGeneration) return;
      _handlePlaybackState(playbackAdapter.state);
      final currentRoute = navigationController.currentRoute;
      if (currentRoute is! PlayerRoute || currentRoute.item.id != item.id) {
        await _stopPlayback();
      } else if (_isBackgrounded &&
          playbackAdapter.state.status == PlaybackStatus.playing) {
        if (item.type == ContentType.live) {
          await _stopPlayback();
        } else {
          await pause();
        }
      }
    } catch (error, stackTrace) {
      if (_disposed || generation != _playbackLoadGeneration) return;
      if (error is UnsupportedError) {
        await _stopPlayback();
        if (_disposed || generation != _playbackLoadGeneration) return;
      }
      _recordFailure('playback_load_failed', error, stackTrace, item: item);
    }
  }

  Future<void> togglePlayPause() async {
    if (!capabilities.supportsPause) return;
    if (_playbackState.value.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    await _runCommand('playback_play_failed', playbackAdapter.play);
  }

  Future<void> pause() async {
    if (!capabilities.supportsPause) return;
    await _runCommand('playback_pause_failed', playbackAdapter.pause);
  }

  Future<void> seekBy(Duration offset) async {
    if (!capabilities.supportsSeek) return;
    var target = _playbackState.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = _playbackState.value.duration;
    if (duration != null && target > duration) target = duration;
    await _runCommand(
      'playback_seek_failed',
      () => playbackAdapter.seek(target),
    );
  }

  Future<void> seekTo(Duration target) async {
    if (!capabilities.supportsSeek) return;
    final duration = _playbackState.value.duration;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _runCommand(
      'playback_seek_failed',
      () => playbackAdapter.seek(target),
    );
  }

  Future<void> _loadFavorite(ContentItem item, int generation) async {
    final repository = favorites;
    final playlist = item.catalogPlaylistId;
    final key = item.catalogItemKey;
    if (repository == null || playlist == null || key == null) return;
    _favoriteLoading = true;
    notifyListeners();
    try {
      final value = await repository.isFavorite(
        playlistId: playlist,
        itemKey: key,
      );
      if (_disposed || generation != _playbackLoadGeneration) return;
      _favorite = value;
      notifyListeners();
    } catch (error, stack) {
      if (_disposed || generation != _playbackLoadGeneration) return;
      _controlFailure(
        'player_favorite_load_failed',
        'Could not load favourite status.',
        error,
        stack,
      );
    } finally {
      if (!_disposed && generation == _playbackLoadGeneration) {
        _favoriteLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggleFavorite() async {
    if (_disposed || !canFavorite || favoriteBusy) return;
    final item = _playbackState.value.item!;
    final generation = _playbackLoadGeneration;
    _favoriteBusy = true;
    _controlError = null;
    notifyListeners();
    try {
      final current =
          _favorite ??
          await favorites!.isFavorite(
            playlistId: item.catalogPlaylistId!,
            itemKey: item.catalogItemKey!,
          );
      await favorites!.setFavorite(
        playlistId: item.catalogPlaylistId!,
        itemKey: item.catalogItemKey!,
        favorite: !current,
      );
      if (!_disposed && generation == _playbackLoadGeneration) {
        _favorite = !current;
      }
    } catch (error, stack) {
      if (!_disposed && generation == _playbackLoadGeneration) {
        _controlFailure(
          'player_favorite_save_failed',
          'Could not update favourites. Please try again.',
          error,
          stack,
        );
      }
    } finally {
      if (!_disposed && generation == _playbackLoadGeneration) {
        _favoriteBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> selectTrack(String id, {required bool subtitle}) async {
    if (_disposed) return false;
    final adapter = playbackAdapter;
    if (adapter is! PlaybackTrackAdapter ||
        !(subtitle
            ? capabilities.supportsSubtitleTracks
            : capabilities.supportsAudioTracks)) {
      return false;
    }
    final generation = _playbackLoadGeneration;
    _controlError = null;
    final tracks = adapter as PlaybackTrackAdapter;
    try {
      if (subtitle) {
        await tracks.selectSubtitleTrack(id);
      } else {
        await tracks.selectAudioTrack(id);
      }
      if (_disposed || generation != _playbackLoadGeneration) return false;
      _handlePlaybackState(adapter.state);
      return true;
    } catch (error, stack) {
      if (!_disposed && generation == _playbackLoadGeneration) {
        _controlFailure(
          'player_track_selection_failed',
          'Could not change track. Please try again.',
          error,
          stack,
        );
      }
      return false;
    }
  }

  void _controlFailure(
    String event,
    String message,
    Object error,
    StackTrace stack,
  ) {
    _logger.error(
      event,
      error: safePlaybackLabel(error.toString()),
      stackTrace: StackTrace.fromString(redactSensitiveText(stack.toString())),
    );
    _controlError = message;
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    if (!capabilities.supportsVolume) return;
    await _runCommand(
      'playback_volume_failed',
      () => playbackAdapter.setVolume(volume),
    );
  }

  Future<void> close() async {
    if (_disposed) return;
    _playbackLoadGeneration++;
    await _stopPlayback();
  }

  void _handlePlaybackState(PlaybackState state) {
    if (!_disposed) _playbackState.value = state;
  }

  Future<void> _runCommand(
    String event,
    Future<void> Function() command,
  ) async {
    if (_disposed) return;
    final generation = _playbackLoadGeneration;
    try {
      await command();
      if (_disposed || generation != _playbackLoadGeneration) return;
      _handlePlaybackState(playbackAdapter.state);
    } catch (error, stackTrace) {
      if (_disposed || generation != _playbackLoadGeneration) return;
      _recordFailure(event, error, stackTrace);
    }
  }

  void _recordFailure(
    String event,
    Object error,
    StackTrace stackTrace, {
    ContentItem? item,
  }) {
    _logger.error(
      event,
      error: safePlaybackLabel(error.toString()),
      stackTrace: StackTrace.fromString(
        redactSensitiveText(stackTrace.toString()),
      ),
    );
    if (!_disposed) {
      _playbackState.value = _playbackState.value.copyWith(
        status: PlaybackStatus.error,
        item: item,
        errorKind: playbackErrorKind(error),
        clearMessage: true,
      );
    }
  }

  void _handleNavigationChanged() {
    final route = navigationController.currentRoute;
    if (_observedRoute is PlayerRoute && !identical(_observedRoute, route)) {
      unawaited(close());
    }
    _observedRoute = route;
  }

  void _handleLifecycleStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_isBackgrounded) return;
      _isBackgrounded = true;
      final playback = _playbackState.value;
      final item = playback.item;
      _resumeVodOnForeground =
          item?.type == ContentType.vod &&
          playback.status == PlaybackStatus.playing;
      _backgroundedItemId = item?.id;
      _backgroundedLoadGeneration = _playbackLoadGeneration;
      if (item == null) return;
      if (playback.status == PlaybackStatus.loading) {
        unawaited(_stopPlayback());
        return;
      }
      if (playback.status != PlaybackStatus.playing) return;

      if (item.type == ContentType.live) {
        unawaited(_stopPlayback());
      } else {
        unawaited(pause());
      }
      return;
    }

    if (state == AppLifecycleState.resumed && _isBackgrounded) {
      _isBackgrounded = false;
      final shouldResume = _resumeVodOnForeground;
      final itemId = _backgroundedItemId;
      final generation = _backgroundedLoadGeneration;
      _resumeVodOnForeground = false;
      _backgroundedItemId = null;
      _backgroundedLoadGeneration = null;

      final route = navigationController.currentRoute;
      if (shouldResume &&
          route is PlayerRoute &&
          route.item.id == itemId &&
          generation == _playbackLoadGeneration &&
          _playbackState.value.item?.id == itemId) {
        unawaited(play());
      }
    }
  }

  Future<void> _stopPlayback() async {
    final generation = _playbackLoadGeneration;
    try {
      await playbackAdapter.stop();
      if (_disposed || generation != _playbackLoadGeneration) return;
      _handlePlaybackState(playbackAdapter.state);
    } catch (error, stackTrace) {
      if (_disposed || generation != _playbackLoadGeneration) return;
      _recordFailure('playback_stop_failed', error, stackTrace);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_playbackLoadGeneration;
    _lifecycleListener.dispose();
    navigationController.removeListener(_handleNavigationChanged);
    _backHandlerOwner = null;
    _backRequestHandler = null;
    _disposeFuture = _disposePlayback();
    unawaited(
      _disposeFuture!.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _logger.error(
            'playback_dispose_failed',
            error: safePlaybackLabel(error.toString()),
            stackTrace: StackTrace.fromString(
              redactSensitiveText(stack.toString()),
            ),
          );
        },
      ),
    );
    _playbackState.dispose();
    super.dispose();
  }

  Future<void> _disposePlayback() async {
    final disposal = playbackAdapter.dispose();
    try {
      await _statesSubscription.cancel();
    } finally {
      await disposal;
    }
  }
}
