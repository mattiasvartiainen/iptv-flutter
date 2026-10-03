import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../models/content_item.dart';
import '../security/url_redaction.dart';
import 'catalog_classifier.dart';
import 'catalog_hash.dart';
import 'catalog_import_protocol.dart';
import 'catalog_normalizer.dart';
import 'm3u_parser.dart';

class CatalogImportWorkerHandle {
  CatalogImportWorkerHandle._({
    required this.done,
    required Isolate isolate,
    required ReceivePort commands,
    required SendPort workerCommands,
  }) : _isolate = isolate,
       _commands = commands,
       _workerCommands = workerCommands;

  final Future<CatalogImportWorkerResult> done;
  final Isolate _isolate;
  final ReceivePort _commands;
  final SendPort _workerCommands;
  final Completer<void> _cancellation = Completer<void>();
  bool _cancelled = false;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    if (!_cancellation.isCompleted) _cancellation.complete();
    _workerCommands.send({'type': 'cancel'});
    _isolate.kill(priority: Isolate.immediate);
    _commands.close();
  }
}

class CatalogImportWorkerException implements Exception {
  const CatalogImportWorkerException({
    required this.errorType,
    required this.message,
    required this.workerStackTrace,
  });

  final String errorType;
  final String message;
  final String workerStackTrace;

  @override
  String toString() => '$errorType: $message';
}

class CatalogImportWorker {
  const CatalogImportWorker._();

  static const int batchSize = 1000;
  static const int maxParseSliceLength = 16 * 1024;
  static const Duration connectionTimeout = Duration(minutes: 5);
  static const Duration requestTimeout = Duration(minutes: 5);

  static Future<CatalogImportWorkerHandle> start({
    required String playlistId,
    required String playlistUrl,
    String? sourceUrl,
    required CatalogImportRowSelector selectRows,
    required CatalogImportRowsCallback onRows,
    void Function(CatalogImportHeaders headers)? onHeaders,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final messages = StreamIterator<Object?>(receivePort);
    final isolate =
        await Isolate.spawn<Map<String, Object?>>(_catalogImportWorkerEntry, {
          'replyTo': receivePort.sendPort,
          'playlistUrl': playlistUrl,
          'playlistId': playlistId,
          'sourceUrl': sourceUrl ?? playlistUrl,
          'batchSize': batchSize,
          'connectionTimeoutMs': connectionTimeout.inMilliseconds,
          'requestTimeoutMs': requestTimeout.inMilliseconds,
        });
    final completion = Completer<CatalogImportWorkerResult>();
    final ready = await messages.moveNext();
    if (!ready) {
      isolate.kill(priority: Isolate.immediate);
      receivePort.close();
      throw StateError('Import worker exited before startup.');
    }
    final first = messages.current! as Map<Object?, Object?>;
    if (first['type'] == 'error') {
      isolate.kill(priority: Isolate.immediate);
      receivePort.close();
      throw FormatException(first['error']?.toString() ?? 'Worker failed.');
    }
    if (first['type'] != 'ready') {
      isolate.kill(priority: Isolate.immediate);
      receivePort.close();
      throw StateError('Unexpected import worker startup message.');
    }
    final workerCommands = first['sendPort']! as SendPort;
    final handle = CatalogImportWorkerHandle._(
      done: completion.future,
      isolate: isolate,
      commands: receivePort,
      workerCommands: workerCommands,
    );
    unawaited(
      _consumeMessages(
        messages: messages,
        receivePort: receivePort,
        workerCommands: workerCommands,
        handle: handle,
        completion: completion,
        selectRows: selectRows,
        onRows: onRows,
        onHeaders: onHeaders,
        onProgress: onProgress,
      ),
    );
    return handle;
  }

  static Future<void> _consumeMessages({
    required StreamIterator<Object?> messages,
    required ReceivePort receivePort,
    required SendPort workerCommands,
    required CatalogImportWorkerHandle handle,
    required Completer<CatalogImportWorkerResult> completion,
    required CatalogImportRowSelector selectRows,
    required CatalogImportRowsCallback onRows,
    required void Function(CatalogImportHeaders headers)? onHeaders,
    required CatalogImportProgressCallback? onProgress,
  }) async {
    CatalogImportHeaders? headers;
    try {
      while (await messages.moveNext()) {
        if (handle._cancelled) throw const CatalogImportCancelledException();
        final message = messages.current! as Map<Object?, Object?>;
        switch (message['type']) {
          case 'headers':
            headers = CatalogImportHeaders(
              statusCode: message['statusCode']! as int,
              contentLength: message['contentLength'] as int?,
              etag: message['etag'] as String?,
              lastModified: message['lastModified'] as String?,
            );
            onHeaders?.call(headers);
          case 'progress':
            onProgress?.call(
              message['bytesReceived']! as int,
              message['totalBytes'] as int?,
              message['itemsParsed']! as int,
            );
          case 'keys':
            final batch = _decodeKeys(message);
            final selected = await Future.any<List<int>>([
              selectRows(batch),
              handle._cancellation.future.then<List<int>>(
                (_) => throw const CatalogImportCancelledException(),
              ),
            ]);
            if (selected.any(
              (index) => index < 0 || index >= batch.itemKeys.length,
            )) {
              throw RangeError(
                'Selected row index is outside the import batch.',
              );
            }
            workerCommands.send({
              'type': 'want',
              'batchNumber': batch.batchNumber,
              'indices': selected,
            });
          case 'rows':
            final batchNumber = message['batchNumber']! as int;
            final rowMessages = message['rows']! as List<Object?>;
            await onRows(
              batchNumber,
              rowMessages
                  .map(
                    (row) => CatalogImportRow.fromMessage(
                      row! as Map<Object?, Object?>,
                    ),
                  )
                  .toList(growable: false),
            );
            workerCommands.send({'type': 'ack', 'batchNumber': batchNumber});
          case 'done':
            if (headers == null) {
              throw StateError('Worker completed without response headers.');
            }
            completion.complete(
              CatalogImportWorkerResult(
                bytesReceived: message['bytesReceived']! as int,
                itemsParsed: message['itemsParsed']! as int,
                itemsRejected: message['itemsRejected']! as int,
                duplicateUrls: message['duplicateUrls']! as int,
                bodyHash: message['bodyHash']! as int,
                headers: headers,
              ),
            );
            handle._isolate.kill(priority: Isolate.immediate);
            receivePort.close();
            return;
          case 'error':
            final errorType = message['errorType']?.toString() ?? 'Error';
            final errorMessage =
                message['error']?.toString() ??
                'Playlist import worker failed.';
            if (errorType == 'FormatException') {
              throw FormatException(errorMessage);
            }
            throw CatalogImportWorkerException(
              errorType: errorType,
              message: errorMessage,
              workerStackTrace: message['stackTrace']?.toString() ?? '',
            );
          default:
            throw StateError(
              'Unexpected import worker message: ${message['type']}',
            );
        }
      }
      if (!handle._cancelled) {
        throw StateError('Import worker closed before completing.');
      }
      throw const CatalogImportCancelledException();
    } catch (error, stackTrace) {
      if (!completion.isCompleted) completion.completeError(error, stackTrace);
      handle._isolate.kill(priority: Isolate.immediate);
      receivePort.close();
    } finally {
      await messages.cancel();
    }
  }

  static CatalogImportBatchKeys _decodeKeys(Map<Object?, Object?> message) {
    final itemKeys = (message['itemKeys']! as TransferableTypedData)
        .materialize()
        .asUint8List();
    final contentHashes = (message['contentHashes']! as TransferableTypedData)
        .materialize()
        .asUint8List();
    final ordinals = (message['ordinals']! as TransferableTypedData)
        .materialize()
        .asUint8List();
    return CatalogImportBatchKeys(
      batchNumber: message['batchNumber']! as int,
      itemKeys: Int64List.view(itemKeys.buffer),
      contentHashes: Int64List.view(contentHashes.buffer),
      ordinals: Int32List.view(ordinals.buffer),
    );
  }
}

void _catalogImportWorkerEntry(Map<String, Object?> request) async {
  final replyTo = request['replyTo']! as SendPort;
  final commands = ReceivePort();
  final commandIterator = StreamIterator<Object?>(commands);
  final parser = M3uStreamingParser(sourceUrl: request['sourceUrl'] as String?);
  final batchSize = request['batchSize']! as int;
  final timeout = Duration(milliseconds: request['requestTimeoutMs']! as int);
  var bytesReceived = 0;
  var itemsParsed = 0;
  var itemsRejected = 0;
  var duplicateUrls = 0;
  final bodyHasher = Fnv64Hasher();
  final occurrences = _OccurrenceIndex();
  var batchNumber = 0;
  var batch = <CatalogImportRow>[];
  var cancelled = false;

  replyTo.send({'type': 'ready', 'sendPort': commands.sendPort});

  Future<List<int>> waitForIndices(int expectedBatchNumber) async {
    while (await commandIterator.moveNext()) {
      final command = commandIterator.current! as Map<Object?, Object?>;
      if (command['type'] == 'cancel') {
        cancelled = true;
        throw const CatalogImportCancelledException();
      }
      if (command['type'] != 'want' ||
          command['batchNumber'] != expectedBatchNumber) {
        continue;
      }
      return (command['indices']! as List<Object?>)
          .map((value) => value! as int)
          .toList(growable: false);
    }
    throw const CatalogImportCancelledException();
  }

  Future<void> waitForAck(int expectedBatchNumber) async {
    while (await commandIterator.moveNext()) {
      final command = commandIterator.current! as Map<Object?, Object?>;
      if (command['type'] == 'cancel') {
        cancelled = true;
        throw const CatalogImportCancelledException();
      }
      if (command['type'] == 'ack' &&
          command['batchNumber'] == expectedBatchNumber) {
        return;
      }
    }
    throw const CatalogImportCancelledException();
  }

  Future<void> sendBatch({int? limit}) async {
    if (batch.isEmpty) return;
    final sendCount = limit == null || limit > batch.length
        ? batch.length
        : limit;
    final sending = batch.sublist(0, sendCount);
    final currentBatchNumber = batchNumber++;
    final keys = Int64List(sending.length);
    final hashes = Int64List(sending.length);
    final ordinals = Int32List(sending.length);
    for (var index = 0; index < sending.length; index++) {
      keys[index] = sending[index].itemKey;
      hashes[index] = sending[index].contentHash;
      ordinals[index] = sending[index].ordinal;
    }
    replyTo.send({
      'type': 'keys',
      'batchNumber': currentBatchNumber,
      'itemKeys': TransferableTypedData.fromList([keys.buffer.asUint8List()]),
      'contentHashes': TransferableTypedData.fromList([
        hashes.buffer.asUint8List(),
      ]),
      'ordinals': TransferableTypedData.fromList([
        ordinals.buffer.asUint8List(),
      ]),
    });
    final indices = await waitForIndices(currentBatchNumber);
    replyTo.send({
      'type': 'rows',
      'batchNumber': currentBatchNumber,
      'rows': [for (final index in indices) sending[index].toMessage()],
    });
    await waitForAck(currentBatchNumber);
    batch = batch.sublist(sendCount);
  }

  void collectItem(ContentItem item) {
    itemsParsed++;
    final streamUri = Uri.tryParse(item.streamUrl);
    if (item.title.trim().isEmpty ||
        streamUri == null ||
        !streamUri.hasScheme) {
      itemsRejected++;
      return;
    }
    final occurrence = occurrences.next(item.streamUrl);
    if (occurrence > 0) duplicateUrls++;
    final classification = classifyCatalogItem(
      streamUrl: item.streamUrl,
      groupTitle: item.group,
      title: item.title,
      providerType: item.metadata['type'] ?? item.metadata['content-type'],
    );
    final canonicalGroup = CatalogNormalizer.canonicalGroup(item.group);
    final seriesTitle = classification.episodeMatch?.seriesTitle;
    batch.add(
      CatalogImportRow(
        itemKey: itemKey(
          item.streamUrl,
          title: item.title,
          duplicateOccurrence: occurrence,
        ),
        contentHash: contentItemHash(item, classification),
        ordinal: item.sourceIndex,
        itemKind: classification.itemKind,
        groupKind: classification.groupKind,
        groupTitle: canonicalGroup,
        title: item.title,
        streamUrl: item.streamUrl,
        logoUrl: item.logoUrl,
        metadata: item.metadata,
        seriesKey: seriesTitle == null
            ? null
            : seriesKey(
                playlistId: request['playlistId']! as String,
                groupKind: classification.groupKind,
                groupTitle: canonicalGroup,
                seriesTitle: seriesTitle,
              ),
        seriesTitle: seriesTitle,
        seasonNumber: classification.episodeMatch?.seasonNumber,
        episodeNumber: classification.episodeMatch?.episodeNumber,
      ),
    );
  }

  try {
    final client = HttpClient();
    try {
      final httpRequest = await client
          .getUrl(Uri.parse(request['playlistUrl']! as String))
          .timeout(
            Duration(milliseconds: request['connectionTimeoutMs']! as int),
          );
      httpRequest.headers.set(
        HttpHeaders.acceptHeader,
        'application/x-mpegURL, text/plain, */*',
      );
      httpRequest.headers.set(HttpHeaders.userAgentHeader, 'IPTV-Flutter/0.1');
      final response = await httpRequest.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Playlist request failed: ${response.statusCode}');
      }
      final totalBytes = response.contentLength >= 0
          ? response.contentLength
          : null;
      replyTo.send({
        'type': 'headers',
        'statusCode': response.statusCode,
        'contentLength': totalBytes,
        'etag': response.headers.value(HttpHeaders.etagHeader),
        'lastModified': response.headers.value(HttpHeaders.lastModifiedHeader),
      });

      await for (final text
          in response.transform(utf8.decoder).timeout(timeout)) {
        if (cancelled) throw const CatalogImportCancelledException();
        final encodedText = utf8.encode(text);
        bodyHasher.addBytes(encodedText);
        bytesReceived += encodedText.length;
        for (
          var offset = 0;
          offset < text.length;
          offset += CatalogImportWorker.maxParseSliceLength
        ) {
          final end = (offset + CatalogImportWorker.maxParseSliceLength).clamp(
            0,
            text.length,
          );
          parser.addChunk(text.substring(offset, end), collectItem);
          while (batch.length >= batchSize) {
            await sendBatch(limit: batchSize);
          }
        }
        replyTo.send({
          'type': 'progress',
          'bytesReceived': bytesReceived,
          'totalBytes': totalBytes,
          'itemsParsed': itemsParsed,
        });
      }
      parser.finish(collectItem);
      itemsRejected += parser.rejectedRecordCount;
      await sendBatch();
      replyTo.send({
        'type': 'done',
        'bytesReceived': bytesReceived,
        'itemsParsed': itemsParsed,
        'itemsRejected': itemsRejected,
        'duplicateUrls': duplicateUrls,
        'bodyHash': bodyHasher.value,
      });
    } finally {
      client.close(force: true);
    }
  } catch (error, stackTrace) {
    replyTo.send({
      'type': 'error',
      'errorType': error.runtimeType.toString(),
      'error': redactSensitiveText(error.toString()),
      'stackTrace': redactSensitiveText(stackTrace.toString()),
    });
  } finally {
    commands.close();
    await commandIterator.cancel();
  }
}

class _OccurrenceIndex {
  Int64List _hashes = Int64List(1024);
  Int32List _counts = Int32List(1024);
  int _size = 0;

  int next(String value) {
    final key = hash64(value);
    if ((_size + 1) * 10 >= _hashes.length * 7) _grow();
    var slot = key & (_hashes.length - 1);
    while (_counts[slot] != 0) {
      if (_hashes[slot] == key) {
        final occurrence = _counts[slot];
        _counts[slot] = occurrence + 1;
        return occurrence;
      }
      slot = (slot + 1) & (_hashes.length - 1);
    }
    _hashes[slot] = key;
    _counts[slot] = 1;
    _size++;
    return 0;
  }

  void _grow() {
    final oldHashes = _hashes;
    final oldCounts = _counts;
    _hashes = Int64List(oldHashes.length * 2);
    _counts = Int32List(oldCounts.length * 2);
    for (var index = 0; index < oldHashes.length; index++) {
      final count = oldCounts[index];
      if (count == 0) continue;
      var slot = oldHashes[index] & (_hashes.length - 1);
      while (_counts[slot] != 0) {
        slot = (slot + 1) & (_hashes.length - 1);
      }
      _hashes[slot] = oldHashes[index];
      _counts[slot] = count;
    }
  }
}
