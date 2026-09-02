import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class PlaylistSecretStore {
  Future<void> write({required String key, required String value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

class FlutterSecurePlaylistSecretStore implements PlaylistSecretStore {
  FlutterSecurePlaylistSecretStore({Directory? baseDirectory})
    : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;

  Future<Directory> _directory() async {
    final directory = _baseDirectory ?? await getApplicationSupportDirectory();
    final secureDirectory = Directory(p.join(directory.path, 'secure-store'));
    if (!await secureDirectory.exists()) {
      await secureDirectory.create(recursive: true);
    }
    return secureDirectory;
  }

  Future<File> _fileFor(String key) async {
    final directory = await _directory();
    final safeName = base64Url.encode(utf8.encode(key));
    return File(p.join(directory.path, '$safeName.json'));
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final file = await _fileFor(key);
    final payload = jsonEncode(<String, String>{'value': value});
    await file.writeAsString(payload, flush: true);
  }

  @override
  Future<String?> read({required String key}) async {
    final file = await _fileFor(key);
    if (!await file.exists()) return null;
    final contents = await file.readAsString();
    final decoded = jsonDecode(contents);
    if (decoded is Map<String, dynamic>) {
      return decoded['value'] as String?;
    }
    return null;
  }

  @override
  Future<void> delete({required String key}) async {
    final file = await _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class InMemoryPlaylistSecretStore implements PlaylistSecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
