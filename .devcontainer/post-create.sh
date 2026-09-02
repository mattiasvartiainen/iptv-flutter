#!/usr/bin/env bash
set -euo pipefail
source /etc/profile.d/flutter-webos.sh
if [[ ! -f pubspec.yaml ]]; then
  temp_project="$(mktemp -d)"
  trap 'rm -rf "$temp_project"' EXIT
  flutter-webos create --platforms webos,linux "$temp_project/iptv_flutter"
  cp -a "$temp_project/iptv_flutter/." .
fi

bash .devcontainer/bootstrap-linux-plugins.sh

