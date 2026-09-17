import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_coordinator.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';

void main() {
  test(
    'stream parsing emits bounded batches and applies backpressure',
    () async {
      final playlist = StringBuffer('#EXTM3U\n');
      for (var index = 0; index < 1205; index++) {
        playlist
          ..writeln('#EXTINF:-1 group-title="News",Channel $index')
          ..writeln('https://stream.test/$index.m3u8');
      }

      final batches = <CatalogImportBatch>[];
      final coordinator = CatalogImportCoordinator();
      final parsedCount = await coordinator.run(
        playlistId: 'streaming-playlist',
        operation: (reporter) => coordinator.parseStream(
          Stream<PlaylistSourceChunk>.fromIterable([
            PlaylistSourceChunk(
              text: playlist.toString().substring(0, 4096),
              received: 4096,
              total: playlist.length,
            ),
            PlaylistSourceChunk(
              text: playlist.toString().substring(4096),
              received: playlist.length,
              total: playlist.length,
            ),
          ]),
          sourceUrl: 'https://provider.test/playlist.m3u',
          reporter: reporter,
          onBatch: (batch) async {
            await Future<void>.delayed(Duration.zero);
            batches.add(batch);
          },
        ),
      );

      expect(parsedCount, 1205);
      expect(batches.length, greaterThan(1));
      expect(batches.every((batch) => batch.items.length <= 1000), isTrue);
      expect(batches.last.parsedItems, 1205);
      expect(batches.expand((batch) => batch.items).length, 1205);
    },
  );
}
