import 'dart:io';

import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final DatabaseFactory testDatabaseFactory = _initializeTestDatabaseFactory();

SqfliteDatabaseAdapter createTestDatabaseAdapter({
  String fileName = 'iptv_test.sqlite',
  List<StorageMigration>? migrations,
}) => SqfliteDatabaseAdapter(
  databaseFactory: testDatabaseFactory,
  databaseDirectoryProvider: () async => Directory.systemTemp.path,
  fileName: fileName,
  migrations: migrations,
);

DatabaseFactory _initializeTestDatabaseFactory() {
  sqfliteFfiInit();
  return databaseFactoryFfi;
}
