import 'package:sqflite_common/sqlite_api.dart';

import '../logging/app_logger.dart';
import '../telemetry/app_telemetry.dart';

enum PreflightStatus { ok, failed }

/// Outcome of a single [PreflightCheck].
class PreflightResult {
  const PreflightResult.ok({this.details = const {}})
    : status = PreflightStatus.ok,
      message = null;

  const PreflightResult.failed({required this.message, this.details = const {}})
    : status = PreflightStatus.failed;

  final PreflightStatus status;

  /// Human-readable failure explanation; `null` when the check passed.
  final String? message;

  /// Structured findings (versions, feature flags) for logs and telemetry.
  final Map<String, Object?> details;
}

/// A startup environment probe.
///
/// Checks verify assumptions about the runtime environment (SQLite features,
/// reachability of external services, ...) and report findings instead of
/// throwing. Register new checks in `AppDependencies.create`.
abstract interface class PreflightCheck {
  /// Stable identifier used in log context and telemetry attributes.
  String get name;

  Future<PreflightResult> run();
}

/// Runs all registered [PreflightCheck]s and reports their outcomes.
///
/// Preflight is diagnostic only: failed checks are reported and startup
/// continues to the real initialization.
class StartupPreflight {
  const StartupPreflight({
    required List<PreflightCheck> checks,
    AppLogger logger = const DebugAppLogger(),
    AppTelemetry telemetry = const NoopAppTelemetry(),
  }) : _checks = checks,
       _logger = logger,
       _telemetry = telemetry;

  final List<PreflightCheck> _checks;
  final AppLogger _logger;
  final AppTelemetry _telemetry;

  Future<Map<String, PreflightResult>> run() async {
    final results = <String, PreflightResult>{};
    for (final check in _checks) {
      PreflightResult result;
      try {
        result = await _telemetry.measure(
          'preflight.${check.name}',
          check.run,
          attributes: {'preflight.check': check.name},
        );
      } catch (error, stackTrace) {
        _telemetry.failure('preflight.${check.name}', error, stackTrace);
        _logger.error(
          'Preflight check "${check.name}" threw unexpectedly',
          error: error,
          stackTrace: stackTrace,
          context: {'preflight.check': check.name},
        );
        results[check.name] = PreflightResult.failed(
          message: 'Preflight check threw: $error',
        );
        continue;
      }
      results[check.name] = result;
      final context = <String, Object?>{
        'preflight.check': check.name,
        ...result.details,
      };
      switch (result.status) {
        case PreflightStatus.ok:
          _logger.info(
            'Preflight check "${check.name}" passed',
            context: context,
          );
        case PreflightStatus.failed:
          _logger.error(
            'Preflight check "${check.name}" failed: ${result.message}',
            context: context,
          );
      }
    }
    return results;
  }
}

/// Verifies that the SQLite runtime behind the injected [DatabaseFactory]
/// can support the application schema before the real database is opened.
///
/// Probes an in-memory database for the SQLite version and FTS5 support.
/// FTS5 matters because the catalog search migration creates `fts5` virtual
/// tables; on webOS the sqflite plugin links the TV firmware's system
/// libsqlite3, where FTS5 is not guaranteed to be compiled in.
class SqlitePreflightCheck implements PreflightCheck {
  const SqlitePreflightCheck({required DatabaseFactory databaseFactory})
    : _databaseFactory = databaseFactory;

  final DatabaseFactory _databaseFactory;

  @override
  String get name => 'sqlite';

  @override
  Future<PreflightResult> run() async {
    final Database db;
    try {
      db = await _databaseFactory.openDatabase(inMemoryDatabasePath);
    } catch (error) {
      return PreflightResult.failed(
        message: 'Unable to open an in-memory SQLite database: $error',
      );
    }
    try {
      String? version;
      try {
        final rows = await db.rawQuery('SELECT sqlite_version() AS version');
        version = rows.first['version'] as String?;
      } catch (error) {
        return PreflightResult.failed(
          message: 'Unable to read the SQLite version: $error',
        );
      }

      try {
        await db.execute(
          'CREATE VIRTUAL TABLE preflight_fts USING fts5(title)',
        );
        await db.execute('DROP TABLE preflight_fts');
      } catch (error) {
        return PreflightResult.failed(
          message: 'SQLite FTS5 probe failed: $error',
          details: {'sqlite.version': version},
        );
      }

      final details = <String, Object?>{
        'sqlite.version': version,
        'sqlite.fts5': true,
      };
      return PreflightResult.ok(details: details);
    } finally {
      await db.close();
    }
  }
}
