import 'dart:async';

import 'catalog_import_progress.dart';
import 'catalog_import_protocol.dart'
    show
        CatalogImportRowSelector,
        CatalogImportRowsCallback,
        CatalogImportWorkerResult;
import 'catalog_import_worker.dart';

typedef CatalogImportOperation<T> =
    Future<T> Function(CatalogImportReporter reporter);

class CatalogImportCoordinator {
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

    final job = _ImportJob<T>(playlistId: playlistId);
    job.listen(onProgress);
    _jobs[playlistId] = job;
    final reporter = CatalogImportReporter._(job);
    job.emit(
      CatalogImportProgress(
        phase: CatalogImportPhase.starting,
        startedAt: DateTime.now(),
        message: 'Preparing playlist import',
      ),
    );

    () async {
      try {
        final result = await operation(reporter);
        job.emit(
          CatalogImportProgress(
            phase: CatalogImportPhase.completed,
            startedAt: DateTime.now(),
            message: 'Playlist import completed',
          ),
        );
        job.complete(result);
      } catch (error, stackTrace) {
        job.emit(
          CatalogImportProgress(
            phase: job.isCancelled
                ? CatalogImportPhase.cancelled
                : CatalogImportPhase.failed,
            startedAt: DateTime.now(),
            message: job.isCancelled
                ? 'Playlist import cancelled'
                : 'Playlist import failed',
            error: error,
          ),
        );
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
  _ImportJob({required this.playlistId}) : startedAt = DateTime.now();

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
    for (final listener in List.of(listeners)) {
      listener(enriched);
    }
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
