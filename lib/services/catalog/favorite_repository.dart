abstract interface class FavoriteRepository {
  Future<bool> isFavorite({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  });
  Future<void> setFavorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  });
}
