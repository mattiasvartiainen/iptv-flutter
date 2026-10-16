import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/storage/secure_storage_service.dart';

class WindowsPlaylistSecretStore implements PlaylistSecretStore {
  WindowsPlaylistSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _physicalKey(String key) =>
      'playlist-v1-${sha256.convert(utf8.encode(key))}';

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: _physicalKey(key), value: value);

  @override
  Future<String?> read({required String key}) async =>
      await _storage.read(key: _physicalKey(key)) ??
      await _storage.read(key: key);

  @override
  Future<void> delete({required String key}) async {
    for (final candidate in [_physicalKey(key), key]) {
      if (await _storage.containsKey(key: candidate)) {
        await _storage.delete(key: candidate);
      }
    }
  }
}
