import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';

void main() {
  test(
    'authenticates without returning account credentials or server override',
    () async {
      final transport = _Transport({
        'user_info': {
          'auth': '1',
          'status': 'Active',
          'username': 'echo',
          'password': 'echo',
          'allowed_output_formats': ['ts', 'm3u8', 'evil'],
        },
        'server_info': {'url': 'other.example'},
      });
      final client = XtreamApiClient(
        resolveCredentials: (_, _) async => _credentials,
        createTransport: () => transport,
      );
      final result = await client.authenticate(
        playlistId: 'p',
        connectionRevision: 1,
      );
      expect(result.verification, SourceVerificationState.verified);
      expect(result.accountState, SourceAccountState.active);
      expect(result.allowedOutputFormats, ['ts', 'm3u8']);
      expect(transport.uri!.host, 'provider.example');
      expect(transport.uri!.queryParameters, {
        'username': 'user +',
        'password': ' pass& ',
      });
      expect(transport.closed, isTrue);
    },
  );
}

final _credentials = XtreamCredentials(
  endpoint: Uri.parse('https://provider.example/panel/player_api.php'),
  username: 'user +',
  password: ' pass& ',
  confirmed: true,
);

class _Transport implements XtreamAuthTransport {
  _Transport(this.payload);
  final Object payload;
  Uri? uri;
  bool closed = false;
  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    uri = authenticatedUri;
    return XtreamAuthResponse(
      statusCode: 200,
      body: Stream.value(utf8.encode(jsonEncode(payload))),
    );
  }

  @override
  void close() {
    closed = true;
  }
}
