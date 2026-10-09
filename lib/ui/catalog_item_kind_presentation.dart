import 'package:flutter/material.dart';

import '../services/catalog/catalog_query.dart';

extension CatalogItemKindPresentation on CatalogItemKind {
  IconData get icon => switch (this) {
    CatalogItemKind.live => Icons.live_tv,
    CatalogItemKind.movie => Icons.movie,
    CatalogItemKind.episode => Icons.tv,
    CatalogItemKind.unknown => Icons.play_circle_outline,
  };

  String get label => switch (this) {
    CatalogItemKind.live => 'Live TV',
    CatalogItemKind.movie => 'Movie',
    CatalogItemKind.episode => 'Series',
    CatalogItemKind.unknown => 'Media',
  };
}
