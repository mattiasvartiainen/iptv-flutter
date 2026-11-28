# Local webOS video controller facade

`lib/video_player.dart` is derived from `video_player_drm` at
`3a742bb86b04e261044f0864f9b1f71acf0bbad3`; its upstream license is included.
Imports refer to the same pinned upstream package so the native implementation
continues to be selected and verified by the webOS build wrapper.

The local controller exposes raw native completion events independently of
position-derived `isCompleted`. The cause of an event is not known and must
not be assumed to be a natural end. Update this copy together with the pinned
upstream package, reviewing the local diff and rerunning the wrapper tests.
