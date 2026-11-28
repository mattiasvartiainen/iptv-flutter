import 'package:flutter/widgets.dart';

import '../../models/content_item.dart';
import 'playback_error.dart';

export 'playback_error.dart';

enum PlaybackStatus { idle, loading, playing, paused, stopped, error }

/// Fixed backend support, not current stream metadata or command readiness.
///
/// A supported operation can still fail before initialization or for a stream
/// without the required tracks/duration. Owners gate controls with these flags
/// and stream state; the session rejects unsupported calls before native work.
@immutable
class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.supportsSeek,
    required this.supportsPause,
    required this.supportsVolume,
    required this.supportsDrm,
    required this.supportsLiveStreams,
    this.supportsAudioTracks = false,
    this.supportsSubtitleTracks = false,
    this.usesPlatformVideoPlane = false,
  });

  /// Whether absolute seeking is implemented (not whether this stream seeks).
  final bool supportsSeek;

  /// Whether pausing is implemented; [PlaybackAdapter.play] is independent.
  final bool supportsPause;

  /// Whether per-stream volume accepts a percentage from 0 to 100.
  final bool supportsVolume;

  /// Whether an implemented DRM configuration flow exists, not plugin support.
  final bool supportsDrm;

  /// Whether live items can be loaded; this does not guarantee codec support.
  final bool supportsLiveStreams;

  /// Whether embedded audio selection is implemented.
  final bool supportsAudioTracks;

  /// Whether embedded subtitle selection is implemented, including disabling.
  final bool supportsSubtitleTracks;

  /// Whether the host needs transparency for a native video plane.
  final bool usesPlatformVideoPlane;
}

@immutable
class PlaybackTrack {
  const PlaybackTrack({required this.id, required this.label});
  final String id;
  final String label;
}

@immutable
class PlaybackMediaInfo {
  const PlaybackMediaInfo({
    this.width,
    this.height,
    this.fps,
    this.videoCodec,
    this.audioCodec,
    this.channelLayout,
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.selectedAudioId,
    this.selectedSubtitleId,
  });
  final int? width;
  final int? height;
  final double? fps;
  final String? videoCodec;
  final String? audioCodec;
  final String? channelLayout;
  final List<PlaybackTrack> audioTracks;
  final List<PlaybackTrack> subtitleTracks;
  final String? selectedAudioId;
  final String? selectedSubtitleId;

  PlaybackMediaInfo withSelectedTrack(String id, {required bool subtitle}) =>
      PlaybackMediaInfo(
        width: width,
        height: height,
        fps: fps,
        videoCodec: videoCodec,
        audioCodec: audioCodec,
        channelLayout: channelLayout,
        audioTracks: audioTracks,
        subtitleTracks: subtitleTracks,
        selectedAudioId: subtitle ? selectedAudioId : id,
        selectedSubtitleId: subtitle ? id : selectedSubtitleId,
      );
}

/// Optional embedded track selection advertised by backend capabilities.
///
/// IDs come from the current media info, including backend-specific Off/Auto
/// entries. Completion means request acceptance; selected IDs reflect native
/// confirmation only and remain `null` when unavailable.
abstract interface class PlaybackTrackAdapter {
  Future<void> selectAudioTrack(String id);
  Future<void> selectSubtitleTrack(String id);
}

/// Optional unclassified native end notifications for the current resource.
///
/// Notifications may be caused by a seek and may be duplicated or delayed;
/// they are not evidence of natural completion. The item identifies the
/// resource associated with the notification, not its native cause. A backend
/// that cannot associate events with its current resource must not implement
/// this interface. A retained resource restarted after stop can still receive
/// a delayed notification from its earlier playback; callers cannot use this
/// stream to distinguish that notification from a new one.
abstract interface class PlaybackRawEndEvents {
  /// Whether this backend can associate end notifications with a resource.
  bool get supportsRawEndEvents;

  /// The broadcast stream of unclassified native end notifications.
  Stream<ContentItem> get rawEndEvents;
}

class PlaybackState {
  const PlaybackState({
    required this.status,
    this.item,
    this.message,
    this.errorKind,
    this.position = Duration.zero,
    this.duration,
    this.isBuffering = false,
    this.loadStartedAt,
    this.playbackStartedAt,
    this.mediaInfo = const PlaybackMediaInfo(),
    this.volume = 100,
  });

  const PlaybackState.idle() : this(status: PlaybackStatus.idle);

  final PlaybackStatus status;
  final ContentItem? item;
  final String? message;
  final PlaybackErrorKind? errorKind;
  final Duration position;
  final Duration? duration;
  final bool isBuffering;
  final DateTime? loadStartedAt;
  final DateTime? playbackStartedAt;
  final PlaybackMediaInfo mediaInfo;
  final double volume;

  Duration? get startupLatency =>
      loadStartedAt == null || playbackStartedAt == null
      ? null
      : playbackStartedAt!.difference(loadStartedAt!);

  PlaybackState copyWith({
    PlaybackStatus? status,
    ContentItem? item,
    String? message,
    bool clearMessage = false,
    PlaybackErrorKind? errorKind,
    bool clearErrorKind = false,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    bool? isBuffering,
    DateTime? loadStartedAt,
    DateTime? playbackStartedAt,
    bool clearPlaybackStartedAt = false,
    PlaybackMediaInfo? mediaInfo,
    double? volume,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      item: item ?? this.item,
      message: clearMessage ? null : (message ?? this.message),
      errorKind: clearErrorKind ? null : (errorKind ?? this.errorKind),
      position: position ?? this.position,
      duration: clearDuration ? null : (duration ?? this.duration),
      isBuffering: isBuffering ?? this.isBuffering,
      loadStartedAt: loadStartedAt ?? this.loadStartedAt,
      playbackStartedAt: clearPlaybackStartedAt
          ? null
          : (playbackStartedAt ?? this.playbackStartedAt),
      mediaInfo: mediaInfo ?? this.mediaInfo,
      volume: volume ?? this.volume,
    );
  }
}

/// A single native playback resource owned by a playback session.
///
/// Owners serialize ordinary commands. Only [stop] may interrupt [load].
/// Events retain the supplied [ContentItem] and describe the current resource,
/// never a detached controller. Native initialization failures throw
/// [PlaybackException]; other command/cleanup failures remain observable and
/// are classified by [playbackErrorKind] at the owner boundary.
/// Unsupported operations throw
/// [UnsupportedError], not unsupported-media errors. Track completion means
/// request acceptance, not native confirmation. Unsupported operations are
/// gated by [capabilities].
abstract interface class PlaybackAdapter {
  PlaybackCapabilities get capabilities;
  PlaybackState get state;
  Stream<PlaybackState> get states;

  /// Returns the current resource's stable widget, or `null` without a surface.
  ///
  /// Repeated calls return the same widget while the native resource survives.
  /// Position/metadata changes do not recreate it; aspect ratio reacts within
  /// the widget. Detached resources, cancelled initialization and disposal
  /// invalidate it. Replacement or stop may reuse a retained native resource's
  /// surface (as on MediaKit). Owners query this on state changes rather than
  /// caching the first non-null widget.
  /// Implementations publish state when surface availability/identity changes.
  Widget? buildVideoView();

  /// Replaces the resource and starts playback once initialization completes.
  ///
  /// [stop] or [dispose] cancels pending initialization without an error.
  /// Cancellation prevents subsequent autoplay and stale state publication.
  Future<void> load(ContentItem item);

  /// Resumes playback, recreating the retained item's resource when necessary.
  ///
  /// A restart has the same cancellation guarantees as [load].
  Future<void> play();
  Future<void> pause();

  /// Stops output and cancels a pending load without retaining its callbacks.
  ///
  /// Repeated calls are safe. The loaded item may remain available for a later
  /// explicit [play].
  /// Live playback never restarts automatically on foreground return.
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Releases native resources and subscriptions exactly once.
  ///
  /// Disposal starts synchronously, suppressing subsequent events. The returned
  /// future completes when cleanup finishes and reports cleanup failures.
  /// Repeated calls return the same completion. No commands follow disposal.
  Future<void> dispose();
}
