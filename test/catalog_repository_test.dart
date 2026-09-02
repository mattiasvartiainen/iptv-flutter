import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';

void main() {
  test('loads catalog through an injected playlist source', () async {
    const source = FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="News",Injected Channel
https://stream.test/injected.m3u8
''');
    const repository = M3uCatalogRepository(source: source);

    final items = await repository.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
    );

    expect(items.itemCount, 1);
  });
}
