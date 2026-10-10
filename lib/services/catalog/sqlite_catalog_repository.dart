import '../../models/content_item.dart';
import '../storage/storage_contracts.dart';
import 'catalog_import_coordinator.dart';
import 'catalog_importer.dart';
import 'catalog_query.dart';
import 'catalog_query_service.dart';
import 'catalog_repository.dart';
import 'catalog_search_indexer.dart';
import 'catalog_sync_service.dart';
import 'sqlite_catalog_query_service.dart';
import 'user_library_repository.dart';

/// Temporary façade over the split catalog services for existing callers.
///
/// New code should depend on [CatalogSyncService], [CatalogQueryService],
/// [CatalogSearchIndexer] or [UserLibraryRepository] directly.
class SqliteCatalogRepository
    implements CatalogRepository, CatalogQueryService {
  factory SqliteCatalogRepository({
    required DatabaseAdapter databaseAdapter,
    bool autoStartSearchIndexWorker = true,
    CatalogImportCoordinator? importCoordinator,
  }) {
    final searchIndexer = SqliteCatalogSearchIndexer(
      databaseAdapter: databaseAdapter,
      autoStartWorker: autoStartSearchIndexWorker,
    );
    return SqliteCatalogRepository.fromServices(
      sync: CatalogSyncService(
        databaseAdapter: databaseAdapter,
        importer: CatalogImporter(
          databaseAdapter: databaseAdapter,
          coordinator: importCoordinator,
        ),
        searchIndexer: searchIndexer,
      ),
      queries: SqliteCatalogQueryService(
        databaseAdapter: databaseAdapter,
        searchIndexer: searchIndexer,
      ),
      searchIndexer: searchIndexer,
      userLibrary: SqliteUserLibraryRepository(
        databaseAdapter: databaseAdapter,
      ),
    );
  }

  const SqliteCatalogRepository.fromServices({
    required this.sync,
    required this.queries,
    required this.searchIndexer,
    required this.userLibrary,
  });

  final CatalogSyncService sync;
  final CatalogQueryService queries;
  final CatalogSearchIndexer searchIndexer;
  final UserLibraryRepository userLibrary;

  // --- CatalogSyncService ----------------------------------------------------

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) => sync.load(
    playlistUrl: playlistUrl,
    playlistId: playlistId,
    playlistName: playlistName,
    policy: policy,
    onProgress: onProgress,
  );

  Future<void> cancelImport(String playlistId) => sync.cancelImport(playlistId);

  Future<void> recoverAbandonedImports() => sync.recoverAbandonedImports();

  // --- CatalogSearchIndexer --------------------------------------------------

  Future<void> resumeSearchIndexing() => searchIndexer.resumePendingIndexing();

  Future<int> processCatalogSearchIndexQueue({
    String? playlistId,
    int batchSize = SqliteCatalogSearchIndexer.defaultBatchSize,
  }) =>
      searchIndexer.processQueue(playlistId: playlistId, batchSize: batchSize);

  // --- CatalogQueryService ---------------------------------------------------

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) =>
      queries.queryItems(query);

  @override
  Future<CatalogSearchIndexStatus> searchIndexStatus(String playlistId) =>
      queries.searchIndexStatus(playlistId);

  @override
  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  }) => queries.queryGroups(playlistId, kind: kind, profileId: profileId);

  @override
  Future<CatalogPage<CatalogItemSummary>> itemsInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    CatalogSort sort = CatalogSort.title,
  }) => queries.itemsInGroup(
    playlistId,
    groupId,
    offset: offset,
    limit: limit,
    sort: sort,
  );

  @override
  Future<CatalogPage<SeriesSummary>> seriesInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) => queries.seriesInGroup(
    playlistId,
    groupId,
    offset: offset,
    limit: limit,
    searchTerm: searchTerm,
  );

  @override
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  }) => queries.homePreview(playlistId, kind: kind, limit: limit);

  @override
  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) => queries.querySeries(
    playlistId,
    offset: offset,
    limit: limit,
    searchTerm: searchTerm,
  );

  @override
  Future<List<SeasonSummary>> seasons(String seriesId) =>
      queries.seasons(seriesId);

  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(
    String seasonId, {
    int offset = 0,
    int limit = kCatalogPageSize,
  }) => queries.episodes(seasonId, offset: offset, limit: limit);

  @override
  Future<List<String>> groups(
    String playlistId, {
    List<CatalogItemKind> kinds = const [],
  }) => queries.groups(playlistId, kinds: kinds);

  @override
  Future<ContentItem?> itemById(String itemId) => queries.itemById(itemId);

  // --- UserLibraryRepository -------------------------------------------------

  Future<void> setV9Favorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  }) => userLibrary.setFavorite(
    playlistId: playlistId,
    itemKey: itemKey,
    favorite: favorite,
    profileId: profileId,
  );

  Future<List<CatalogItemSummary>> v9FavoriteItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kCatalogPageSize,
  }) => userLibrary.favoriteItems(
    playlistId: playlistId,
    profileId: profileId,
    limit: limit,
  );

  Future<void> saveV9PlaybackProgress({
    required String playlistId,
    required int itemKey,
    required int positionMs,
    int? durationMs,
    String profileId = 'default',
  }) => userLibrary.savePlaybackProgress(
    playlistId: playlistId,
    itemKey: itemKey,
    positionMs: positionMs,
    durationMs: durationMs,
    profileId: profileId,
  );

  Future<CatalogPlaybackProgress?> v9PlaybackProgress({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  }) => userLibrary.playbackProgress(
    playlistId: playlistId,
    itemKey: itemKey,
    profileId: profileId,
  );

  Future<void> recordV9WatchHistory({
    required String playlistId,
    required int itemKey,
    required bool completed,
    int? positionMs,
    int? durationMs,
    String profileId = 'default',
  }) => userLibrary.recordWatchHistory(
    playlistId: playlistId,
    itemKey: itemKey,
    completed: completed,
    positionMs: positionMs,
    durationMs: durationMs,
    profileId: profileId,
  );

  Future<List<CatalogItemSummary>> v9RecentlyWatchedItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kHomePreviewCount,
  }) => userLibrary.recentlyWatchedItems(
    playlistId: playlistId,
    profileId: profileId,
    limit: limit,
  );
}
