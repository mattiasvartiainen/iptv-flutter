import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';

void main() {
  test(
    'DebugAppLogger redacts URLs in messages, context, errors, and stacks',
    () {
      final output = <String>[];
      final originalDebugPrint = foundation.debugPrint;
      foundation.debugPrint = (message, {wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() => foundation.debugPrint = originalDebugPrint);
      const credentialUrl =
          'https://provider.test/live/private-user/private-pass/channel.m3u8';
      const expectedRedactedUrl =
          'https://provider.test/live/%5Bredacted%5D/%5Bredacted%5D/channel.m3u8';
      const logger = DebugAppLogger();

      logger.info(
        'request failed: $credentialUrl',
        context: {'url': credentialUrl},
      );
      logger.error(
        'playback_failed',
        error: StateError(credentialUrl),
        stackTrace: StackTrace.fromString('at $credentialUrl'),
      );

      final logged = output.join('\n');
      expect(logged, contains(expectedRedactedUrl));
      expect(logged, isNot(contains('private-user')));
      expect(logged, isNot(contains('private-pass')));
    },
  );
}
