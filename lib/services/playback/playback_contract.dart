import 'package:flutter/widgets.dart';

import '../../models/content_item.dart';

enum PlaybackStatus { idle, loading, playing, paused, stopped, error }

class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.supportsSeek,
    required this.supportsPause,
    required this.supportsVolume,
    required this.supportsDrm,
    required this.supportsLiveStreams,
  });

  final bool supportsSeek;
  final bool supportsPause;
  final bool supportsVolume;
  final bool supportsDrm;
  final bool supportsLiveStreams;
}

class PlaybackState {
  const PlaybackState({
    required this.status,
    this.item,
    this.message,
    this.position = Duration.zero,
    this.duration,
    this.isBuffering = false,
    this.loadStartedAt,
    this.playbackStartedAt,
  });

  const PlaybackState.idle() : this(status: PlaybackStatus.idle);

  final PlaybackStatus status;
  final ContentItem? item;
  final String? message;
  final Duration position;
  final Duration? duration;
  final bool isBuffering;
  final DateTime? loadStartedAt;
  final DateTime? playbackStartedAt;

  Duration? get startupLatency =>
      loadStartedAt == null || playbackStartedAt == null
      ? null
      : playbackStartedAt!.difference(loadStartedAt!);

  PlaybackState copyWith({
    PlaybackStatus? status,
    ContentItem? item,
    String? message,
    bool clearMessage = false,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    bool? isBuffering,
    DateTime? loadStartedAt,
    DateTime? playbackStartedAt,
    bool clearPlaybackStartedAt = false,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      item: item ?? this.item,
      message: clearMessage ? null : (message ?? this.message),
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      isBuffering: isBuffering ?? this.isBuffering,
      loadStartedAt: loadStartedAt ?? this.loadStartedAt,
      playbackStartedAt: clearPlaybackStartedAt
          ? null
          : (playbackStartedAt ?? this.playbackStartedAt),
    );
  }
}

abstract interface class PlaybackAdapter {
  PlaybackCapabilities get capabilities;
  PlaybackState get state;
  Stream<PlaybackState> get states;
  Widget? buildVideoView();
  Future<void> load(ContentItem item);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  void dispose();
}
