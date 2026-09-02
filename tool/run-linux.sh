#!/usr/bin/env bash
set -euo pipefail

# Wrapper used inside devcontainer to avoid stale/missing linux plugin symlinks.
bash .devcontainer/bootstrap-linux-plugins.sh

extra_args=()

has_define() {
  local key="$1"
  shift
  for arg in "$@"; do
    if [[ "$arg" == --dart-define=${key}=* ]]; then
      return 0
    fi
  done
  return 1
}

if ! has_define "IPTV_DESKTOP_BACKEND" "$@"; then
  extra_args+=("--dart-define=IPTV_DESKTOP_BACKEND=media_kit")
fi

if ! has_define "IPTV_DISABLE_VIDEO_OUTPUT" "$@"; then
  extra_args+=("--dart-define=IPTV_DISABLE_VIDEO_OUTPUT=false")
fi

if ! has_define "IPTV_DISABLE_HW_ACCEL" "$@"; then
  extra_args+=("--dart-define=IPTV_DISABLE_HW_ACCEL=true")
fi

if command -v flutter-webos >/dev/null 2>&1; then
  exec flutter-webos run -d linux "${extra_args[@]}" "$@"
fi

exec flutter run -d linux "${extra_args[@]}" "$@"
