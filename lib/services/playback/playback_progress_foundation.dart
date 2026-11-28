import '../../models/content_item.dart';
import '../../models/library_identity.dart';

/// A scoped snapshot ready for atomic progress and history storage.
class PlaybackCheckpoint {
  const PlaybackCheckpoint({
    required this.identity,
    required this.position,
    required this.duration,
    required this.completed,
  });

  final LibraryIdentity identity;
  final Duration position;
  final Duration? duration;
  final bool completed;
}

/// A writer for one playback session.
abstract interface class PlaybackCheckpointWriter {
  /// Atomically stores one snapshot, or throws when storage fails.
  Future<void> write(PlaybackCheckpoint checkpoint);
}

/// Creates isolated checkpoint writers.
abstract interface class PlaybackCheckpointStore {
  /// Creates a writer for a new playback session.
  PlaybackCheckpointWriter newSession();
}

/// Serializes checkpoint writes across successive sessions.
///
/// This foundation is not connected to the player. A future integration must
/// share one coordinator across sessions and supply ordered, monotonic samples
/// and explicit seek boundaries; raw end events are not completion evidence.
class PlaybackProgressCoordinator {
  PlaybackProgressCoordinator(this._store);

  final PlaybackCheckpointStore _store;
  Future<void> _tail = Future<void>.value();
  PlaybackProgressSession? _current;

  /// Replaces the active session; live and unidentified items are excluded.
  PlaybackProgressSession? begin({
    required ContentType type,
    required LibraryIdentity? identity,
  }) {
    _current?._active = false;
    if (type != ContentType.vod || identity == null) {
      _current = null;
      return null;
    }
    return _current = PlaybackProgressSession._(
      this,
      identity,
      _store.newSession(),
    );
  }

  Future<void> _write(
    PlaybackCheckpointWriter writer,
    PlaybackCheckpoint value,
  ) {
    final result = _tail.then((_) => writer.write(value));
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }
}

/// Tracks conservative playback evidence for one active session.
class PlaybackProgressSession {
  PlaybackProgressSession._(this._coordinator, this.identity, this._writer);

  final PlaybackProgressCoordinator _coordinator;
  final PlaybackCheckpointWriter _writer;
  final LibraryIdentity identity;
  bool _active = true;
  bool _seeking = false;
  bool _wasPlaying = false;
  Duration? _latestTime;
  Duration? _lastTime;
  Duration? _lastPosition;
  Duration _position = Duration.zero;
  Duration? _duration;
  Duration _played = Duration.zero;
  Duration _lastCheckpointPlayed = Duration.zero;
  bool _completed = false;

  /// The conservatively observed amount of actual playback.
  Duration get played => _played;

  /// Whether the known-duration threshold was reached during playback.
  bool get completed => _completed;

  /// Invalidates position evidence before issuing a seek.
  void seekStarted() {
    if (!_active) return;
    _seeking = true;
    _lastPosition = null;
    _lastTime = null;
    _wasPlaying = false;
  }

  /// Ends a seek without treating its resulting position as playback.
  void seekFinished() {
    if (!_active) return;
    _seeking = false;
    _lastPosition = null;
    _lastTime = null;
    _wasPlaying = false;
  }

  /// Observes an ordered position sample and stores a due checkpoint.
  ///
  /// [elapsed] is a monotonic session clock. Playback credit requires position
  /// to advance while previously playing and not buffering, and cannot exceed
  /// elapsed time. Large jumps are treated as discontinuities, not playback.
  /// The caller must handle the returned storage failure.
  Future<void> observe({
    required Duration elapsed,
    required Duration position,
    required Duration? duration,
    required bool playing,
    required bool buffering,
  }) {
    if (!_active) return Future<void>.value();
    if (elapsed.isNegative ||
        position.isNegative ||
        (duration != null && duration.isNegative) ||
        (_latestTime != null && elapsed < _latestTime!)) {
      throw ArgumentError('Invalid playback sample.');
    }
    _latestTime = elapsed;
    final lastTime = _lastTime;
    final lastPosition = _lastPosition;
    final advancing =
        !_seeking &&
        _wasPlaying &&
        lastTime != null &&
        lastPosition != null &&
        elapsed > lastTime &&
        position > lastPosition;
    if (advancing) {
      final time = elapsed - lastTime;
      final movement = position - lastPosition;
      if (movement <= time + const Duration(seconds: 1)) {
        _played += movement < time ? movement : time;
        if (duration != null &&
            duration > Duration.zero &&
            position.inMicroseconds * 10 >= duration.inMicroseconds * 9) {
          _completed = true;
        }
      }
    }
    _position = position;
    _duration = duration == Duration.zero ? null : duration;
    _lastTime = elapsed;
    _lastPosition = position;
    _wasPlaying = playing && !buffering && !_seeking;
    if (_played >= const Duration(seconds: 30) &&
        (_lastCheckpointPlayed == Duration.zero ||
            _played - _lastCheckpointPlayed >= const Duration(seconds: 15))) {
      return checkpoint();
    }
    return Future<void>.value();
  }

  /// Stores the current snapshot after the minimum playback threshold.
  ///
  /// Call this before clearing state on pause, background, or exit. Await or
  /// otherwise report failures; the coordinator continues after failed writes.
  Future<void> checkpoint() {
    if (!_active || _played < const Duration(seconds: 30)) {
      return Future<void>.value();
    }
    final previousCheckpoint = _lastCheckpointPlayed;
    final checkpointPlayed = _played;
    _lastCheckpointPlayed = checkpointPlayed;
    return _coordinator
        ._write(
          _writer,
          PlaybackCheckpoint(
            identity: identity,
            position: _position,
            duration: _duration,
            completed: _completed,
          ),
        )
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (_lastCheckpointPlayed == checkpointPlayed) {
              _lastCheckpointPlayed = previousCheckpoint;
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
  }

  /// Closes the session after scheduling its final checkpoint.
  Future<void> finish() {
    final result = checkpoint();
    _active = false;
    return result;
  }
}
