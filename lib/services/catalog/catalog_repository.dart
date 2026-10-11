import 'catalog_import_progress.dart';

export 'catalog_import_progress.dart';

enum CatalogLoadPolicy {
  /// Return cached rows only and never make a network request.
  cacheOnly,

  /// Return cached rows if present and refresh only when the cache is stale.
  cacheFirst,

  /// Always attempt a network refresh before returning data.
  networkOnly,
}

abstract interface class CatalogRepository {
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  });
}

class CatalogLoadResult {
  const CatalogLoadResult({required this.playlistId, required this.itemCount});

  final String? playlistId;
  final int itemCount;
}
