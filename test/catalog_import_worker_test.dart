import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_protocol.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_worker.dart';
import 'package:iptv_flutter/services/catalog/catalog_hash.dart';

void main() {
  group('CatalogImportWorker', () {
    test(
      'decodes UTF-8 split across network chunks and returns ordered rows',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final body = utf8.encode('''#EXTM3U
#EXTINF:-1 group-title="News",Café
https://stream.test/cafe.m3u8
#EXTINF:-1 group-title="News",Second
https://stream.test/second.m3u8
#EXTINF:-1 type="series" group-title="Drama",Example S01E02
https://stream.test/episode
#EXTINF:-1 group-title="News",Second Alternate
https://stream.test/second.m3u8
#EXTINF:-1 group-title="News",Broken URL
http://[
''');
        final accentBytes = utf8.encode('é');
        final splitAt = _indexOfBytes(body, accentBytes) + 1;
        unawaited(() async {
          final request = await server.first;
          request.response.contentLength = body.length;
          request.response.add(body.sublist(0, splitAt));
          request.response.add(body.sublist(splitAt));
          await request.response.close();
        }());

        final rows = <CatalogImportRow>[];
        final progress = <(int, int?, int)>[];
        final handle = await CatalogImportWorker.start(
          playlistId: 'playlist-utf8',
          playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
          selectRows: (batch) async =>
              List.generate(batch.itemKeys.length, (index) => index),
          onRows: (_, batchRows) async => rows.addAll(batchRows),
          onProgress: (received, total, parsed) =>
              progress.add((received, total, parsed)),
        );

        final result = await handle.done;

        expect(result.itemsParsed, 5);
        expect(result.itemsRejected, 1);
        expect(result.bytesReceived, body.length);
        expect(result.bodyHash, hash64(utf8.decode(body)));
        expect(result.headers.statusCode, HttpStatus.ok);
        expect(result.headers.contentLength, body.length);
        expect(rows.map((row) => row.ordinal), [0, 1, 2, 3]);
        expect(rows.first.title, 'Café');
        expect(rows[2].itemKind.name, 'episode');
        expect(rows[2].groupKind.name, 'series');
        expect(rows[2].seriesKey, isNotNull);
        expect(result.duplicateUrls, 1);
        expect(rows[1].itemKey, isNot(rows[3].itemKey));
        expect(rows.map((row) => row.itemKey).toSet(), hasLength(4));
        expect(progress, isNotEmpty);
      },
    );

    test(
      'waits for row acknowledgement before requesting the next batch',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final body = StringBuffer('#EXTM3U\n');
        for (var index = 0; index < 2205; index++) {
          body
            ..writeln('#EXTINF:-1 group-title="News",Channel $index')
            ..writeln('https://stream.test/$index.m3u8');
        }
        final encoded = utf8.encode(body.toString());
        unawaited(() async {
          final request = await server.first;
          request.response.contentLength = encoded.length;
          request.response.add(encoded);
          await request.response.close();
        }());

        final firstRowsDelivered = Completer<void>();
        final releaseFirstRows = Completer<void>();
        final batchSizes = <int>[];
        var selections = 0;
        final handle = await CatalogImportWorker.start(
          playlistId: 'playlist-large',
          playlistUrl: 'http://127.0.0.1:${server.port}/large.m3u',
          selectRows: (batch) async {
            selections++;
            return List.generate(batch.itemKeys.length, (index) => index);
          },
          onRows: (batchNumber, rows) async {
            batchSizes.add(rows.length);
            if (batchNumber == 0) {
              firstRowsDelivered.complete();
              await releaseFirstRows.future;
            }
          },
        );

        await firstRowsDelivered.future;
        expect(selections, 1);
        releaseFirstRows.complete();
        final result = await handle.done;

        expect(result.itemsParsed, 2205);
        expect(selections, 3);
        expect(batchSizes, [1000, 1000, 205]);
      },
    );

    test('cancel stops a worker while its key selection is pending', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final pendingSelection = Completer<List<int>>();
      final keyBatchReceived = Completer<void>();
      unawaited(() async {
        final request = await server.first;
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          '#EXTM3U\n#EXTINF:-1 group-title="News",Channel\nhttps://stream.test/channel.m3u8\n',
        );
        await request.response.close();
      }());

      final handle = await CatalogImportWorker.start(
        playlistId: 'playlist-cancel',
        playlistUrl: 'http://127.0.0.1:${server.port}/cancel.m3u',
        selectRows: (batch) {
          keyBatchReceived.complete();
          return pendingSelection.future;
        },
        onRows: (_, _) async {},
      );

      await keyBatchReceived.future;
      await handle.cancel();
      await expectLater(
        handle.done,
        throwsA(isA<CatalogImportCancelledException>()),
      );
      pendingSelection.complete(const []);
    });

    test('propagates non-success HTTP status as a worker error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(() async {
        final request = await server.first;
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }());

      final handle = await CatalogImportWorker.start(
        playlistId: 'playlist-failure',
        playlistUrl: 'http://127.0.0.1:${server.port}/failure.m3u',
        selectRows: (_) async => const [],
        onRows: (_, _) async {},
      );

      await expectLater(handle.done, throwsA(isA<FormatException>()));
    });
  });
}

int _indexOfBytes(List<int> source, List<int> target) {
  for (var start = 0; start <= source.length - target.length; start++) {
    var matches = true;
    for (var offset = 0; offset < target.length; offset++) {
      if (source[start + offset] != target[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}
