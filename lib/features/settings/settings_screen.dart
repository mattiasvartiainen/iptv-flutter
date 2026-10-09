import 'package:flutter/material.dart';

import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import 'widgets/playlist_editor_dialog.dart';
import 'widgets/playlist_section.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playlists = AppScope.playlistsControllerOf(context);
    final preferences = AppScope.preferencesControllerOf(context);
    final app = AppScope.appControllerOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([playlists, preferences]),
      builder: (context, _) => AppShellScaffold(
        showBack: true,
        title: 'Settings',
        child: FocusTraversalGroup(
          child: ListView(
            padding: AppTokens.pagePaddingFor(MediaQuery.sizeOf(context).width),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.panelPadding),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Manage saved playlists, refresh them manually, and keep home section visibility in one place.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            showPlaylistEditor(context, controller: playlists),
                        icon: const Icon(Icons.add),
                        label: const Text('Add playlist'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PlaylistSection(
                controller: playlists,
                preferencesController: preferences,
                onEdit: (playlist) => showPlaylistEditor(
                  context,
                  controller: playlists,
                  playlist: playlist,
                ),
                onDelete: (playlist) =>
                    confirmPlaylistDelete(context, playlists, playlist),
              ),
              const SizedBox(height: 20),
              Card(
                child: SwitchListTile(
                  title: const Text('Show Live TV on Home'),
                  subtitle: const Text(
                    'Displays the Live TV row on the Home screen.',
                  ),
                  value: preferences.showHomeLiveTv,
                  onChanged: preferences.setShowHomeLiveTv,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Show Movies on Home'),
                  subtitle: const Text(
                    'Displays the Movies row on the Home screen.',
                  ),
                  value: preferences.showHomeMovies,
                  onChanged: preferences.setShowHomeMovies,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Show Series on Home'),
                  subtitle: const Text(
                    'Displays the Series row on the Home screen.',
                  ),
                  value: preferences.showHomeSeries,
                  onChanged: preferences.setShowHomeSeries,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Display verbose information'),
                  subtitle: const Text(
                    'Shows download and import progress while a playlist refreshes.',
                  ),
                  value: preferences.verboseRefreshInfo,
                  onChanged: preferences.setVerboseRefreshInfo,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: app.goBack, child: const Text('Back')),
            ],
          ),
        ),
      ),
    );
  }
}
