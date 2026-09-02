import 'database_adapter.dart';
import 'secure_storage_service.dart';
import '../catalog/sqlite_catalog_repository.dart';
import '../settings/settings_repository.dart';

class AppStorageBootstrap {
  AppStorageBootstrap._();

  static final AppStorageBootstrap instance = AppStorageBootstrap._();

  final SqfliteDatabaseAdapter _adapter = SqfliteDatabaseAdapter();
  final PlaylistSecretStore _secretStore = FlutterSecurePlaylistSecretStore();
  SqliteCatalogRepository? _catalogRepository;
  SqliteSettingsRepository? _settingsRepository;

  SqfliteDatabaseAdapter get adapter => _adapter;

  SqliteCatalogRepository get catalogRepository =>
      _catalogRepository ??= SqliteCatalogRepository(
        databaseAdapter: _adapter,
        secretStore: _secretStore,
      );

  SqliteSettingsRepository get settingsRepository =>
      _settingsRepository ??= SqliteSettingsRepository(
        databaseAdapter: _adapter,
        secretStore: _secretStore,
      );

  PlaylistSecretStore get secretStore => _secretStore;

  Future<void> initialize() async {
    await _adapter.initialize();
  }

  Future<void> dispose() async {
    await _adapter.close();
  }
}
