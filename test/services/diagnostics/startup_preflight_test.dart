import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/diagnostics/startup_preflight.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('SqlitePreflightCheck', () {
    test('reports the SQLite version and FTS5 support', () async {
      sqfliteFfiInit();
      final check = SqlitePreflightCheck(databaseFactory: databaseFactoryFfi);

      final result = await check.run();

      expect(result.status, PreflightStatus.ok);
      expect(result.details['sqlite.version'], isA<String>());
      expect(result.details['sqlite.fts5'], isTrue);
    });

    test('fails without throwing when the database cannot be opened', () async {
      final check = SqlitePreflightCheck(
        databaseFactory: _ThrowingDatabaseFactory(),
      );

      final result = await check.run();

      expect(result.status, PreflightStatus.failed);
      expect(result.message, contains('in-memory'));
    });

    test('reports an FTS5 probe error and closes the database', () async {
      final database = _FtsFailureDatabase();
      final check = SqlitePreflightCheck(
        databaseFactory: _DatabaseFactoryStub(database),
      );

      final result = await check.run();

      expect(result.status, PreflightStatus.failed);
      expect(result.message, contains('no such module: fts5'));
      expect(result.details['sqlite.version'], '3.45.0');
      expect(database.closed, isTrue);
    });
  });

  group('StartupPreflight', () {
    test('runs every check and logs the outcomes', () async {
      final logger = _RecordingLogger();
      final preflight = StartupPreflight(
        checks: [
          _StubCheck('passing', const PreflightResult.ok(details: {'k': 'v'})),
          _StubCheck(
            'failing',
            const PreflightResult.failed(message: 'broken'),
          ),
        ],
        logger: logger,
      );

      final results = await preflight.run();

      expect(results['passing']!.status, PreflightStatus.ok);
      expect(results['failing']!.status, PreflightStatus.failed);
      expect(logger.infos.single, contains('"passing" passed'));
      expect(logger.errors.single, contains('broken'));
    });

    test('a throwing check is reported as failed and does not abort', () async {
      final logger = _RecordingLogger();
      final preflight = StartupPreflight(
        checks: [
          _ThrowingCheck(),
          _StubCheck('after', const PreflightResult.ok()),
        ],
        logger: logger,
      );

      final results = await preflight.run();

      expect(results['throwing']!.status, PreflightStatus.failed);
      expect(results['after']!.status, PreflightStatus.ok);
      expect(logger.errors.single, contains('threw unexpectedly'));
    });
  });
}

class _StubCheck implements PreflightCheck {
  _StubCheck(this.name, this.result);

  @override
  final String name;
  final PreflightResult result;

  @override
  Future<PreflightResult> run() async => result;
}

class _ThrowingCheck implements PreflightCheck {
  @override
  String get name => 'throwing';

  @override
  Future<PreflightResult> run() async => throw StateError('boom');
}

class _ThrowingDatabaseFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    throw StateError('open refused');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _DatabaseFactoryStub implements DatabaseFactory {
  _DatabaseFactoryStub(this.database);

  final Database database;

  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) async => database;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FtsFailureDatabase implements Database {
  bool closed = false;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => [
    {'version': '3.45.0'},
  ];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    throw StateError('no such module: fts5');
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingLogger implements AppLogger {
  final infos = <String>[];
  final warnings = <String>[];
  final errors = <String>[];

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {
    infos.add(message);
  }

  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {
    warnings.add(message);
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    errors.add(message);
  }
}
