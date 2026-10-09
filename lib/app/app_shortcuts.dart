import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> buildAppShortcuts({
  Map<ShortcutActivator, Intent> extraShortcuts = const {},
}) => {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.escape): BackIntent(),
  const SingleActivator(LogicalKeyboardKey.goBack): BackIntent(),
  const SingleActivator(LogicalKeyboardKey.browserBack): BackIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause): PlayPauseIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPlay): PlayIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaPause): PauseIntent(),
  const SingleActivator(LogicalKeyboardKey.mediaFastForward): SeekIntent(
    Duration(seconds: 10),
  ),
  const SingleActivator(LogicalKeyboardKey.mediaRewind): SeekIntent(
    Duration(seconds: -10),
  ),
  const SingleActivator(LogicalKeyboardKey.channelUp): ChannelStepIntent(1),
  const SingleActivator(LogicalKeyboardKey.channelDown): ChannelStepIntent(-1),
  ...extraShortcuts,
};

final class BackIntent extends Intent {
  const BackIntent();
}

final class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

final class PlayIntent extends Intent {
  const PlayIntent();
}

final class PauseIntent extends Intent {
  const PauseIntent();
}

final class SeekIntent extends Intent {
  const SeekIntent(this.offset);

  final Duration offset;
}

final class ChannelStepIntent extends Intent {
  const ChannelStepIntent(this.step);

  final int step;
}
