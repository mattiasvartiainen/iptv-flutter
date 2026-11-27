import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

final _imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAW0lEQVR4nO3U'
  'oQ0AIAxE0Y7DYGhm6qYQUtEUNDnBFzVF3An6rPmYZfoxj99NGb53pgzPAqLw'
  'KCAMvwsIPmQWEF1DFBCeYj1DHMABHMABHMABHMABHMABHPAPHVjg/Fx5xYCP'
  'OAAAAABJRU5ErkJggg==',
);

void installVisualFixtureHttp() {
  debugNetworkImageHttpClientProvider = () => _FixtureClient();
}

void uninstallVisualFixtureHttp() {
  debugNetworkImageHttpClientProvider = null;
}

class _FixtureClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (url.host != 'example.invalid') {
      throw StateError('Unexpected visual fixture image host.');
    }
    return _FixtureRequest(url.path == '/missing.png');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureRequest implements HttpClientRequest {
  _FixtureRequest(this.missing);

  final bool missing;

  @override
  Future<HttpClientResponse> close() async => _FixtureResponse(missing);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureResponse extends Stream<List<int>> implements HttpClientResponse {
  _FixtureResponse(this.missing);

  final bool missing;

  @override
  int get statusCode => missing ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => missing ? 0 : _imageBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<Uint8List>.value(missing ? Uint8List(0) : _imageBytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
