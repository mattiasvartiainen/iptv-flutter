import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/ui/catalog_item_kind_presentation.dart';

void main() {
  test('provides an icon and label for every catalog item kind', () {
    expect(CatalogItemKind.live.icon, Icons.live_tv);
    expect(CatalogItemKind.live.label, 'Live TV');
    expect(CatalogItemKind.movie.icon, Icons.movie);
    expect(CatalogItemKind.movie.label, 'Movie');
    expect(CatalogItemKind.episode.icon, Icons.tv);
    expect(CatalogItemKind.episode.label, 'Series');
    expect(CatalogItemKind.unknown.icon, Icons.play_circle_outline);
    expect(CatalogItemKind.unknown.label, 'Media');
  });
}
