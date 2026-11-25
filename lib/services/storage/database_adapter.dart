import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../telemetry/app_telemetry.dart';
import 'catalog_sort_v13_migration.dart';
import 'movie_metadata_v14_migration.dart';
import 'series_membership_v17_migration.dart';
import 'series_metadata_v15_migration.dart';
import 'series_metadata_v16_migration.dart';
import 'source_verification_v12_migration.dart';
import 'storage_contracts.dart';
import 'storage_migrations.dart';

class SqfliteDatabaseAdapter implements DatabaseAdapter {
  SqfliteDatabaseAdapter({
    required DatabaseFactory databaseFactory,
    this.databaseDirectoryProvider,
    this.fileName = 'iptv_app.sqlite',
    this.telemetry = const NoopAppTelemetry(),
    List<StorageMigration>? migrations,
  }) : _databaseFactory = databaseFactory,
       _migrations =
           migrations ??
           const [
             InitialSchemaV1Migration(),
             PlaylistImportMetricsV2Migration(),
             PlaylistScopedIdentityV3Migration(),
             MediaItemXuiIdV4Migration(),
             PaginatedCatalogV5Migration(),
             ImportStagingSqlReconcileV6Migration(),
             ImportPerformanceV7Migration(),
             ImportSessionsV8Migration(),
             CatalogImportV9Migration(),
             CatalogSearchV10Migration(),
             DropLegacyCatalogV11Migration(),
             SourceVerificationV12Migration(),
             CatalogSortV13Migration(),
             MovieMetadataV14Migration(),
             SeriesMetadataV15Migration(),
             SeriesMetadataV16Migration(),
             SeriesMembershipV17Migration(),
           ];

  final String fileName;
  final AppTelemetry telemetry;
  final DatabaseFactory _databaseFactory;
  final Future<String> Function()? databaseDirectoryProvider;
  final List<StorageMigration> _migrations;

  Database? _database;

  int get _targetVersion => _migrations.isEmpty
      ? 1
      : _migrations.map((x) => x.version).reduce((a, b) => a > b ? a : b);

  @override
  Future<void> initialize() => _database == null
      ? telemetry.measure('db.open', _initialize)
      : _initialize();

  Future<void> _initialize() async {
    if (_database != null) {
      final currentVersion = await _readDatabaseVersion(_database!);
      if (currentVersion < _targetVersion) {
        await _runMigrations(
          _database!,
          fromVersion: currentVersion,
          toVersion: _targetVersion,
        );
        await _database!.execute('PRAGMA user_version = $_targetVersion');
      }
      return;
    }

    final basePath =
        await (databaseDirectoryProvider?.call() ??
            _databaseFactory.getDatabasesPath());
    final fullPath = p.join(basePath, fileName);

    _database = await _databaseFactory.openDatabase(
      fullPath,
      options: OpenDatabaseOptions(
        version: _targetVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // The catalog is a rebuildable cache, so trading the last few
          // transactions on power loss for far fewer fsyncs is worth it.
          // WAL is deliberately not enabled: a playlist import is one very
          // large write transaction, and growing the WAL past the page cache
          // makes every page read go through the wal-index instead.
          await db.execute('PRAGMA synchronous = NORMAL');
          // Negative values are KiB rather than pages; bounded so a TV with
          // little free memory cannot be pushed into swap by an import.
          await db.execute('PRAGMA cache_size = -8000');
        },
        onCreate: (db, version) async {
          await _runMigrations(db, fromVersion: 0, toVersion: version);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _runMigrations(
            db,
            fromVersion: oldVersion,
            toVersion: newVersion,
          );
        },
      ),
    );
  }

  Future<void> _runMigrations(
    Database db, {
    required int fromVersion,
    required int toVersion,
  }) async {
    final applicable =
        _migrations
            .where((m) => m.version > fromVersion && m.version <= toVersion)
            .toList()
          ..sort((a, b) => a.version.compareTo(b.version));
    final now = DateTime.now().toUtc().toIso8601String();

    for (final migration in applicable) {
      await telemetry.measure('db.migration', () async {
        await migration.up(db);
        await db.insert('schema_migrations', {
          'version': migration.version,
          'name': migration.name,
          'applied_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await db.insert('schema_meta', {
          'key': 'schema_version',
          'value': migration.version.toString(),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }, attributes: {'version': migration.version});
    }

    await db.insert('profiles', {
      'id': 'default',
      'name': 'Default',
      'is_default': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('profile_settings', {
      'profile_id': 'default',
      'subtitle_language': null,
      'audio_language': null,
      'watch_history_enabled': 1,
      'autoplay_enabled': 1,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final defaultSettings = <Map<String, Object?>>[
      {'key': 'show_continue_watching', 'value': 'true', 'updated_at': now},
      {'key': 'show_recently_watched', 'value': 'true', 'updated_at': now},
      {'key': 'show_favorites', 'value': 'true', 'updated_at': now},
      {'key': 'animations_enabled', 'value': 'true', 'updated_at': now},
      {'key': 'show_home_live_tv', 'value': 'true', 'updated_at': now},
      {'key': 'show_home_movies', 'value': 'true', 'updated_at': now},
      {'key': 'show_home_series', 'value': 'true', 'updated_at': now},
    ];
    for (final row in defaultSettings) {
      await db.insert(
        'app_settings',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<int> _readDatabaseVersion(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    return rows.first['user_version'] as int? ?? 0;
  }

  @override
  Future<Database> get database async {
    await initialize();
    return _database!;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor txn) action) =>
      telemetry.measure('db.transaction', () async {
        final db = await database;
        return db.transaction(action);
      });

  @override
  Future<void> close() async {
    if (_database == null) return;
    await _database!.close();
    _database = null;
  }
}
