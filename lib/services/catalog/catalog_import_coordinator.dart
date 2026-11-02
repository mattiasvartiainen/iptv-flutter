import 'dart:async';

import '../telemetry/app_telemetry.dart';
import 'catalog_import_progress.dart';
import 'catalog_import_protocol.dart'
    show
        CatalogImportCancelledException,
        CatalogImportRowSelector,
        CatalogImportRowsCallback,
        CatalogImportWorkerResult;
import 'catalog_import_worker.dart';

typedef CatalogImportOperation<T> =
    Future<T> Function(CatalogImportReporter reporter);

class CatalogImportCoordinator {
  CatalogImportCoordinator({AppTelemetry telemetry = const NoopAppTelemetry()})
    : _telemetry = telemetry;

  final AppTelemetry _telemetry;
  final Map<String, _ImportJob<dynamic>> _jobs = {};

  Future<T> run<T>({
    required String playlistId,
    required CatalogImportOperation<T> operation,
    CatalogImportProgressCallback? onProgress,
  }) {
    final existing = _jobs[playlistId];
    if (existing != null) {
      existing.listen(onProgress);
      return existing.future.then((value) => value as T);
    }

    final job = _ImportJob<T>(playlistId: playlistId, telemetry: _telemetry);
    job.listen(onProgress);
    _jobs[playlistId] = job;
    final reporter = CatalogImportReporter._(job);
    () async {
      try {
        final result = await _telemetry.measure('playlist.import', () async {
          job.telemetryZone = Zone.current;
          job.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.starting,
              startedAt: job.startedAt,
              message: 'Preparing playlist import',
            ),
          );
          final heartbeat = !_telemetry.enabled
              ? null
              : Timer.periodic(const Duration(seconds: 5), (_) {
                  job.emitHeartbeat();
                });
          try {
            final value = await operation(reporter);
            job.emitTerminal(CatalogImportPhase.completed);
            return value;
          } catch (error) {
            job.emitTerminal(
              job.isCancelled || error is CatalogImportCancelledException
                  ? CatalogImportPhase.cancelled
                  : CatalogImportPhase.failed,
              error: error,
            );
            rethrow;
          } finally {
            heartbeat?.cancel();
          }
        }, attributes: const {'import.kind': 'playlist'});
        job.complete(result);
      } catch (error, stackTrace) {
        job.fail(error, stackTrace);
      } finally {
        _jobs.remove(playlistId);
      }
    }();

    return job.future;
  }

  Future<void> cancel(String playlistId) async {
    await _jobs[playlistId]?.cancel();
  }

  Future<CatalogImportWorkerResult> importPlaylist({
    required String playlistId,
    required String playlistUrl,
    String? sourceUrl,
    required CatalogImportRowSelector selectRows,
    required CatalogImportRowsCallback onRows,
    CatalogImportProgressCallback? onProgress,
  }) => run<CatalogImportWorkerResult>(
    playlistId: playlistId,
    onProgress: onProgress,
    operation: (reporter) async {
      final worker = await CatalogImportWorker.start(
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        telemetry: _telemetry,
        sourceUrl: sourceUrl,
        selectRows: selectRows,
        onRows: onRows,
        onHeaders: (headers) => reporter.emit(
          CatalogImportProgress(
            phase: CatalogImportPhase.downloading,
            startedAt: reporter.startedAt,
            current: 0,
            total: headers.contentLength,
            currentOperation: 'headers',
          ),
        ),
        onProgress: (received, total, parsed) {
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.downloading,
              startedAt: reporter.startedAt,
              current: received,
              total: total,
              parsedItems: parsed,
              currentOperation: 'downloading',
            ),
          );
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.parsing,
              startedAt: reporter.startedAt,
              current: parsed,
              parsedItems: parsed,
              currentOperation: 'parsing',
            ),
          );
        },
      );
      reporter.onCancel(worker.cancel);
      return worker.done;
    },
  );
}

class CatalogImportReporter {
  CatalogImportReporter._(this._job);

  final _ImportJob<dynamic> _job;

  DateTime get startedAt => _job.startedAt;
  bool get isCancelled => _job.isCancelled;

  void attachSession(int sessionId) {
    _job.importSessionId = sessionId;
  }

  void onCancel(FutureOr<void> Function() callback) {
    if (_job.isCancelled) {
      unawaited(Future<void>.sync(callback));
      return;
    }
    _job.cancellationCallbacks.add(callback);
  }

  void emit(CatalogImportProgress progress) => _job.emit(progress);
}

class _ImportJob<T> {
  _ImportJob({required this.playlistId, required this.telemetry})
    : startedAt = DateTime.now();

  final AppTelemetry telemetry;
  Zone? telemetryZone;
  CatalogImportProgress? lastProgress;
  DateTime? lastTelemetryAt;
  final String playlistId;
  final DateTime startedAt;
  final _result = Completer<T>();
  final listeners = <CatalogImportProgressCallback>[];
  final cancellationCallbacks = <FutureOr<void> Function()>[];
  String? jobId;
  int? importSessionId;
  bool isCancelled = false;

  Future<T> get future => _result.future;

  void listen(CatalogImportProgressCallback? listener) {
    if (listener != null) listeners.add(listener);
  }

  void emit(CatalogImportProgress progress) {
    jobId ??= '${playlistId}_${startedAt.microsecondsSinceEpoch}';
    final enriched = progress.copyWith(
      jobId: jobId,
      playlistId: playlistId,
      importSessionId: importSessionId,
      startedAt: startedAt,
      updatedAt: DateTime.now(),
    );
    lastProgress = enriched.copyWith(
      parsedItems: enriched.parsedItems == 0 ? lastProgress?.parsedItems : null,
      stagedItems: enriched.stagedItems == 0 ? lastProgress?.stagedItems : null,
      acceptedItems: enriched.acceptedItems == 0
          ? lastProgress?.acceptedItems
          : null,
      rejectedItems: enriched.rejectedItems == 0
          ? lastProgress?.rejectedItems
          : null,
      indexedItems: enriched.indexedItems == 0
          ? lastProgress?.indexedItems
          : null,
    );
    if (telemetry.enabled &&
        (lastTelemetryAt == null ||
            enriched.isTerminal ||
            DateTime.now().difference(lastTelemetryAt!) >=
                const Duration(seconds: 2))) {
      _event('playlist.import.progress', lastProgress!);
    }
    for (final listener in List.of(listeners)) {
      listener(enriched);
    }
  }

  void emitTerminal(CatalogImportPhase phase, {Object? error}) {
    emit(
      (lastProgress ??
              CatalogImportProgress(phase: phase, startedAt: startedAt))
          .copyWith(
            phase: phase,
            error: error,
            message: switch (phase) {
              CatalogImportPhase.completed => 'Playlist import completed',
              CatalogImportPhase.cancelled => 'Playlist import cancelled',
              _ => 'Playlist import failed',
            },
          ),
    );
  }

  void emitHeartbeat() {
    final progress = lastProgress;
    if (progress != null &&
        !progress.isTerminal &&
        DateTime.now().difference(lastTelemetryAt!) >=
            const Duration(seconds: 5)) {
      _event('playlist.import.heartbeat', progress);
    }
  }

  void _event(String name, CatalogImportProgress progress) {
    lastTelemetryAt = DateTime.now();
    telemetryZone!.run(
      () => telemetry.event(
        name,
        attributes: {
          'playlistId': playlistId,
          'jobId': jobId,
          'importSessionId': importSessionId,
          'phase': progress.phase.name,
          'currentOperation': progress.currentOperation,
          'current': progress.current,
          'total': progress.total,
          'parsed': progress.parsedItems,
          'staged': progress.stagedItems,
          'accepted': progress.acceptedItems,
          'rejected': progress.rejectedItems,
          'indexed': progress.indexedItems,
        },
      ),
    );
  }

  void complete(T value) {
    if (!_result.isCompleted) _result.complete(value);
  }

  void fail(Object error, StackTrace stackTrace) {
    if (!_result.isCompleted) _result.completeError(error, stackTrace);
  }

  Future<void> cancel() async {
    if (isCancelled) return;
    isCancelled = true;
    for (final callback in List.of(cancellationCallbacks)) {
      await callback();
    }
  }
}
