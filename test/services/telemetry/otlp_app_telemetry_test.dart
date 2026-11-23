import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/telemetry/otlp_app_telemetry.dart';
import 'package:iptv_flutter/services/telemetry/telemetry_config.dart';

void main() {
  test(
    'exports logs, correlated spans and metrics and replaces endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String, List<Map<String, dynamic>>>{};
      final subscription = server.listen((request) async {
        final json =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        received.putIfAbsent(request.uri.path, () => []).add(json);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      final telemetry = OtlpAppTelemetry();
      addTearDown(() async {
        await telemetry.close();
        await subscription.cancel();
        await server.close(force: true);
      });
      await telemetry.configure(
        TelemetryConfig(
          enabled: true,
          endpoint: 'http://127.0.0.1:${server.port}',
          protocol: 'http/json',
        ),
      );
      await telemetry.measure('playlist.import', () async {
        telemetry.event(
          'import.started',
          attributes: {
            'playlistId': 'fixture',
            'url': 'https://secret.test/user/password',
          },
        );
        await telemetry.measure('db.write', () async {});
      });
      expect(await telemetry.flush(), isTrue);
      expect(
        received.keys,
        containsAll(['/v1/logs', '/v1/traces', '/v1/metrics']),
      );
      final payload = jsonEncode(received);
      expect(payload, contains('playlist.import'));
      expect(payload, contains('iptv.operation.duration'));
      expect(payload, isNot(contains('password')));
      final spans = received['/v1/traces']!
          .expand(
            (request) =>
                (request['resourceSpans'] as List).cast<Map<String, dynamic>>(),
          )
          .expand(
            (resource) =>
                (resource['scopeSpans'] as List).cast<Map<String, dynamic>>(),
          )
          .expand(
            (scope) => (scope['spans'] as List).cast<Map<String, dynamic>>(),
          )
          .toList();
      final root = spans.singleWhere(
        (span) => span['name'] == 'playlist.import',
      );
      final child = spans.singleWhere((span) => span['name'] == 'db.write');
      expect(child['traceId'], root['traceId']);
      expect(child['parentSpanId'], root['spanId']);
      final records = received['/v1/logs']!
          .expand(
            (request) =>
                (request['resourceLogs'] as List).cast<Map<String, dynamic>>(),
          )
          .expand(
            (resource) =>
                (resource['scopeLogs'] as List).cast<Map<String, dynamic>>(),
          )
          .expand(
            (scope) =>
                (scope['logRecords'] as List).cast<Map<String, dynamic>>(),
          );
      expect(
        records.any((record) => record['traceId'] == root['traceId']),
        isTrue,
      );
      await telemetry.configure(const TelemetryConfig());
      expect(await telemetry.flush(), isFalse);
      await telemetry.configure(
        TelemetryConfig(
          enabled: true,
          endpoint: 'http://127.0.0.1:${server.port}',
          protocol: 'http/json',
          deviceAlias: 'replacement',
        ),
      );
      await telemetry.measure('replacement.test', () async {});
      expect(await telemetry.flush(), isTrue);
      expect(jsonEncode(received), contains('replacement.test'));
    },
  );

  test('sanitizes credential and SQL errors and retains safe frames', () async {
    final collector = await _Collector.start();
    final telemetry = OtlpAppTelemetry();
    addTearDown(() async {
      await telemetry.close();
      await collector.close();
    });
    await telemetry.configure(collector.config(verbose: true));
    final error = StateError(
      'SELECT stream_url FROM items WHERE password = sql-secret '
      'https://user:credential@provider.test/live?token=api-secret',
    );
    final stack = StackTrace.fromString(
      '#0      importRows (package:iptv_flutter/services/import.dart:12:3)\n'
      'SQL parameters: [sql-secret, credential]\n'
      '#1      leak (https://user:credential@host.test/source.dart:1:2)\n'
      '#2      main (file:///Users/credential/source.dart:1:2)\n'
      '#3      bad (package:iptv_flutter/sql-secret.dart:1:2)\n',
    );
    var invocations = 0;
    await expectLater(
      telemetry.measure('playlist.import', () async {
        invocations++;
        Error.throwWithStackTrace(error, stack);
      }),
      throwsA(same(error)),
    );
    expect(invocations, 1);
    expect(telemetry.activeOperations, 0);
    expect(await telemetry.flush(), isTrue);
    final payload = jsonEncode(collector.received);
    expect(payload, contains('StateError'));
    expect(payload, contains('importRows'));
    expect(payload, contains('services/import.dart:12:3'));
    for (final secret in ['SELECT', 'sql-secret', 'credential', 'api-secret']) {
      expect(payload, isNot(contains(secret)));
    }
  });

  for (final failedPath in [null, '/v1/logs', '/v1/traces', '/v1/metrics']) {
    test('reports collector 401 for ${failedPath ?? 'all signals'}', () async {
      final collector = await _Collector.start(
        status: (path) => failedPath == null || path == failedPath ? 401 : 200,
      );
      final telemetry = OtlpAppTelemetry();
      addTearDown(() async {
        await telemetry.close();
        await collector.close();
      });
      await telemetry.configure(collector.config());
      var invocations = 0;
      expect(
        await telemetry.measure('playlist.import', () async {
          invocations++;
          return 42;
        }),
        42,
      );
      expect(invocations, 1);
      expect(await telemetry.flush(), isFalse);
      final signal = failedPath?.split('/').last;
      final failed = signal == null
          ? telemetry.deliveries.values
          : [telemetry.deliveries[signal]!];
      expect(failed.every((delivery) => delivery.failureCount > 0), isTrue);
      expect(
        failed.every((delivery) => delivery.lastSucceeded == false),
        isTrue,
      );
      expect(
        jsonEncode(failed.map((delivery) => delivery.lastFailure).toList()),
        isNot(contains('http')),
      );
      collector.status = (_) => 200;
      expect(await telemetry.flush(), isTrue);
      collector.status = (_) => 401;
      expect(await telemetry.flush(), isFalse);
    });
  }

  test('unreachable collector preserves business results and errors', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final telemetry = OtlpAppTelemetry();
    addTearDown(telemetry.close);
    await telemetry.configure(
      TelemetryConfig(
        enabled: true,
        endpoint: 'http://127.0.0.1:$port',
        protocol: 'http/json',
      ),
    );
    var invocations = 0;
    expect(
      await telemetry.measure('playlist.import', () async {
        invocations++;
        return 7;
      }),
      7,
    );
    final error = StateError('SQL params contain password');
    await expectLater(
      telemetry.measure('playlist.import', () async {
        invocations++;
        throw error;
      }),
      throwsA(same(error)),
    );
    expect(invocations, 2);
    expect(telemetry.activeOperations, 0);
    expect(await telemetry.flush(), isFalse);
    expect(
      telemetry.deliveries.values.every((status) => status.successCount == 0),
      isTrue,
    );
    await telemetry.close();
    expect(await telemetry.flush(), isFalse);
  });

  test(
    'replaces endpoint and resources, isolates instances, disables traffic',
    () async {
      final first = await _Collector.start();
      final second = await _Collector.start();
      final telemetry = OtlpAppTelemetry();
      final other = OtlpAppTelemetry();
      addTearDown(() async {
        await telemetry.close();
        await other.close();
        await first.close();
        await second.close();
      });
      await Future.wait([
        telemetry.configure(first.config(service: 'original-service')),
        other.configure(first.config(service: 'other-service')),
      ]);
      expect(await telemetry.flush(), isTrue);
      expect(await other.flush(), isTrue);
      await telemetry.configure(second.config(service: 'replacement-service'));
      final previousRequests = first.received.length;
      expect(await telemetry.flush(), isTrue);
      expect(first.received.length, previousRequests);
      final payload = jsonEncode(second.received);
      expect(payload, contains('replacement-service'));
      expect(payload, isNot(contains('original-service')));
      expect(payload, isNot(contains('other-service')));
      for (final key in ['host.name', 'host.id', 'os.type', 'device.id']) {
        expect(payload, isNot(contains(key)));
      }
      await telemetry.configure(const TelemetryConfig());
      final disabledRequests = second.received.length;
      expect(await telemetry.measure('disabled', () async => 99), 99);
      telemetry.event('disabled');
      telemetry.failure('disabled', StateError('secret'), StackTrace.current);
      expect(await telemetry.flush(), isFalse);
      await telemetry.close();
      expect(second.received.length, disabledRequests);
      expect(await other.flush(), isTrue);
    },
  );

  test('span setup failure invokes action exactly once', () async {
    final collector = await _Collector.start();
    final telemetry = OtlpAppTelemetry();
    addTearDown(() async {
      await telemetry.close();
      await collector.close();
    });
    await telemetry.configure(collector.config());
    var invocations = 0;
    expect(
      await telemetry.measure('import', () async {
        invocations++;
        return 123;
      }, attributes: {'phase': _ThrowingText()}),
      123,
    );
    expect(invocations, 1);
    expect(telemetry.activeOperations, 0);
  });

  test('retains known import attributes and omits nonverbose stacks', () async {
    final collector = await _Collector.start();
    final telemetry = OtlpAppTelemetry();
    addTearDown(() async {
      await telemetry.close();
      await collector.close();
    });
    await telemetry.configure(collector.config());
    const attributes = <String, Object>{
      'currentOperation': 'parse',
      'parsed': 1,
      'staged': 2,
      'accepted': 3,
      'rejected': 4,
      'indexed': 5,
      'parsingCpuUs': 6,
      'acknowledgementWaitUs': 7,
      'selectionWaitUs': 8,
      'bytes': 9,
      'batchRows': 10,
      'db.system': 'sqlite',
      'http.request.method': 'GET',
      'http.response.status_code': 200,
      'import.kind': 'm3u',
      'new': 11,
      'changed': 12,
      'moved': 13,
      'removed': 14,
      'elapsedMs': 15,
    };
    await telemetry.measure('import.attributes', () async {
      telemetry.event(
        'import.progress',
        attributes: {
          ...attributes,
          'sql.parameters': 'sql-secret',
          'http.url': 'https://credential@host.test/private',
        },
      );
      telemetry.failure('import', StateError('sql-secret'), StackTrace.current);
    }, attributes: attributes);
    expect(await telemetry.flush(), isTrue);
    final payload = jsonEncode(collector.received);
    for (final name in attributes.keys) {
      expect(payload, contains('"key":"$name"'));
    }
    expect(payload, isNot(contains('sql-secret')));
    expect(payload, isNot(contains('credential')));
    expect(payload, isNot(contains('exception.stacktrace')));
  });

  test('rejects unsafe endpoints and keeps keys out of persisted settings', () {
    for (final endpoint in [
      'http://localhost:18888',
      'http://user:pass@host:4318',
      'http://host:4318?token=secret',
      'file:///tmp/logs',
      'http://host/v1/logs',
    ]) {
      expect(
        () => TelemetryConfig(endpoint: endpoint).validate(),
        throwsFormatException,
      );
    }
    expect(
      jsonEncode(const TelemetryConfig(apiKey: 'secret').toJson()),
      isNot(contains('secret')),
    );
  });

  test(
    'exports safe filesystem diagnostics without paths or messages',
    () async {
      final collector = await _Collector.start();
      final telemetry = OtlpAppTelemetry();
      addTearDown(() async {
        await telemetry.close();
        await collector.close();
      });
      await telemetry.configure(collector.config());
      telemetry.failure(
        'telemetry.settings.save',
        const PathAccessException(
          '/private/secret-path',
          OSError('secret operating system message', 13),
          'Creation failed',
        ),
        StackTrace.current,
      );
      telemetry.failure(
        'other',
        const FileSystemException(
          'secret error message',
          '/private/secret-path',
        ),
        StackTrace.current,
      );
      expect(await telemetry.flush(), isTrue);
      final payload = jsonEncode(collector.received);
      expect(payload, contains('Could not create a filesystem entry.'));
      expect(payload, contains('A filesystem operation failed.'));
      expect(payload, contains('PathAccessException'));
      expect(payload, contains('exception.os_error_code'));
      expect(payload, contains('13'));
      expect(payload, isNot(contains('secret-path')));
      expect(payload, isNot(contains('secret operating system message')));
      expect(payload, isNot(contains('secret error message')));
    },
  );
}

class _ThrowingText {
  @override
  String toString() => throw StateError('SDK attribute conversion failed');
}

class _Collector {
  _Collector(this.server, this.status);

  final HttpServer server;
  int Function(String) status;
  final received = <Map<String, dynamic>>[];
  late final StreamSubscription<HttpRequest> subscription;

  static Future<_Collector> start({int Function(String)? status}) async {
    final collector = _Collector(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      status ?? (_) => 200,
    );
    collector.subscription = collector.server.listen((request) async {
      collector.received.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.statusCode = collector.status(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    return collector;
  }

  TelemetryConfig config({
    bool verbose = false,
    String service = 'iptv-test',
  }) => TelemetryConfig(
    enabled: true,
    endpoint: 'http://127.0.0.1:${server.port}',
    protocol: 'http/json',
    verbose: verbose,
    serviceName: service,
  );

  Future<void> close() async {
    await subscription.cancel();
    await server.close(force: true);
  }
}
