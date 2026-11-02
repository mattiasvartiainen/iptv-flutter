import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/telemetry/otlp_app_telemetry.dart';
import 'package:iptv_flutter/services/telemetry/telemetry_config.dart';

import '../../tool/synthetic_playlist.dart';
import '../support/database_adapter.dart';

void main() {
  test(
    'Windows synthetic playlist and SQLite telemetry reaches Aspire',
    () async {
      final endpoint = const String.fromEnvironment(
        'OTEL_EXPORTER_OTLP_ENDPOINT',
        defaultValue: 'http://localhost:4318',
      );
      final telemetry = OtlpAppTelemetry();
      await telemetry.configure(
        TelemetryConfig(
          enabled: true,
          endpoint: endpoint,
          serviceName: 'iptv-windows-smoke',
          deviceAlias: 'windows-synthetic',
          verbose: true,
          apiKey: Platform.environment['IPTV_OTLP_API_KEY'] ?? '',
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'iptv_telemetry_smoke_',
      );
      final adapter = SqfliteDatabaseAdapter(
        databaseFactory: testDatabaseFactory,
        databaseDirectoryProvider: () async => directory.path,
        telemetry: telemetry,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var playlist = generateSyntheticPlaylist(itemCount: 1000, seed: 42);
      final requests = server.listen((request) async {
        if (request.uri.path == '/fail') {
          request.response.statusCode = HttpStatus.serviceUnavailable;
        } else {
          request.response.write(playlist);
        }
        await request.response.close();
      });
      addTearDown(() async {
        await adapter.close();
        await requests.cancel();
        await server.close(force: true);
        await telemetry.close();
        await directory.delete(recursive: true);
      });
      final repository = SqliteCatalogRepository(
        databaseAdapter: adapter,
        telemetry: telemetry,
        autoStartSearchIndexWorker: false,
      );
      final url = 'http://127.0.0.1:${server.port}/playlist.m3u';
      final cold = await repository.load(
        playlistUrl: url,
        playlistId: 'smoke',
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(cold.itemCount, 1000);
      await repository.load(
        playlistUrl: url,
        playlistId: 'smoke',
        policy: CatalogLoadPolicy.networkOnly,
      );
      playlist = churnSyntheticPlaylist(playlist);
      await repository.load(
        playlistUrl: url,
        playlistId: 'smoke',
        policy: CatalogLoadPolicy.networkOnly,
      );
      await repository.queryItems(const CatalogQuery(playlistId: 'smoke'));
      await repository.homePreview('smoke', kind: CatalogItemKind.live);
      await expectLater(
        repository.load(
          playlistUrl: 'http://127.0.0.1:${server.port}/fail',
          playlistId: 'failure',
          policy: CatalogLoadPolicy.networkOnly,
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        await telemetry.flush(),
        isTrue,
        reason:
            'Aspire must accept logs, traces and metrics on the configured OTLP HTTP endpoint.',
      );
      for (final delivery in telemetry.deliveries.values) {
        expect(delivery.successCount, greaterThan(0));
        expect(delivery.failureCount, 0);
      }
    },
  );
}
