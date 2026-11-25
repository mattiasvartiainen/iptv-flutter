import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/metadata/series_metadata.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';
import 'package:iptv_flutter/services/xtream/xtream_movie_metadata_provider.dart';
import 'package:iptv_flutter/services/xtream/xtream_series_metadata.dart';

final credentials = XtreamCredentials(
  endpoint: Uri.parse('https://provider.test/base/player_api.php'),
  username: 'fixture-account',
  password: 'fixture-password',
  confirmed: true,
);

XtreamSeriesResponse decode(Object value, {
  String action = 'get_series_info',
  Set<String> ids = const {'42'},
}) => decodeXtreamSeries(XtreamSeriesRequest(
  bytes: utf8.encode(jsonEncode(value)), action: action, credentials: credentials,
  title: 'Fixture Show', group: 'Series', seriesId: '7', episodeIds: ids,
));

Map<String, Object?> payload() => {
  'info': {
    'name': 'Fixture Show', 'plot': 'A show synopsis.',
    'cover': 'https://images.test/poster.jpg',
    'backdrop_path': ['https://images.test/backdrop.jpg'],
    'releaseDate': '2020-01-01',
    'genre': 'Drama', 'rating': '8.5', 'duration': '00:45:00',
  },
  'episodes': {
    '0': [{'id': '42', 'season': 0, 'episode_num': 0}],
    '2': [{'id': '43', 'season': 2, 'episode_num': 1}],
  },
};

void main() {
  test('verified show maps public artwork/facts and preserves specials', () {
    final result = decode(payload(), ids: {'42', '43'}).result!;
    expect(result.providerSeriesId, '7');
    expect(result.metadata![ContentMetadataField.plot], 'A show synopsis.');
    expect(result.metadata![ContentMetadataField.poster], 'https://images.test/poster.jpg');
    expect(result.metadata![ContentMetadataField.backdrop], 'https://images.test/backdrop.jpg');
    expect(result.metadata![ContentMetadataField.releaseDate], '2020-01-01');
    expect(result.metadata![ContentMetadataField.runtime], isNull);
  });
  test('title alone and unrelated episode membership never validate a show', () {
    expect(decode(payload(), ids: {}).failure, MetadataFailure.unmapped);
    expect(decode(payload(), ids: {'99'}).failure, MetadataFailure.unmapped);
    final wrong = payload()..['info'] = {'name': 'Another Show'};
    expect(decode(wrong).failure, MetadataFailure.unmapped);
  });
  test('contradictory IDs, duplicate episodes and invalid numbering rejected', () {
    final wrong = payload()..['series_id'] = 8;
    expect(decode(wrong).failure, MetadataFailure.malformed);
    for (final episodes in [
      {'1': [{'id': '42', 'season': 2, 'episode_num': 1}]},
      {'1': [{'id': '42', 'episode_num': -1}]},
      {'1': [{'id': '42', 'episode_num': 1}, {'id': '42', 'episode_num': 2}]},
    ]) {
      expect(decode(payload()..['episodes'] = episodes).failure, MetadataFailure.malformed);
    }
  });
  test('bounded exact candidates retain ambiguity rather than first result', () {
    expect(decode([
      {'series_id': '7', 'name': ' Fixture  Show '},
      {'series_id': '8', 'name': 'fixture show'},
      {'series_id': '0', 'name': 'Fixture Show'},
      {'series_id': '9', 'name': 'Different'},
    ], action: 'get_series').ids, ['7', '8']);
    expect(decode(List.generate(11, (index) =>
      {'series_id': index + 1, 'name': 'Fixture Show'}), action: 'get_series').failure,
      MetadataFailure.unmapped);
    expect(decode([
      {'category_id': '3', 'category_name': 'Series'},
      {'category_id': '4', 'category_name': 'Movies'},
    ], action: 'get_series_categories').ids, ['3']);
  });
  test('denial and malformed responses remain explicit', () {
    expect(decode({'user_info': {'auth': 0}}).failure, MetadataFailure.denied);
    expect(decode([]).failure, MetadataFailure.malformed);
    expect(decode({}, action: 'get_series').failure, MetadataFailure.malformed);
    expect(decode(payload()..['episodes'] = {'invalid': []}).failure, MetadataFailure.malformed);
    expect(decode(payload()..['info'] = {'name': 'Fixture Show'}).result!.metadata!.fields,
      {ContentMetadataField.title: 'Fixture Show'});
  });
  test('descriptive fields cannot leak provider credentials', () {
    final value = payload()..['info'] = {
      'name': 'Fixture Show',
      'plot': 'fixture-account fixture-password https://host.test/series/u/p/42',
      'cover': 'https://host.test/fixture-password.jpg',
      'backdrop_path': ['https://host.test/image?password=fixture-password'],
    };
    final result = decode(value).result!.metadata!;
    expect(result[ContentMetadataField.plot], isNot(contains('fixture-password')));
    expect(result[ContentMetadataField.plot], isNot(contains('fixture-account')));
    expect(result[ContentMetadataField.poster], isNull);
    expect(result[ContentMetadataField.backdrop], isNull);
  });
  test('episode identity requires exact configured origin, base and account', () {
    const valid = 'https://provider.test/base/series/fixture-account/fixture-password/42.mkv';
    expect(xtreamStreamId(valid, credentials, kind: 'series'), '42');
    for (final url in [
      valid.replaceFirst('provider.test', 'other.test'),
      valid.replaceFirst('/base/', '/'),
      valid.replaceFirst('fixture-account', 'other'),
      valid.replaceFirst('/series/', '/movie/'),
      '$valid?token=secret',
      '$valid#fragment',
      valid.replaceFirst('42.mkv', '0.mkv'),
    ]) {
      expect(xtreamStreamId(url, credentials, kind: 'series'), isNull);
    }
  });
}
