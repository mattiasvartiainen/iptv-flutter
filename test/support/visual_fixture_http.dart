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
final _portraitBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAABACAYAAAB7jnWuAAAAQElEQVR4nO3O'
  'IQEAAAgDMJI8McFoBTEwE/Or9OynEhAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ'
  'EBAQEBAQEMhz4AAYyIkeu4VbawAAAABJRU5ErkJggg==',
);
final _landscapeBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAYAAACinX6EAAAAXklEQVR4nO3Q'
  'MQ0AIADAMJSgGGG4AhklYcf+ZmOufX5uaICuARqga4AG6BqgAboGaICuARqg'
  'a4AG6BqgAboGaICuARqga4AG6BqgAboGaICuARqga4AG6BowH0DIAReGUYke'
  'RXyw+gAAAABJRU5ErkJggg==',
);

void installVisualFixtureHttp({Map<String, Uint8List> extraImages = const {}}) {
  debugNetworkImageHttpClientProvider = () => _FixtureClient(extraImages);
}

void uninstallVisualFixtureHttp() {
  debugNetworkImageHttpClientProvider = null;
}

class _FixtureClient implements HttpClient {
  _FixtureClient(this.extraImages);

  final Map<String, Uint8List> extraImages;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (url.host != 'example.invalid') {
      throw StateError('Unexpected visual fixture image host.');
    }
    final bytes =
        extraImages[url.path] ??
        switch (url.path) {
          '/missing.png' => null,
          '/portrait.png' => _portraitBytes,
          '/landscape.png' => _landscapeBytes,
          _ => _imageBytes,
        };
    return _FixtureRequest(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureRequest implements HttpClientRequest {
  _FixtureRequest(this.bytes);

  final Uint8List? bytes;

  @override
  Future<HttpClientResponse> close() async => _FixtureResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureResponse extends Stream<List<int>> implements HttpClientResponse {
  _FixtureResponse(this.bytes);

  final Uint8List? bytes;

  @override
  int get statusCode => bytes == null ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => bytes?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<Uint8List>.value(bytes ?? Uint8List(0)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
