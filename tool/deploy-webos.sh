#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

device=''
package=''
launch=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device|-d) device="$2"; shift 2 ;;
    --package|-p) package="$2"; shift 2 ;;
    --no-launch) launch=false; shift ;;
    -h|--help)
      echo 'Usage: bash tool/deploy-webos.sh --device <name> [--package <ipk>] [--no-launch]'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$device" ]]; then
  device="${WEBOS_DEVICE:-}"
fi
if [[ -z "$device" ]]; then
  echo 'Missing webOS device. Pass --device <name> or set WEBOS_DEVICE.' >&2
  exit 2
fi

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
  echo '[deploy-webos] ERROR: Node.js 20 or newer is required for the webOS CLI' >&2
  exit 1
fi

if ! command -v ares-install >/dev/null 2>&1 || ! command -v ares-launch >/dev/null 2>&1; then
  echo 'webOS CLI commands ares-install and ares-launch are required.' >&2
  exit 1
fi

if [[ -z "$package" ]]; then
  package="$(find build/webos -type f -name '*.ipk' -print 2>/dev/null | sort | tail -n 1)"
fi
if [[ -z "$package" || ! -f "$package" ]]; then
  echo 'No IPK found. Build first with bash tool/build-webos.sh or pass --package.' >&2
  exit 1
fi

if ares-install --device "$device" "$package"; then
  :
else
  status=$?
  if command -v ares-setup-device >/dev/null 2>&1; then
    echo 'Configured webOS devices:' >&2
    ares-setup-device --list >&2 || true
  else
    echo 'Cannot list devices: ares-setup-device is not available.' >&2
  fi
  exit "$status"
fi
if [[ "$launch" == true ]]; then
  ares-launch --device "$device" com.flutter.app.iptv-flutter
fi
