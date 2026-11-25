import 'package:flutter/material.dart';

import '../../../services/playback/playback_contract.dart';

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
    return AlertDialog(
      title: Text(subtitle ? 'Subtitles' : 'Audio tracks'),
      content: SizedBox(
        width: 440,
        height: tracks.isEmpty
            ? null
            : (tracks.length * 72.0 * MediaQuery.textScalerOf(context).scale(1))
                  .clamp(0, MediaQuery.sizeOf(context).height * .45),
        child: tracks.isEmpty
            ? const Text('No tracks available.')
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .5,
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
