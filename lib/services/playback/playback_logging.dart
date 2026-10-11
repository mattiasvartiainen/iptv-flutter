import 'playback_contract.dart';

bool isPlaybackLogTransition(PlaybackState previous, PlaybackState next) =>
    previous.status != next.status || previous.isBuffering != next.isBuffering;
