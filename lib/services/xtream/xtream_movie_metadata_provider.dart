import 'dart:async';

import '../metadata/movie_metadata.dart';
import 'xtream_api_client.dart';
import 'xtream_authentication.dart';
import 'xtream_vod_metadata.dart';

class XtreamMovieMetadataProvider implements MovieMetadataProvider {
  const XtreamMovieMetadataProvider(this.client);
  final XtreamApiClient client;
  @override
  String get id => 'xtream';
  @override
  bool supports(MovieMetadataSubject subject) =>
      positiveProviderId(subject.providerMovieId) != null;

  @override
  Future<MovieMetadataResult> fetch(
    MovieMetadataSubject subject,
    MetadataCancellation cancellation,
  ) async {
    final operation = XtreamCancellation();
    unawaited(cancellation.whenCancelled.then((_) => operation.cancel()));
    if (cancellation.isCancelled) operation.cancel();
    return client.getVodInfo(
      playlistId: subject.playlistId,
      connectionRevision: subject.connectionRevision,
      movieId: subject.providerMovieId!,
      cancellation: operation,
    );
  }
}

String? xtreamMovieId(String streamUrl, XtreamCredentials credentials) {
  try {
    final stream = Uri.tryParse(streamUrl);
    final endpoint = credentials.endpoint;
    if (stream == null ||
        stream.scheme != endpoint.scheme ||
        stream.host != endpoint.host ||
        stream.port != endpoint.port ||
        stream.userInfo.isNotEmpty ||
        stream.hasQuery ||
        stream.hasFragment) {
      return null;
    }
    final base = endpoint.pathSegments
        .take(endpoint.pathSegments.length - 1)
        .toList();
    final parts = stream.pathSegments;
    if (parts.length != base.length + 4) return null;
    for (var index = 0; index < base.length; index++) {
      if (parts[index] != base[index]) return null;
    }
    if (parts[base.length] != 'movie' ||
        parts[base.length + 1] != credentials.username ||
        parts[base.length + 2] != credentials.password) {
      return null;
    }
    final match = RegExp(
      r'^([1-9][0-9]{0,18})(?:\.[a-zA-Z0-9]{1,8})?$',
    ).firstMatch(parts.last);
    return match?.group(1);
  } on FormatException {
    return null;
  }
}
