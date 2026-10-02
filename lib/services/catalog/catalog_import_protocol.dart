import 'dart:typed_data';

import 'catalog_query.dart';

class CatalogImportBatchKeys {
  const CatalogImportBatchKeys({
    required this.batchNumber,
    required this.itemKeys,
    required this.contentHashes,
    required this.ordinals,
  });

  final int batchNumber;
  final Int64List itemKeys;
  final Int64List contentHashes;
  final Int32List ordinals;
}

class CatalogImportRow {
  const CatalogImportRow({
    required this.itemKey,
    required this.contentHash,
    required this.ordinal,
    required this.itemKind,
    required this.groupKind,
    required this.groupTitle,
    required this.title,
    required this.streamUrl,
    this.logoUrl,
    this.metadata = const {},
    this.seriesKey,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
  });

  final int itemKey;
  final int contentHash;
  final int ordinal;
  final CatalogItemKind itemKind;
  final CatalogGroupKind groupKind;
  final String groupTitle;
  final String title;
  final String streamUrl;
  final String? logoUrl;
  final Map<String, String> metadata;
  final int? seriesKey;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;

  Map<String, Object?> toMessage() => {
    'itemKey': itemKey,
    'contentHash': contentHash,
    'ordinal': ordinal,
    'itemKind': itemKind.name,
    'groupKind': groupKind.name,
    'groupTitle': groupTitle,
    'title': title,
    'streamUrl': streamUrl,
    'logoUrl': logoUrl,
    'metadata': metadata,
    'seriesKey': seriesKey,
    'seriesTitle': seriesTitle,
    'seasonNumber': seasonNumber,
    'episodeNumber': episodeNumber,
  };

  static CatalogImportRow fromMessage(Map<Object?, Object?> row) =>
      CatalogImportRow(
        itemKey: row['itemKey']! as int,
        contentHash: row['contentHash']! as int,
        ordinal: row['ordinal']! as int,
        itemKind: CatalogItemKind.values.byName(row['itemKind']! as String),
        groupKind: CatalogGroupKind.values.byName(row['groupKind']! as String),
        groupTitle: row['groupTitle']! as String,
        title: row['title']! as String,
        streamUrl: row['streamUrl']! as String,
        logoUrl: row['logoUrl'] as String?,
        metadata: Map<String, String>.from(row['metadata']! as Map),
        seriesKey: row['seriesKey'] as int?,
        seriesTitle: row['seriesTitle'] as String?,
        seasonNumber: row['seasonNumber'] as int?,
        episodeNumber: row['episodeNumber'] as int?,
      );
}

class CatalogImportHeaders {
  const CatalogImportHeaders({
    required this.statusCode,
    required this.contentLength,
    this.etag,
    this.lastModified,
  });

  final int statusCode;
  final int? contentLength;
  final String? etag;
  final String? lastModified;
}

class CatalogImportWorkerResult {
  const CatalogImportWorkerResult({
    required this.bytesReceived,
    required this.itemsParsed,
    required this.itemsRejected,
    required this.duplicateUrls,
    required this.bodyHash,
    required this.headers,
  });

  final int bytesReceived;
  final int itemsParsed;
  final int itemsRejected;
  final int duplicateUrls;
  final int bodyHash;
  final CatalogImportHeaders headers;
}

class CatalogImportCancelledException implements Exception {
  const CatalogImportCancelledException();

  @override
  String toString() => 'Playlist import cancelled.';
}

typedef CatalogImportRowSelector =
    Future<List<int>> Function(CatalogImportBatchKeys batch);

typedef CatalogImportRowsCallback =
    Future<void> Function(int batchNumber, List<CatalogImportRow> rows);

typedef CatalogImportProgressCallback =
    void Function(int bytesReceived, int? totalBytes, int itemsParsed);
