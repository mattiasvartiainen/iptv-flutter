import 'dart:async';
import 'dart:isolate';

import '../../models/content_item.dart';
import 'catalog_repository.dart';
import 'm3u_parser.dart';

typedef CatalogImportOperation<T> =
    Future<T> Function(CatalogImportReporter reporter);

class CatalogImportBatch {
  const CatalogImportBatch({
    required this.batchNumber,
    required this.items,
    required this.parsedItems,
  });

  final int batchNumber;
  final List<ContentItem> items;
  final int parsedItems;
}

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

  Future<int> parseStream(
    Stream<PlaylistSourceChunk> chunks, {
    required String? sourceUrl,
    required CatalogImportReporter reporter,
    required Future<void> Function(CatalogImportBatch batch) onBatch,
  }) async {
    reporter.emit(
      CatalogImportProgress(
        phase: CatalogImportPhase.parsing,
        startedAt: reporter.startedAt,
        current: 0,
        currentOperation: 'parsing',
        message: 'Parsing playlist',
      ),
    );
    final receivePort = ReceivePort();
    final messages = StreamIterator<Map<Object?, Object?>>(
      receivePort.cast<Map<Object?, Object?>>(),
    );
    final isolate = await Isolate.spawn<Map<String, Object?>>(
      _streamParseWorkerEntry,
      <String, Object?>{
        'sourceUrl': sourceUrl,
        'replyTo': receivePort.sendPort,
      },
    );
    var parsedItems = 0;
    var batchNumber = 0;

    Future<Map<Object?, Object?>> nextMessage() async {
      if (!await messages.moveNext()) {
        throw StateError('Parser worker closed before completing.');
      }
      return messages.current;
    }

    Future<void> handleMessagesUntil(String expectedType) async {
      while (true) {
        final message = await nextMessage();
        final type = message['type'];
        if (type == 'error') {
          throw FormatException(
            message['error']?.toString() ?? 'Parsing failed',
          );
        }
        if (type == 'batch') {
          final rows = message['items'] as List<Object?>;
          final items = rows
              .map(_contentItemFromMessage)
              .toList(growable: false);
          parsedItems += items.length;
          await onBatch(
            CatalogImportBatch(
              batchNumber: batchNumber++,
              items: items,
              parsedItems: parsedItems,
            ),
          );
          (message['ackTo']! as SendPort).send(null);
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.parsing,
              startedAt: reporter.startedAt,
              current: parsedItems,
              parsedItems: parsedItems,
              currentOperation: 'parsing',
              message: 'Parsed $parsedItems items',
            ),
          );
          continue;
        }
        if (type == expectedType) return;
      }
    }

    try {
      final ready = await nextMessage();
      final workerPort = ready['sendPort']! as SendPort;
      await for (final chunk in chunks) {
        if (reporter.isCancelled) throw const _ImportCancelled();
        workerPort.send(<String, Object?>{'type': 'chunk', 'text': chunk.text});
        reporter.emit(
          CatalogImportProgress(
            phase: CatalogImportPhase.downloading,
            startedAt: reporter.startedAt,
            current: chunk.received,
            total: chunk.total,
            parsedItems: parsedItems,
            currentOperation: 'downloading',
          ),
        );
        await handleMessagesUntil('chunkDone');
      }
      workerPort.send(<String, Object?>{'type': 'finish'});
      await handleMessagesUntil('complete');
      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.parsing,
          startedAt: reporter.startedAt,
          current: parsedItems,
          total: parsedItems,
          parsedItems: parsedItems,
          currentOperation: 'parsed',
          message: 'Parsed $parsedItems items',
        ),
      );
      return parsedItems;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await messages.cancel();
      receivePort.close();
    }
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

void _streamParseWorkerEntry(Map<String, Object?> request) async {
  final replyTo = request['replyTo']! as SendPort;
  final commands = ReceivePort();
  final parser = M3uStreamingParser(sourceUrl: request['sourceUrl'] as String?);
  replyTo.send(<String, Object?>{
    'type': 'ready',
    'sendPort': commands.sendPort,
  });
  const batchSize = 1000;

  Future<void> sendItems(List<ContentItem> items) async {
    if (items.isEmpty) return;
    final ackPort = ReceivePort();
    replyTo.send(<String, Object?>{
      'type': 'batch',
      'items': items.map(_contentItemToMessage).toList(growable: false),
      'ackTo': ackPort.sendPort,
    });
    await ackPort.first;
    ackPort.close();
  }

  await for (final raw in commands) {
    final command = raw as Map<Object?, Object?>;
    switch (command['type']) {
      case 'chunk':
        final batch = <ContentItem>[];
        parser.addChunk(command['text']! as String, (item) {
          batch.add(item);
        });
        for (var offset = 0; offset < batch.length; offset += batchSize) {
          final end = (offset + batchSize).clamp(0, batch.length);
          await sendItems(batch.sublist(offset, end));
        }
        replyTo.send(<String, Object?>{'type': 'chunkDone'});
      case 'finish':
        final batch = <ContentItem>[];
        parser.finish(batch.add);
        for (var offset = 0; offset < batch.length; offset += batchSize) {
          final end = (offset + batchSize).clamp(0, batch.length);
          await sendItems(batch.sublist(offset, end));
        }
        replyTo.send(<String, Object?>{'type': 'complete'});
        commands.close();
      default:
        replyTo.send(<String, Object?>{
          'type': 'error',
          'error': 'Unknown parser worker command.',
        });
    }
  }
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
