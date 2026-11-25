import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/errors/network_failure_diagnostics.dart';

void main() {
  test(
    'reports socket reason and OS code without arbitrary exception data',
    () {
      final details = networkFailureDiagnostics(
        const SocketException(
          'Connection refused https://private.test/get.php?password=secret',
          osError: OSError('secret OS message', 111),
        ),
      );

      expect(details['exception.message'], 'Connection refused.');
      expect(details['exception.os_error_code'], 111);
      expect(jsonEncode(details), isNot(contains('secret')));
      expect(jsonEncode(details), isNot(contains('private.test')));
    },
  );

  test('retains a known TLS reason, but no raw TLS message', () {
    final details = networkFailureDiagnostics(
      const HandshakeException(
        'Handshake error with secret credentials',
        OSError('CERTIFICATE_VERIFY_FAILED: secret certificate subject', -1),
      ),
    );

    expect(details['exception.message'], 'TLS negotiation failed.');
    expect(details['tls.failure_reason'], 'CERTIFICATE_VERIFY_FAILED');
    expect(details['exception.os_error_code'], -1);
    expect(jsonEncode(details), isNot(contains('secret')));
  });

  test('reports DNS lookup failures without the hostname', () {
    final details = networkFailureDiagnostics(
      const SocketException('Failed host lookup: private.test'),
    );
    expect(details['exception.message'], 'DNS lookup failed.');
    expect(jsonEncode(details), isNot(contains('private.test')));
  });

  test('distinguishes a missing TLS issuer from other certificate failures', () {
    final details = networkFailureDiagnostics(
      const HandshakeException(
        'Handshake error',
        OSError(
          'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate: '
          'secret certificate subject',
          -1,
        ),
      ),
    );
    expect(
      details['tls.failure_reason'],
      'CERTIFICATE_VERIFY_FAILED, unable to get local issuer certificate',
    );
    expect(jsonEncode(details), isNot(contains('secret')));
  });

  test('recognizes socket reasons supplied only by the operating system', () {
    final details = networkFailureDiagnostics(
      const SocketException(
        'Connection failed',
        osError: OSError('Connection refused', 111),
      ),
    );
    expect(details['exception.message'], 'Connection refused.');
  });

  test('reports timeout duration but not the original message', () {
    final details = networkFailureDiagnostics(
      TimeoutException('secret', const Duration(seconds: 30)),
    );
    expect(details['exception.timeout_ms'], 30000);
    expect(jsonEncode(details), isNot(contains('secret')));
  });

  test('does not export SQL, format input, or arbitrary HTTP messages', () {
    for (final error in [
      StateError('SELECT password FROM secrets'),
      const FormatException('secret playlist body'),
    ]) {
      expect(networkFailureDiagnostics(error), isEmpty);
    }
    expect(
      networkFailureDiagnostics(const HttpException('secret server response')),
      {'exception.message': 'The HTTP request failed.'},
    );
  });
}
