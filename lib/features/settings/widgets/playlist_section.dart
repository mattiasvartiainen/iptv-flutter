import 'package:flutter/material.dart';

import '../../../services/settings/settings_repository.dart';
import '../../../state/app_preferences_controller.dart';
import '../../../state/playlists_controller.dart';
import '../../../ui/theme/app_tokens.dart';
import 'playlist_card.dart';

class PlaylistSection extends StatelessWidget {
  const PlaylistSection({
    super.key,
    required this.controller,
    required this.preferencesController,
    required this.onEdit,
    required this.onDelete,
  });

  final PlaylistsController controller;
  final AppPreferencesController preferencesController;
  final ValueChanged<ManagedPlaylist?> onEdit;
  final ValueChanged<ManagedPlaylist> onDelete;

  @override
  Widget build(BuildContext context) {
    final playlists = controller.playlists;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.panelPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Playlists',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('${playlists.length} saved'),
              ],
            ),
            if (controller.errorMessage case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            if (playlists.isEmpty)
              const _EmptyPlaylistState()
            else
              ...playlists.map(
                (playlist) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PlaylistCard(
                    playlist: playlist,
                    isActive:
                        playlist.playlistId == controller.activePlaylistId,
                    isRefreshing:
                        playlist.playlistId == controller.refreshingPlaylistId,
                    progress:
                        playlist.playlistId ==
                                controller.refreshingPlaylistId &&
                            preferencesController.verboseRefreshInfo
                        ? controller.importProgress
                        : null,
                    onSelect: () =>
                        controller.selectPlaylist(playlist.playlistId),
                    onRefresh: () =>
                        controller.refreshPlaylist(playlist.playlistId),
                    onEdit: () => onEdit(playlist),
                    onDelete: () => onDelete(playlist),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylistState extends StatelessWidget {
  const _EmptyPlaylistState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.panelRadius),
      ),
      child: const Text(
        'No playlists saved yet. Add a URL playlist or enter Xtream Codes details to store it here.',
      ),
    );
  }
}
