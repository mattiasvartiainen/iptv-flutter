#!/usr/bin/env bash
set -euo pipefail

# Build wrapper for webOS packaging from VS Code terminals.
# VS Code's js-debug can inject NODE_OPTIONS=--require <bootloader>,
# which breaks ares-package when that path is not present.

cd "$(dirname "$0")/.."

if [[ -L .dart_tool || -L .dart_tool/webos-pub-cache ]]; then
  echo "[build-webos] ERROR: isolated pub cache must not be a symlink" >&2
  exit 1
fi
mkdir -p .dart_tool
if ! mkdir .dart_tool/webos-build.lock 2>/dev/null; then
  echo "[build-webos] ERROR: another webOS build is running or its lock is stale" >&2
  exit 1
fi
trap 'rmdir .dart_tool/webos-build.lock' EXIT

if [[ -f /etc/profile.d/flutter-webos.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/flutter-webos.sh
fi
export PUB_CACHE="$PWD/.dart_tool/webos-pub-cache"

if ! command -v flutter-webos >/dev/null 2>&1; then
  echo "[build-webos] ERROR: flutter-webos not found in PATH"
  exit 1
fi

# Remove editor-injected Node preload/debug hooks for child Node processes.
unset NODE_OPTIONS || true
unset VSCODE_INSPECTOR_OPTIONS || true
unset ELECTRON_RUN_AS_NODE || true

node_found=false
IFS=: read -r -a path_entries <<< "$PATH"
for directory in "${path_entries[@]}"; do
  directory=${directory:-.}
  if [[ -x "$directory/node" ]] && [[ "$("$directory/node" -p 'Number(process.versions.node.split(".")[0]) >= 20' 2>/dev/null)" == true ]]; then
    export PATH="$directory:$PATH"
    node_found=true
    break
  fi
done

if [[ "$node_found" != true ]]; then
  echo "[build-webos] ERROR: Node.js 20 or newer is required for ares-package" >&2
  exit 1
fi

define_present=false
for arg in "$@"; do
  if [[ "$arg" == --dart-define=IPTV_WEBOS_SAFE_NATIVE_LOGS=* || "$arg" == --pub ]]; then
    echo "[build-webos] ERROR: native logging marker and pub mode are managed by this script" >&2
    exit 1
  fi
  if [[ "$arg" == --dart-define=IPTV_WEBOS=* ]]; then
    define_present=true
  fi
done

echo "[build-webos] Running dependency sync..."
flutter-webos pub get >/dev/null

echo "[build-webos] Verifying and securing isolated native plugin..."
node tool/patch-webos-playback-logging.cjs

echo "[build-webos] Building webOS package..."

if [[ "$define_present" == true ]]; then
  flutter-webos build webos "$@" --no-pub --dart-define=IPTV_WEBOS_SAFE_NATIVE_LOGS=true
else
  flutter-webos build webos "$@" --no-pub --dart-define=IPTV_WEBOS=true --dart-define=IPTV_WEBOS_SAFE_NATIVE_LOGS=true
fi
