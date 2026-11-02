import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;

class DeliveryStatus {
  int _successCount = 0;
  int _failureCount = 0;
  String? _lastFailure;
  bool? _lastSucceeded;

  int get successCount => _successCount;
  int get failureCount => _failureCount;
  String? get lastFailure => _lastFailure;
  bool? get lastSucceeded => _lastSucceeded;

  void _success() {
    _successCount++;
    _lastSucceeded = true;
  }

  void _failure([Object? error]) {
    _failureCount++;
    _lastSucceeded = false;
    _lastFailure = error == null
        ? 'ExportFailure'
        : error.runtimeType.toString();
  }
}

class TrackedOtlpSpanExporter extends otel.OtlpHttpSpanExporter {
  TrackedOtlpSpanExporter(super.config, this.delivery);

  final DeliveryStatus delivery;
  bool _closed = false;

  @override
  Future<void> export(List<otel.Span> spans) async {
    if (spans.isEmpty) return;
    if (_closed) {
      delivery._failure();
      return;
    }
    try {
      await super.export(spans);
      if (_closed) {
        delivery._failure();
      } else {
        delivery._success();
      }
    } catch (error) {
      delivery._failure(error);
    }
  }

  @override
  Future<void> shutdown() async {
    _closed = true;
    await super.shutdown();
  }
}

class TrackedOtlpLogExporter extends otel.OtlpHttpLogRecordExporter {
  TrackedOtlpLogExporter(super.config, this.delivery);

  final DeliveryStatus delivery;

  @override
  Future<otel.ExportResult> export(
    List<otel.ReadableLogRecord> logRecords,
  ) async {
    if (logRecords.isEmpty) return otel.ExportResult.success;
    try {
      final result = await super.export(logRecords);
      if (result == otel.ExportResult.success) {
        delivery._success();
      } else {
        delivery._failure();
      }
      return result;
    } catch (error) {
      delivery._failure(error);
      return otel.ExportResult.failure;
    }
  }
}

class TrackedOtlpMetricExporter extends otel.OtlpHttpMetricExporter {
  TrackedOtlpMetricExporter(super.config, this.delivery);

  final DeliveryStatus delivery;

  @override
  Future<bool> export(otel.MetricData metrics) async {
    if (metrics.metrics.isEmpty) return false;
    try {
      final result = await super.export(metrics);
      if (result) {
        delivery._success();
      } else {
        delivery._failure();
      }
      return result;
    } catch (error) {
      delivery._failure(error);
      return false;
    }
  }
}
