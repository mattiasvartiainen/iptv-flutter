import 'package:flutter/foundation.dart';

@immutable
class LibraryIdentity {
  const LibraryIdentity({
    required this.playlistId,
    required this.profileId,
    required this.itemKey,
  });

  final String playlistId;
  final String profileId;
  final int itemKey;

  @override
  bool operator ==(Object other) =>
      other is LibraryIdentity &&
      other.playlistId == playlistId &&
      other.profileId == profileId &&
      other.itemKey == itemKey;

  @override
  int get hashCode => Object.hash(playlistId, profileId, itemKey);
}
