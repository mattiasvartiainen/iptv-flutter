import 'package:iptv_flutter/services/catalog/catalog_import_coordinator.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/catalog/catalog_sync_service.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';

/// Sync service over [adapter] whose indexer only drains on explicit calls
/// unless [searchIndexer] is supplied.
CatalogSyncService createCatalogSyncService(
  DatabaseAdapter adapter, {
  CatalogSearchIndexer? searchIndexer,
  CatalogImportCoordinator? coordinator,
}) => CatalogSyncService(
  databaseAdapter: adapter,
  importer: CatalogImporter(databaseAdapter: adapter, coordinator: coordinator),
  searchIndexer:
      searchIndexer ??
      SqliteCatalogSearchIndexer(
        databaseAdapter: adapter,
        autoStartWorker: false,
      ),
);
