import 'dart:async';
import 'dart:io';

Map<String, Object> networkFailureDiagnostics(Object error) {
  if (error is SocketException) {
    final message = '${error.message} ${error.osError?.message}'.toLowerCase();
    return {
      'exception.message': switch (message) {
        _ when message.contains('host lookup') => 'DNS lookup failed.',
        _ when message.contains('refused') => 'Connection refused.',
        _ when message.contains('reset') => 'Connection reset by peer.',
        _ when message.contains('timed out') => 'Connection timed out.',
        _ when message.contains('unreachable') => 'Network is unreachable.',
        _ when message.contains('no route') => 'No route to the server.',
        _ => 'A network socket operation failed.',
      },
      if (error.osError != null)
        'exception.os_error_code': error.osError!.errorCode,
    };
  }
  if (error is TlsException) {
    final text = '${error.message} ${error.osError?.message}';
    const reasons = [
      'CERTIFICATE_VERIFY_FAILED',
      'CERTIFICATE_HAS_EXPIRED',
      'WRONG_VERSION_NUMBER',
      'TLSV1_ALERT_PROTOCOL_VERSION',
      'TLSV1_ALERT_HANDSHAKE_FAILURE',
      'SSLV3_ALERT_HANDSHAKE_FAILURE',
      'NO_SHARED_CIPHER',
      'unable to get local issuer certificate',
      'unable to verify the first certificate',
      'certificate has expired',
      'self signed certificate',
      'hostname mismatch',
    ];
    return {
      'exception.message': 'TLS negotiation failed.',
      if (error.osError != null)
        'exception.os_error_code': error.osError!.errorCode,
      if (reasons.any(text.contains))
        'tls.failure_reason': reasons.where(text.contains).join(', '),
    };
  }
  if (error is TimeoutException) {
    return {
      'exception.message': 'The network operation timed out.',
      if (error.duration != null)
        'exception.timeout_ms': error.duration!.inMilliseconds,
    };
  }
  if (error is HttpException) {
    final message = error.message.toLowerCase();
    return {
      'exception.message': switch (message) {
        _ when error is RedirectException => 'HTTP redirect failed.',
        _ when message.contains('connection closed') =>
          'The server closed the connection before the response completed.',
        _ => 'The HTTP request failed.',
      },
    };
  }
  return const {};
}
