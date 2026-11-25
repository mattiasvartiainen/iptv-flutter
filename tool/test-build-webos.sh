#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
project="$PWD"
scratch="$project/.dart_tool/webos-wrapper-test-$$"
mkdir -p "$scratch/tool" "$scratch/bin"
trap 'rm -rf "$scratch"' EXIT
cp tool/build-webos.sh "$scratch/tool/"

cat > "$scratch/tool/patch-webos-playback-logging.cjs" <<'EOF'
const fs = require('node:fs');
fs.appendFileSync(process.env.TEST_LOG, 'verify\n');
if (process.env.TEST_FAIL_VERIFY === '1') process.exit(1);
EOF
cat > "$scratch/bin/flutter-webos" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$PUB_CACHE" == "$PWD/.dart_tool/webos-pub-cache" ]]
[[ -z "${NODE_OPTIONS:-}" ]]
printf '%s\n' "$*" >> "$TEST_LOG"
EOF
chmod +x "$scratch/bin/flutter-webos"
export PATH="$scratch/bin:$PATH"
export TEST_LOG="$scratch/calls"
export NODE_OPTIONS=--require=editor-only-preload
cd "$scratch"

bash tool/build-webos.sh --release >/dev/null
grep -Fx 'pub get' "$TEST_LOG" >/dev/null
grep -Fx 'verify' "$TEST_LOG" >/dev/null
grep -Fx 'build webos --release --no-pub --dart-define=IPTV_WEBOS=true --dart-define=IPTV_WEBOS_SAFE_NATIVE_LOGS=true' "$TEST_LOG" >/dev/null
[[ ! -e .dart_tool/webos-build.lock ]]

: > "$TEST_LOG"
if TEST_FAIL_VERIFY=1 bash tool/build-webos.sh >/dev/null 2>&1; then
  echo 'verification failure did not stop the build' >&2
  exit 1
fi
! grep -q '^build ' "$TEST_LOG"
[[ ! -e .dart_tool/webos-build.lock ]]

: > "$TEST_LOG"
if bash tool/build-webos.sh --dart-define=IPTV_WEBOS=true --dart-define=IPTV_WEBOS_SAFE_NATIVE_LOGS=false >/dev/null 2>&1; then
  echo 'marker override was accepted' >&2
  exit 1
fi
[[ ! -s "$TEST_LOG" ]]
echo 'webOS build wrapper checks passed'
