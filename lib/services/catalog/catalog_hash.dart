import 'dart:convert';

import '../../models/content_item.dart';
import 'catalog_classifier.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';

const int _wordMask = 0xffffffff;
final BigInt _twoTo63 = BigInt.from(1) << 63;
final BigInt _twoTo64 = BigInt.from(1) << 64;

/// Incremental FNV-1a hash represented as a signed SQLite int.
///
/// Two 32-bit words avoid platform-specific overflow behavior.
class Fnv64Hasher {
  int _high = 0xcbf29ce4;
  int _low = 0x84222325;

  void addBytes(Iterable<int> bytes) {
    for (final byte in bytes) {
      _low = (_low ^ byte) & _wordMask;
      final product = _low * 0x1b3;
      final nextLow = product & _wordMask;
      final carry = product ~/ 0x100000000;
      _high = (_high * 0x1b3 + _low * 0x100 + carry) & _wordMask;
      _low = nextLow;
    }
  }

  int get value {
    final unsigned = (BigInt.from(_high) << 32) | BigInt.from(_low);
    return (unsigned >= _twoTo63 ? unsigned - _twoTo64 : unsigned).toInt();
  }
}

/// Stable 64-bit FNV-1a hash of UTF-8 text, represented as a signed SQLite int.
int hash64(String value) {
  final hasher = Fnv64Hasher()..addBytes(utf8.encode(value));
  return hasher.value;
}

/// Stable identity for an item. [duplicateOccurrence] is zero for the first
/// occurrence; later occurrences are disambiguated using title and ordinal.
int itemKey(String streamUrl, {String? title, int duplicateOccurrence = 0}) {
  if (duplicateOccurrence <= 0) return hash64(streamUrl);
  return hash64('$streamUrl\u0000${title ?? ''}\u0000$duplicateOccurrence');
}

/// Hashes ordered, typed fields. Nulls, integers and strings cannot alias each
/// other, and field boundaries are encoded before each UTF-8 payload.
int contentHash(Iterable<Object?> fields) {
  final hasher = Fnv64Hasher();

  for (final field in fields) {
    final type = switch (field) {
      null => 'n',
      int _ => 'i',
      bool _ => 'b',
      num _ => 'd',
      _ => 's',
    };
    final encoded = utf8.encode(field?.toString() ?? '');
    hasher.addBytes([type.codeUnitAt(0)]);
    final length = encoded.length;
    hasher.addBytes([
      (length >> 24) & 0xff,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
      ...encoded,
    ]);
  }
  return hasher.value;
}

int contentItemHash(ContentItem item, CatalogClassification classification) =>
    contentHash([
      classification.itemKind.name,
      classification.groupKind.name,
      CatalogNormalizer.canonicalGroup(item.group),
      item.title,
      item.streamUrl,
      item.logoUrl,
      item.metadata['tvg-id'],
      item.metadata['tvg-name'],
      item.metadata['tvg-chno'],
      item.metadata['xui-id'],
      classification.episodeMatch?.seriesTitle,
      classification.episodeMatch?.seasonNumber,
      classification.episodeMatch?.episodeNumber,
    ]);

int seriesKey({
  required String playlistId,
  required CatalogGroupKind groupKind,
  required String groupTitle,
  required String seriesTitle,
}) => hash64(
  '$playlistId\u0000${groupKind.name}\u0000$groupTitle\u0000$seriesTitle',
);
