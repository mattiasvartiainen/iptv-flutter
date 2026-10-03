import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_coordinator.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_progress.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_protocol.dart';

void main() {
  test('parses in a worker and reports lifecycle progress', () async {
    final coordinator = CatalogImportCoordinator();
    final progress = <CatalogImportProgress>[];

    final result = await coordinator.run(
      playlistId: 'playlist-1',
      onProgress: progress.add,
      operation: (reporter) => coordinator.parse(
        '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''',
        sourceUrl: 'https://provider.test/playlist.m3u',
        reporter: reporter,
      ),
    );

    expect(result, hasLength(1));
    expect(result.single.title, 'Channel A');
    expect(progress.map((value) => value.phase), [
      CatalogImportPhase.starting,
      CatalogImportPhase.parsing,
      CatalogImportPhase.parsing,
      CatalogImportPhase.completed,
    ]);
    expect(progress.last.isTerminal, isTrue);
    expect(progress.last.jobId, isNotNull);
    expect(progress.last.playlistId, 'playlist-1');
    expect(progress[2].parsedItems, 1);
  });

  test('shares one in-flight job with concurrent callers', () async {
    final coordinator = CatalogImportCoordinator();
    final started = Completer<void>();
    final release = Completer<void>();
    var operationCount = 0;
    final firstProgress = <CatalogImportProgress>[];
    final secondProgress = <CatalogImportProgress>[];

    Future<int> operation(CatalogImportReporter reporter) async {
      operationCount++;
      started.complete();
      await release.future;
      return 42;
    }

    final first = coordinator.run(
      playlistId: 'playlist-1',
      onProgress: firstProgress.add,
      operation: operation,
    );
    await started.future;
    final second = coordinator.run(
      playlistId: 'playlist-1',
      onProgress: secondProgress.add,
      operation: operation,
    );
    release.complete();

    expect(await first, 42);
    expect(await second, 42);
    expect(operationCount, 1);
    expect(firstProgress.last.phase, CatalogImportPhase.completed);
    expect(secondProgress.last.phase, CatalogImportPhase.completed);
  });

  test(
    'runs the streamed worker under coordinator lifecycle and progress',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(() async {
        final request = await server.first;
        request.response.write(
          '#EXTM3U\n#EXTINF:-1 group-title="News",Channel\nhttps://stream.test/channel.m3u8\n',
        );
        await request.response.close();
      }());

      final coordinator = CatalogImportCoordinator();
      final progress = <CatalogImportProgress>[];
      final rows = <CatalogImportRow>[];
      final result = await coordinator.importPlaylist(
        playlistId: 'worker-playlist',
        playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
        selectRows: (batch) async =>
            List.generate(batch.itemKeys.length, (index) => index),
        onRows: (_, items) async => rows.addAll(items),
        onProgress: progress.add,
      );

      expect(result.itemsParsed, 1);
      expect(rows.single.title, 'Channel');
      expect(progress.first.phase, CatalogImportPhase.starting);
      expect(
        progress.any((event) => event.phase == CatalogImportPhase.downloading),
        isTrue,
      );
      expect(
        progress.any((event) => event.phase == CatalogImportPhase.parsing),
        isTrue,
      );
      expect(progress.last.phase, CatalogImportPhase.completed);
    },
  );

  test('runs a cancellation callback registered after cancellation', () async {
    final coordinator = CatalogImportCoordinator();
    final operationStarted = Completer<void>();
    final registerCallback = Completer<void>();
    final callbackRan = Completer<void>();
    final operation = coordinator.run<void>(
      playlistId: 'late-cancel-callback',
      operation: (reporter) async {
        operationStarted.complete();
        await registerCallback.future;
        reporter.onCancel(() => callbackRan.complete());
        await callbackRan.future;
      },
    );

    await operationStarted.future;
    await coordinator.cancel('late-cancel-callback');
    registerCallback.complete();
    await callbackRan.future;
    await operation;
  });
}
