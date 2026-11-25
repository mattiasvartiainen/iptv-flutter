import 'package:flutter/material.dart';

import '../../../services/playback/playback_contract.dart';
import '../player_layout.dart';

class PlayerTrackDialog extends StatelessWidget {
  const PlayerTrackDialog({
    super.key,
    required this.mediaInfo,
    required this.subtitle,
    required this.onSelected,
    required this.onCancel,
  });

  final PlaybackMediaInfo mediaInfo;
  final bool subtitle;
  final ValueChanged<String> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tracks = subtitle ? mediaInfo.subtitleTracks : mediaInfo.audioTracks;
    final selected = subtitle
        ? mediaInfo.selectedSubtitleId
        : mediaInfo.selectedAudioId;
    final availableHeight = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: Text(subtitle ? 'Subtitles' : 'Audio tracks'),
      content: SizedBox(
        width: PlayerLayout.trackDialogWidth,
        height: PlayerLayout.trackListHeight(
          trackCount: tracks.length,
          textScaler: MediaQuery.textScalerOf(context),
          availableHeight: availableHeight,
        ),
        child: tracks.isEmpty
            ? const Text('No tracks available.')
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: PlayerLayout.trackListMaxHeight(availableHeight),
                ),
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (_, index) {
                    final track = tracks[index];
                    return ListTile(
                      autofocus:
                          track.id == selected ||
                          (selected == null && index == 0),
                      title: Text(track.label),
                      trailing: track.id == selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => onSelected(track.id),
                    );
                  },
                ),
              ),
      ),
      actions: [TextButton(onPressed: onCancel, child: const Text('Cancel'))],
    );
  }
}
