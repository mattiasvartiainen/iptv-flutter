import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;

import '../catalog/catalog_import_worker.dart';
import '../errors/network_failure_diagnostics.dart';
import 'app_telemetry.dart';
import 'telemetry_config.dart';
import 'tracked_otlp_exporters.dart';

export 'tracked_otlp_exporters.dart' show DeliveryStatus;

class OtlpAppTelemetry extends AppTelemetry {
  OtlpAppTelemetry() : _providerId = 'iptv.${_nextProviderId++}';

  static int _nextProviderId = 0;
  static Future<void>? _sdkSetup;
  final String _providerId;
  int _generation = 0;

  static Future<void> _initializeSdk() async {
    otel.OTelLog.logFunction = null;
    await otel.OTel.initialize(
      serviceName: 'iptv-app',
      detectPlatformResources: false,
      enableLogs: false,
      enableMetrics: false,
      spanProcessor: otel.SimpleSpanProcessor(_DiscardSpanExporter()),
    );
    await otel.OTel.tracerProvider().shutdown();
  }

  TelemetryConfig config = const TelemetryConfig();
  @override
  bool get enabled => config.enabled && _traces != null;
  Map<String, DeliveryStatus> _deliveries = {};
  Map<String, DeliveryStatus> get deliveries => Map.unmodifiable(_deliveries);
  otel.TracerProvider? _traces;
  otel.LoggerProvider? _logs;
  otel.MeterProvider? _metrics;
  otel.APIHistogram? _duration;
  otel.APICounter? _operations;
  int activeOperations = 0;
  Future<bool>? _pendingFlush;

  Future<void> configure(TelemetryConfig next) async {
    next.validate();
    if (activeOperations != 0) {
      throw StateError(
        'Wait for active operations to finish before changing telemetry.',
      );
    }
    await close();
    config = next;
    if (!next.enabled) return;
    await (_sdkSetup ??= _initializeSdk());
    _deliveries = {
      'traces': DeliveryStatus(),
      'logs': DeliveryStatus(),
      'metrics': DeliveryStatus(),
    };
    final protocol = next.protocol == 'http/json'
        ? otel.OtlpHttpProtocol.httpJson
        : otel.OtlpHttpProtocol.httpProtobuf;
    final headers = {if (next.apiKey.isNotEmpty) 'x-otlp-api-key': next.apiKey};
    final spans = otel.BatchSpanProcessor(
      TrackedOtlpSpanExporter(
        otel.OtlpHttpExporterConfig(
          endpoint: next.endpoint,
          headers: headers,
          protocol: protocol,
          timeout: const Duration(seconds: 2),
          maxRetries: 0,
        ),
        _deliveries['traces']!,
      ),
      const otel.BatchSpanProcessorConfig(
        maxQueueSize: 256,
        maxExportBatchSize: 64,
        scheduleDelay: Duration(seconds: 2),
        exportTimeout: Duration(seconds: 3),
      ),
    );
    final logs = otel.BatchLogRecordProcessor(
      TrackedOtlpLogExporter(
        otel.OtlpHttpLogRecordExporterConfig(
          endpoint: next.endpoint,
          headers: headers,
          protocol: protocol,
          timeout: const Duration(seconds: 2),
          maxRetries: 0,
        ),
        _deliveries['logs']!,
      ),
      const otel.BatchLogRecordProcessorConfig(
        maxQueueSize: 256,
        maxExportBatchSize: 64,
        scheduleDelay: Duration(seconds: 2),
        exportTimeout: Duration(seconds: 3),
      ),
    );
    final reader = otel.PeriodicExportingMetricReader(
      TrackedOtlpMetricExporter(
        otel.OtlpHttpMetricExporterConfig(
          endpoint: next.endpoint,
          headers: headers,
          protocol: protocol,
          timeout: const Duration(seconds: 2),
          maxRetries: 0,
        ),
        _deliveries['metrics']!,
      ),
      interval: const Duration(seconds: 10),
      timeout: const Duration(seconds: 3),
    );
    final resourceAttributes = otel.OTel.attributesFromMap({
      'service.name': safeText(next.serviceName),
      'service.version': '1.0.0',
      'service.instance.id': safeText(next.deviceAlias),
    });
    final resource = otel.OTel.resource(resourceAttributes);
    final providerName = '$_providerId.${_generation++}';
    _traces = otel.OTel.addTracerProvider(providerName, resource: resource)
      ..addSpanProcessor(spans);
    _logs = otel.OTel.addLoggerProvider(providerName, resource: resource)
      ..addLogRecordProcessor(logs);
    _metrics = otel.OTel.addMeterProvider(providerName, resource: resource)
      ..addMetricReader(reader);
    final meter = _metrics!.getMeter(name: 'iptv.diagnostics');
    _duration = meter.createHistogram(
      name: 'iptv.operation.duration',
      unit: 's',
    );
    _operations = meter.createCounter(
      name: 'iptv.operations',
      unit: '{operation}',
    );
    event('telemetry.enabled');
  }

  static String safeText(String text) {
    final safe = text.replaceAll(
      RegExp(r'''(?:https?|rtsp|rtmp)://[^\s<>"']+''', caseSensitive: false),
      '[redacted URL]',
    );
    return safe.length > 2048 ? safe.substring(0, 2048) : safe;
  }

  static const _allowedAttributes = {
    'playlistId',
    'jobId',
    'importSessionId',
    'phase',
    'operation',
    'current',
    'total',
    'parsedItems',
    'acceptedItems',
    'rejectedItems',
    'bytesReceived',
    'statusCode',
    'contentLength',
    'batchNumber',
    'batchSize',
    'durationMs',
    'outcome',
    'tier',
    'version',
    'event',
    'severity',
    'kind',
    'offset',
    'limit',
    'count',
    'newCount',
    'changedCount',
    'movedCount',
    'removedCount',
    'currentOperation',
    'parsed',
    'staged',
    'accepted',
    'rejected',
    'indexed',
    'parsingCpuUs',
    'acknowledgementWaitUs',
    'selectionWaitUs',
    'bytes',
    'batchRows',
    'db.system',
    'http.request.method',
    'http.response.status_code',
    'import.kind',
    'new',
    'changed',
    'moved',
    'removed',
    'elapsedMs',
  };

  otel.Attributes _attributes(Map<String, Object?> attributes) =>
      otel.OTel.attributesFromMap({
        for (final entry in attributes.entries)
          if (_allowedAttributes.contains(entry.key) && entry.value != null)
            entry.key: entry.value is num || entry.value is bool
                ? entry.value!
                : safeText(entry.value.toString()),
      });

  @override
  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Map<String, Object?> attributes = const {},
  }) async {
    final provider = _traces;
    if (!config.enabled || provider == null) return action();
    otel.Span? span;
    otel.Context? context;
    try {
      span = provider
          .getTracer('iptv.diagnostics')
          .startSpan(safeText(operation), attributes: _attributes(attributes));
      context = otel.Context.current.withSpan(span);
    } catch (_) {}
    final watch = Stopwatch()..start();
    activeOperations++;
    var outcome = 'success';
    try {
      return await (context == null ? action() : context.run(action));
    } catch (error, stack) {
      outcome = 'failure';
      try {
        span?.setStatus(
          otel.SpanStatusCode.Error,
          error is CatalogImportWorkerException
              ? error.errorType
              : error.runtimeType.toString(),
        );
      } catch (_) {}
      try {
        failure(operation, error, stack);
      } catch (_) {}
      rethrow;
    } finally {
      watch.stop();
      activeOperations--;
      try {
        span?.end();
      } catch (_) {}
      try {
        final dimensions = otel.OTel.attributesFromMap({
          'operation': safeText(operation),
          'outcome': outcome,
        });
        _duration?.record(watch.elapsedMicroseconds / 1000000, dimensions);
        _operations?.add(1, dimensions);
      } catch (_) {}
    }
  }

  @override
  void event(String name, {Map<String, Object?> attributes = const {}}) {
    if (!config.enabled || _logs == null) return;
    try {
      _logs!
          .getLogger('iptv.diagnostics')
          .emit(
            body: safeText(name),
            attributes: _attributes(attributes),
            severityNumber: attributes['severity'] == 'error'
                ? otel.Severity.ERROR
                : attributes['severity'] == 'warning'
                ? otel.Severity.WARN
                : otel.Severity.INFO,
            context: otel.Context.current,
          );
    } catch (_) {}
  }

  @override
  void failure(String name, Object error, StackTrace stackTrace) {
    if (!config.enabled || _logs == null) return;
    try {
      final workerError = error is CatalogImportWorkerException ? error : null;
      final diagnostics =
          workerError?.diagnostics ?? networkFailureDiagnostics(error);
      final stack =
          workerError != null && workerError.workerStackTrace.isNotEmpty
          ? StackTrace.fromString(workerError.workerStackTrace)
          : stackTrace;
      final filteredStack = safeStack(
        stack,
        maxFrames: config.verbose ? 32 : 8,
      );
      final summary = diagnostics['exception.message'];
      _logs!
          .getLogger('iptv.diagnostics')
          .emit(
            body:
                '${safeText(name)} failed'
                '${summary == null ? '' : ': ${safeText(summary.toString())}'}',
            severityNumber: otel.Severity.ERROR,
            attributes: otel.OTel.attributesFromMap({
              'exception.type':
                  workerError?.errorType ?? error.runtimeType.toString(),
              if (workerError != null)
                'exception.wrapper_type': 'CatalogImportWorkerException',
              for (final entry in diagnostics.entries)
                if (const {
                  'exception.message',
                  'exception.os_error_code',
                  'exception.timeout_ms',
                  'tls.failure_reason',
                  'failure.phase',
                  'http.response.status_code',
                }.contains(entry.key))
                  entry.key: entry.value is num
                      ? entry.value
                      : safeText(entry.value.toString()),
              if (error is FileSystemException) ...{
                'exception.message': switch (error.message) {
                  'Creation failed' => 'Could not create a filesystem entry.',
                  'Cannot open file' => 'Could not open a file.',
                  'Write failed' => 'Could not write to a file.',
                  _ when error is PathAccessException =>
                    'Filesystem access was denied.',
                  _ => 'A filesystem operation failed.',
                },
                if (error.osError != null)
                  'exception.os_error_code': error.osError!.errorCode,
              },
              if (filteredStack.isNotEmpty)
                'exception.stacktrace': filteredStack,
            }),
            context: otel.Context.current,
          );
    } catch (_) {}
  }

  Future<bool> flush() {
    return _pendingFlush ??= _flush().whenComplete(() => _pendingFlush = null);
  }

  Future<bool> _flush() async {
    final traces = _traces;
    final logs = _logs;
    final metrics = _metrics;
    final deliveries = _deliveries;
    if (!config.enabled || traces == null || logs == null || metrics == null) {
      return false;
    }
    final before = {
      for (final entry in deliveries.entries)
        entry.key: (entry.value.successCount, entry.value.failureCount),
    };
    try {
      await measure('telemetry.flush', () async {
        event('telemetry.flush');
      });
      await traces.forceFlush();
      await logs.forceFlush();
      final metricsFlushed = await metrics.forceFlush();
      return identical(traces, _traces) &&
          metricsFlushed &&
          deliveries.length == 3 &&
          deliveries.entries.every(
            (entry) =>
                entry.value.successCount > before[entry.key]!.$1 &&
                entry.value.failureCount == before[entry.key]!.$2 &&
                entry.value.lastSucceeded == true,
          );
    } catch (_) {
      return false;
    }
  }

  static String safeStack(StackTrace stack, {int maxFrames = 32}) {
    final dartFrame = RegExp(
      r'^#\d+\s+([A-Za-z0-9_.$<> ]+)\s+\((?:package:([A-Za-z0-9_./]+\.dart)|dart:([A-Za-z0-9_./]+)):(\d+):(\d+)\)$',
    );
    final aotFrame = RegExp(
      r'^\s*#\d+\s+abs\s+[0-9a-fA-F]+\s+virt\s+[0-9a-fA-F]+(?:\s+[A-Za-z0-9_.$<>+ -]+)?$',
    );
    return stack
        .toString()
        .split('\n')
        .where((line) => dartFrame.hasMatch(line) || aotFrame.hasMatch(line))
        .take(maxFrames)
        .join('\n');
  }

  Future<void> close() async {
    final traces = _traces;
    final logs = _logs;
    final metrics = _metrics;
    _traces = null;
    _logs = null;
    _metrics = null;
    _duration = null;
    _operations = null;
    try {
      await traces?.shutdown();
    } catch (_) {}
    try {
      await logs?.shutdown();
    } catch (_) {}
    try {
      await metrics?.shutdown();
    } catch (_) {}
  }
}

class _DiscardSpanExporter implements otel.SpanExporter {
  @override
  Future<void> export(List<otel.Span> spans) async {}

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}
