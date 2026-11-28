import 'package:flutter/foundation.dart';

import '../../platform/build_flags.dart';
import 'playback_contract.dart';

/// Events recorded by the opt-in playback end diagnostic.
enum PlaybackEndTraceEvent {
  loadRequested,
  playRequested,
  pauseRequested,
  seekRequested,
  seekStarted,
  seekFinished,
  stopRequested,
  disposeRequested,
  stateChanged,
  webosRawEnd,
  mediaKitCompletion,
  sessionRawEnd,
}

/// Records a bounded, credential-free trace for playback end validation.
///
/// The application instance is enabled only in non-release builds when the
/// `IPTV_PLAYBACK_END_TRACE` compile-time flag is `true`. Records contain only
/// enum names, numeric timings and positions, and boolean acceptance; they do
/// not contain item identity, URLs, track labels, or native error text.
class PlaybackEndDiagnostics {
  PlaybackEndDiagnostics._(this._sink) : _clock = Stopwatch()..start();

  /// Creates an enabled recorder for tests.
  @visibleForTesting
  PlaybackEndDiagnostics.forTesting(void Function(String) sink) : this._(sink);

  /// The shared opt-in application recorder, or `null` when disabled.
  static final PlaybackEndDiagnostics? instance =
      !kReleaseMode && playbackEndTraceEnabled
      ? PlaybackEndDiagnostics._(debugPrint)
      : null;

  final void Function(String) _sink;
  final Stopwatch _clock;
  int _sequence = 0;
  int _nextOwner = 0;

  /// Allocates an anonymous identifier to correlate records from one owner.
  int newOwner() => ++_nextOwner;

  /// Emits a trace record without content-specific strings.
  void record(
    PlaybackEndTraceEvent event, {
    required int owner,
    int? generation,
    Duration? position,
    Duration? duration,
    Duration? target,
    bool? accepted,
    bool? completed,
    PlaybackStatus? status,
  }) {
    final fields = <String>[
      'seq=${++_sequence}',
      'ms=${_clock.elapsedMilliseconds}',
      'owner=$owner',
      'event=${event.name}',
      if (generation != null) 'generation=$generation',
      if (position != null) 'position_ms=${position.inMilliseconds}',
      if (duration != null) 'duration_ms=${duration.inMilliseconds}',
      if (target != null) 'target_ms=${target.inMilliseconds}',
      if (accepted != null) 'accepted=$accepted',
      if (completed != null) 'completed=$completed',
      if (status != null) 'status=${status.name}',
    ];
    _sink('[playback-end-trace] ${fields.join(' ')}');
  }
}
