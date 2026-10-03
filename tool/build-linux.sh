#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash .devcontainer/bootstrap-linux-plugins.sh

flutter_command=flutter
if command -v flutter-webos >/dev/null 2>&1; then
  flutter_command=flutter-webos
fi

"$flutter_command" pub get
exec "$flutter_command" build linux --release "$@"
