# Local video_player patch

This package contains the runtime library and package metadata from Flutter's
`video_player` 2.11.1, published on pub.dev. The original package archive SHA-256
is `48a7bdaa38a3d50ec10c78627abdbfad863fdf6f0d6e08c7c3c040cfd80ae36f`.
Upstream source and attribution are in the package metadata, AUTHORS, and
LICENSE. Examples, tests, and generated documentation are not vendored.

The local change adds `VideoPlayerController.nativeCompletionEvents`, exposing
the platform's raw completion events without interpreting their cause. The
application must not assume these mean a natural end; a native player may also
report completion following a seek. The patch also closes the event stream on
disposal and updates an upstream doc reference to avoid a deprecated-member
warning in the application analyzer. Keep the patch and this provenance record
when updating the package.
