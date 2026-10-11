import '../security/url_redaction.dart';

const Duration catalogHttpConnectionTimeout = Duration(minutes: 5);
const Duration catalogHttpRequestTimeout = Duration(minutes: 5);
const String catalogHttpAcceptHeader = 'application/x-mpegURL, text/plain, */*';
const String catalogHttpUserAgent = 'IPTV-Flutter/0.1';

String catalogHttpFailureMessage({
  required int statusCode,
  required String url,
}) => 'Playlist request failed: $statusCode (${redactUrl(url)})';
