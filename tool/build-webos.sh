#!/usr/bin/env bash
set -euo pipefail

# Build wrapper for webOS packaging from VS Code terminals.
# VS Code's js-debug can inject NODE_OPTIONS=--require <bootloader>,
# which breaks ares-package when that path is not present.

cd "$(dirname "$0")/.."

if [[ -f /etc/profile.d/flutter-webos.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/flutter-webos.sh
fi

if ! command -v flutter-webos >/dev/null 2>&1; then
  echo "[build-webos] ERROR: flutter-webos not found in PATH"
  exit 1
fi

# Remove editor-injected Node preload/debug hooks for child Node processes.
unset NODE_OPTIONS || true
unset VSCODE_INSPECTOR_OPTIONS || true
unset ELECTRON_RUN_AS_NODE || true

echo "[build-webos] Running dependency sync..."
flutter-webos pub get >/dev/null

echo "[build-webos] Building webOS package..."

define_present=false
for arg in "$@"; do
  if [[ "$arg" == --dart-define=IPTV_WEBOS=* ]]; then
    define_present=true
    break
  fi
done

if [[ "$define_present" == true ]]; then
  exec flutter-webos build webos "$@"
fi

exec flutter-webos build webos --dart-define=IPTV_WEBOS=true "$@"
