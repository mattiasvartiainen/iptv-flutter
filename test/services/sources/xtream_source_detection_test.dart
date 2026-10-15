import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/xtream_source_detection.dart';

void main() {
  test('detects a candidate without promoting or rewriting its input', () {
    const input =
        'http://provider.example:8080/panel/get.php?username=Demo&password=Secret&type=m3u_plus&output=ts&token=keep';
    final candidate = detectXtreamSourceUrl(input)!;
    expect(candidate.originalUrl, input);
    expect(
      candidate.apiEndpoint.toString(),
      'http://provider.example:8080/panel/player_api.php',
    );
    expect(candidate.username, 'Demo');
    expect(candidate.password, 'Secret');
    expect(candidate.requiresEndpointConfirmation, isFalse);
    final summary = SourceConnectionSummary(
      playlistId: 'local-id',
      inputKind: PlaylistSourceKind.url,
    );
    expect(summary.verification, SourceVerificationState.unchecked);
    expect(summary.catalogMode, CatalogSourceMode.m3u);
    expect(summary.accountState, SourceAccountState.unknown);
    expect(
      summary.capability(SourceCapability.vodInfo),
      SourceCapabilityState.unknown,
    );
  });

  test(
    'query decoding preserves credential case and significant whitespace',
    () {
      final uri = Uri.https('provider.example', '/player_api.php', {
        'username': ' User+&/ ',
        'password': ' Pass+&/?#% word ',
        'action': 'get_live_streams',
      });
      final candidate = detectXtreamSourceUrl(uri.toString())!;
      expect(candidate.username, ' User+&/ ');
      expect(candidate.password, ' Pass+&/?#% word ');
      expect(candidate.apiEndpoint.hasQuery, isFalse);
    },
  );

  test('unknown script endpoints require confirmation, never verification', () {
    final candidate = detectXtreamSourceUrl(
      'https://provider.example/custom/list.php?username=u&password=p',
    )!;
    expect(candidate.requiresEndpointConfirmation, isTrue);
    expect(candidate.apiEndpoint.path, '/custom/player_api.php');
    final otherScript = detectXtreamSourceUrl(
      'https://provider.example/custom/list.cgi?username=u&password=p',
    )!;
    expect(otherScript.requiresEndpointConfirmation, isTrue);
    expect(otherScript.apiEndpoint.path, '/custom/player_api.php');
  });

  for (final input in [
    'https://provider.example/get.php',
    'https://provider.example/get.php?username=u',
    'https://provider.example/get.php?username=&password=p',
    'https://provider.example/get.php?username=u&password=',
    'https://provider.example/get.php?username=u&username=v&password=p',
    'https://provider.example/get.php?username=u&password=p&password=q',
    'https://provider.example/live/u/p/42.ts',
    'https://provider.example/u/p/42?username=u&password=p',
    'https://provider.example/video.mp4?username=u&password=p',
    'ftp://provider.example/get.php?username=u&password=p',
    'https://u:p@provider.example/get.php?username=u&password=p',
    'https://provider.example/get.php?username=u&password=p#fragment',
    'https://provider.example:99999/get.php?username=u&password=p',
    'https://provider.example/a%2Fb/get.php?username=u&password=p',
    'https://provider.example/get.php?username=%FF&password=p',
    'https://provider.example/get.php?username=u&password=%ZZ',
    'https://provider.example/get.php?username=u&password=p&username=u',
    'https://provider.example:0/get.php?username=u&password=p',
    'https://provider.example/%00/get.php?username=u&password=p',
    'https://provider.example/a%5Cb/get.php?username=u&password=p',
    'not a URL',
  ]) {
    test(
      'rejects invalid, ambiguous or non-playlist input ${input.hashCode}',
      () {
        expect(detectXtreamSourceUrl(input), isNull);
      },
    );
  }

  test('server parser preserves IPv6 port and encoded base path', () {
    final address = parseXtreamServerAddress('http://[::1]:8080/a%20b/')!;
    expect(address.baseUri.toString(), 'http://[::1]:8080/a%20b/');
    expect(address.requiresSchemeConfirmation, isFalse);
    final candidate = detectXtreamSourceUrl(
      'https://[::1]:8443/a%20b/get.php?username=u&password=p',
    )!;
    expect(
      candidate.apiEndpoint.toString(),
      'https://[::1]:8443/a%20b/player_api.php',
    );
  });

  test('bare server suggests HTTPS but requires confirmation', () {
    final address = parseXtreamServerAddress('provider.example:8080/panel')!;
    expect(address.baseUri.scheme, 'https');
    expect(address.baseUri.port, 8080);
    expect(address.requiresSchemeConfirmation, isTrue);
    for (final invalid in [
      '',
      'ftp://provider.example',
      'https://u:p@provider.example',
      'https://provider.example?token=p',
      'https://provider.example#fragment',
    ]) {
      expect(parseXtreamServerAddress(invalid), isNull);
    }
  });

  test('safe summary copies capabilities and validates revision', () {
    final capabilities = {
      SourceCapability.liveCatalog: SourceCapabilityState.supported,
    };
    final summary = SourceConnectionSummary(
      playlistId: 'p',
      inputKind: PlaylistSourceKind.xtream,
      capabilities: capabilities,
    );
    capabilities.clear();
    expect(
      summary.capability(SourceCapability.liveCatalog),
      SourceCapabilityState.supported,
    );
    expect(() => summary.capabilities.clear(), throwsUnsupportedError);
    expect(
      () => SourceConnectionSummary(
        playlistId: 'p',
        inputKind: PlaylistSourceKind.url,
        connectionRevision: -1,
      ),
      throwsArgumentError,
    );
    expect(summary.toString(), isNot(contains('password')));
  });

  test('legacy source JSON and raw URLs remain compatible', () {
    const url =
        'https://provider.example/get.php?username=u&password=p&output=ts';
    final legacy = PlaylistSourceConfig.fromStorageValue(
      url,
      fallbackName: 'Legacy',
    )!;
    expect(legacy.kind, PlaylistSourceKind.url);
    expect(legacy.resolvedUrl, url);
    expect(legacy.name, 'Legacy');
    final restored = PlaylistSourceConfig.fromStorageValue(
      legacy.toStorageValue(),
    )!;
    expect(restored.toJson(), legacy.toJson());
    expect(detectXtreamSourceUrl(url)!.originalUrl, legacy.resolvedUrl);
    expect(PlaylistSourceKind.values.map((kind) => kind.name), [
      'url',
      'xtream',
    ]);
    const explicit = PlaylistSourceConfig.xtream(
      playlistId: 'existing-id',
      name: 'Account',
      server: 'https://provider.example',
      username: 'demo',
      password: 'secret',
    );
    expect(explicit.playlistId, 'existing-id');
    expect(
      explicit.resolvedUrl,
      'https://provider.example/get.php?username=demo&password=secret&type=m3u_plus&output=m3u8',
    );
    expect(
      PlaylistSourceConfig.fromStorageValue(
        explicit.toStorageValue(),
      )!.toJson(),
      explicit.toJson(),
    );
  });

  test('explicit source round trip and resolution preserve exact password', () {
    const config = PlaylistSourceConfig.xtream(
      name: 'Account',
      server: 'https://provider.example',
      username: ' demo ',
      password: ' Pass+&/% ',
    );
    final restored = PlaylistSourceConfig.fromStorageValue(
      config.toStorageValue(),
    )!;
    expect(restored.password, config.password);
    expect(
      Uri.parse(restored.resolvedUrl).queryParameters['password'],
      config.password,
    );
    expect(Uri.parse(restored.resolvedUrl).queryParameters['username'], 'demo');
  });
}
