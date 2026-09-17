import 'dart:async';
import 'dart:isolate';

import '../../models/content_item.dart';
import 'catalog_import_progress.dart';
import 'm3u_parser.dart';

typedef CatalogImportOperation<T> = Future<T> Function(
  CatalogImportReporter reporter,
);

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

  Future<List<ContentItem>> parse(
    String text, {
    required String? sourceUrl,
    required CatalogImportReporter reporter,
  }) async {
    reporter.emit(
      CatalogImportProgress(
        phase: CatalogImportPhase.parsing,
        startedAt: reporter.startedAt,
        current: 0,
        message: 'Parsing playlist',
      ),
    );
    final items = await reporter.runCancellable(
      () => _parseInWorker(text, sourceUrl),
    );
    reporter.emit(
      CatalogImportProgress(
        phase: CatalogImportPhase.parsing,
        startedAt: reporter.startedAt,
        current: items.length,
        total: items.length,
        parsedItems: items.length,
        message: 'Parsed ${items.length} items',
      ),
    );
    return items;
  }
}

class CatalogImportReporter {
  CatalogImportReporter._(this._job);

  final _ImportJob<dynamic> _job;

  DateTime get startedAt => _job.startedAt;
  bool get isCancelled => _job.isCancelled;

  void emit(CatalogImportProgress progress) => _job.emit(progress);

  Future<T> runCancellable<T>(Future<T> Function() operation) {
    return _job.runCancellable(operation);
  }
}

class _ImportJob<T> {
  _ImportJob({required this.playlistId}) : startedAt = DateTime.now();

  final String playlistId;
  final DateTime startedAt;
  final _result = Completer<T>();
  final listeners = <CatalogImportProgressCallback>[];
  final cancellationCallbacks = <FutureOr<void> Function()>[];
  String? jobId;
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

  Future<R> runCancellable<R>(Future<R> Function() operation) async {
    final cancellation = Completer<void>();
    void callback() {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    cancellationCallbacks.add(callback);
    try {
      return await Future.any<R>([
        operation(),
        cancellation.future.then<R>((_) => throw const _ImportCancelled()),
      ]);
    } finally {
      cancellationCallbacks.remove(callback);
    }
  }
}

class _ImportCancelled implements Exception {
  const _ImportCancelled();
}

Future<List<ContentItem>> _parseInWorker(String text, String? sourceUrl) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn<Map<String, Object?>>(
    _parseWorkerEntry,
    <String, Object?>{
      'text': text,
      'sourceUrl': sourceUrl,
      'replyTo': receivePort.sendPort,
    },
  );

  try {
    final message = await receivePort.first as Map<Object?, Object?>;
    if (message['ok'] != true) {
      throw FormatException(message['error']?.toString() ?? 'Parsing failed');
    }
    final rows = message['items'] as List<Object?>;
    return rows.map(_contentItemFromMessage).toList(growable: false);
  } finally {
    isolate.kill(priority: Isolate.immediate);
    receivePort.close();
  }
}

void _parseWorkerEntry(Map<String, Object?> request) {
  final replyTo = request['replyTo']! as SendPort;
  try {
    final parsed = const M3uParser().parse(
      request['text']! as String,
      sourceUrl: request['sourceUrl'] as String?,
    );
    replyTo.send(<String, Object?>{
      'ok': true,
      'items': parsed.map(_contentItemToMessage).toList(growable: false),
    });
  } catch (error, stackTrace) {
    replyTo.send(<String, Object?>{
      'ok': false,
      'error': '$error\n$stackTrace',
    });
  }
}

Map<String, Object?> _contentItemToMessage(ContentItem item) {
  return <String, Object?>{
    'id': item.id,
    'title': item.title,
    'type': item.type.index,
    'streamUrl': item.streamUrl,
    'group': item.group,
    'description': item.description,
    'logoUrl': item.logoUrl,
    'posterUrl': item.posterUrl,
    'metadata': item.metadata,
    'sourceIndex': item.sourceIndex,
  };
}

ContentItem _contentItemFromMessage(Object? value) {
  final row = value! as Map<Object?, Object?>;
  return ContentItem(
    id: row['id']! as String,
    title: row['title']! as String,
    type: ContentType.values[row['type']! as int],
    streamUrl: row['streamUrl']! as String,
    group: row['group']! as String,
    description: row['description']! as String,
    logoUrl: row['logoUrl'] as String?,
    posterUrl: row['posterUrl'] as String?,
    metadata: Map<String, String>.from(row['metadata']! as Map),
    sourceIndex: row['sourceIndex']! as int,
  );
}
