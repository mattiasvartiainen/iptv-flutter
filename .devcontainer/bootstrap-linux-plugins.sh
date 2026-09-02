#!/usr/bin/env bash
set -euo pipefail

cd "${1:-/workspaces/iptv-flutter}"

if [[ -f /etc/profile.d/flutter-webos.sh ]]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/flutter-webos.sh
fi

if [[ ! -f pubspec.yaml ]]; then
  echo "[bootstrap] pubspec.yaml not found, skipping plugin bootstrap."
  exit 0
fi

if ! pkg-config --exists mpv; then
  echo "[bootstrap] ERROR: missing pkg-config entry for 'mpv' (install libmpv-dev)."
  echo "[bootstrap] If this repo is in a devcontainer, rebuild the container after pulling latest Dockerfile."
  exit 1
fi

if ! pkg-config --exists epoxy; then
  echo "[bootstrap] ERROR: missing pkg-config entry for 'epoxy' (install libepoxy-dev)."
  echo "[bootstrap] If this repo is in a devcontainer, rebuild the container after pulling latest Dockerfile."
  exit 1
fi

echo "[bootstrap] Running pub get..."
if command -v flutter-webos >/dev/null 2>&1; then
  flutter-webos pub get >/dev/null
else
  flutter pub get >/dev/null
fi

plugin_root="linux/flutter/ephemeral/.plugin_symlinks"
mkdir -p "$plugin_root"

plugins_file="linux/flutter/generated_plugins.cmake"
if [[ ! -f "$plugins_file" ]]; then
  echo "[bootstrap] $plugins_file not found yet, nothing to link."
  exit 0
fi

cache_root="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev"
if [[ ! -d "$cache_root" ]]; then
  echo "[bootstrap] Pub cache not found at $cache_root"
  exit 1
fi

# Extract the plugin names from the FLUTTER_PLUGIN_LIST block.
mapfile -t plugins < <(awk '
  /list\(APPEND FLUTTER_PLUGIN_LIST/ { in_list=1; next }
  in_list && /^\)/ { in_list=0; next }
  in_list {
    gsub(/^[ \t]+|[ \t]+$/, "");
    if (length($0) > 0) print $0;
  }
' "$plugins_file")

if [[ ${#plugins[@]} -eq 0 ]]; then
  echo "[bootstrap] No linux plugins listed in generated_plugins.cmake"
  exit 0
fi

missing=0
for plugin in "${plugins[@]}"; do
  match="$(find "$cache_root" -maxdepth 1 -type d -name "${plugin}-*" | sort -V | tail -n 1 || true)"

  if [[ -z "$match" ]]; then
    echo "[bootstrap] WARN: package not found in pub cache for $plugin"
    missing=$((missing + 1))
    continue
  fi

  if [[ ! -d "$match/linux" ]]; then
    echo "[bootstrap] WARN: package exists but has no linux folder: $plugin ($match)"
    missing=$((missing + 1))
    continue
  fi

  ln -sfn "$match" "$plugin_root/$plugin"
  echo "[bootstrap] linked $plugin -> $match"
done

if [[ $missing -gt 0 ]]; then
  echo "[bootstrap] Completed with $missing missing plugin link(s)."
  exit 1
fi

echo "[bootstrap] Linux plugin symlinks ready."
