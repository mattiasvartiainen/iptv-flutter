import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/security/url_redaction.dart';

void main() {
  test('redacts Xtream credentials from stream path segments', () {
    expect(
      redactUrl('http://provider.test:8080/live/user123/pass456/12345.ts'),
      'http://provider.test:8080/live/%5Bredacted%5D/%5Bredacted%5D/12345.ts',
    );
  });

  test('redacts URL user-info and all query values', () {
    expect(
      redactUrl(
        'https://user:pass@provider.test/get.php?username=u&password=p',
      ),
      'https://provider.test/get.php?username=%5Bredacted%5D&password=%5Bredacted%5D',
    );
  });

  test('redacts URLs embedded in exception text', () {
    expect(
      redactSensitiveText(
        'Request failed for http://provider.test/movie/alice/secret/45.mp4',
      ),
      'Request failed for http://provider.test/movie/%5Bredacted%5D/%5Bredacted%5D/45.mp4',
    );
  });

  test('does not change a public URL without credential fields', () {
    expect(
      redactUrl('https://cdn.test/live/channel.m3u8'),
      'https://cdn.test/live/channel.m3u8',
    );
  });
}
