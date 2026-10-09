import 'dart:async';
import 'dart:io';

class CatalogHttpTestServer {
  CatalogHttpTestServer._(this._server, this.responses, this.beforeResponse);

  static Future<CatalogHttpTestServer> start({
    required Map<String, String> responses,
    Future<void>? beforeResponse,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = CatalogHttpTestServer._(server, responses, beforeResponse);
    server.listen((request) async {
      fixture.requestCount++;
      if (!fixture.firstRequest.isCompleted) {
        fixture.firstRequest.complete();
      }
      await fixture.beforeResponse;
      final body = fixture.responses[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType.text;
        request.response.write(body);
      }
      await request.response.close();
    });
    return fixture;
  }

  final HttpServer _server;
  final Map<String, String> responses;
  final Future<void>? beforeResponse;
  final Completer<void> firstRequest = Completer<void>();
  int requestCount = 0;

  String url(String path) =>
      'http://${_server.address.address}:${_server.port}$path';

  Future<void> close() => _server.close(force: true);
}
