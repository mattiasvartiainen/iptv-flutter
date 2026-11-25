import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/playback/playback_load.dart';

void main() {
  test(
    'initialization failures remain observable before cancellation',
    () async {
      final load = PlaybackLoad();
      await expectLater(
        load.waitFor(Future.error(StateError('Initialization failed'))),
        throwsStateError,
      );
    },
  );

  test(
    'cancellation is idempotent and does not wait for native initialization',
    () async {
      final load = PlaybackLoad();
      final initialization = Completer<void>();
      final waiting = load.waitFor(initialization.future);
      load.cancel();
      load.cancel();
      await waiting;
      expect(load.isCancelled, isTrue);
      expect(initialization.isCompleted, isFalse);
      initialization.completeError(StateError('Detached native failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );
}
