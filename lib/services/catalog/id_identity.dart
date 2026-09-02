import 'dart:convert';

import 'package:crypto/crypto.dart';

String strongStableId(String namespace, String value) {
  final digest = sha256.convert(utf8.encode('$namespace|$value'));
  return '$namespace-${digest.toString()}';
}

String legacyStableId(String namespace, String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = 0x1fffffff & (hash + codeUnit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash ^= hash >> 11;
  hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  return '$namespace-${hash.toRadixString(16)}';
}
