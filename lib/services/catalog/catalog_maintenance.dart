abstract interface class CatalogMaintenance {
  Future<void> recoverAbandonedImports();

  Future<void> resumeSearchIndexing();
}
