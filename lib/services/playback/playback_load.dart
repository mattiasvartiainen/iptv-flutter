import 'dart:async';

/// A cancellation gate for native initialization without native autoplay.
class PlaybackLoad {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  Future<void> waitFor(Future<void> initialization) async {
    try {
      await Future.any([initialization, _cancelled.future]);
    } catch (_) {
      if (!isCancelled) rethrow;
    }
  }
}
