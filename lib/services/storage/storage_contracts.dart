import 'package:sqflite_common/sqlite_api.dart';

abstract interface class DatabaseAdapter {
  Future<void> initialize();
  Future<Database> get database;
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor txn) action);
  Future<void> close();
}

abstract interface class StorageMigration {
  int get version;
  String get name;
  Future<void> up(DatabaseExecutor db);
}
