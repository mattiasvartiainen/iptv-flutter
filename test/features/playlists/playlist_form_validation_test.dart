import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/playlists/playlist_form_validation.dart';

void main() {
  test('playlist name must not be empty or whitespace', () {
    expect(validatePlaylistName(null), 'Enter a playlist name.');
    expect(validatePlaylistName('  '), 'Enter a playlist name.');
    expect(validatePlaylistName('News'), isNull);
  });

  test('playlist URL requires a URI with a scheme', () {
    expect(validatePlaylistUrl(null), 'Enter a valid playlist URL.');
    expect(validatePlaylistUrl('provider/list.m3u'), isNotNull);
    expect(validatePlaylistUrl('https://provider.test/list.m3u'), isNull);
  });

  test('Xtream server, username, and password are required', () {
    expect(validateXtreamServer(' '), 'Enter the server URL.');
    expect(validateXtreamServer('https://provider.test'), isNull);
    expect(validateXtreamUsername(' '), 'Enter the username.');
    expect(validateXtreamUsername('viewer'), isNull);
    expect(validateXtreamPassword(''), 'Enter the password.');
    expect(validateXtreamPassword('secret'), isNull);
  });
}
