# iptv_flutter

TV-first Flutter IPTV for Android (phone and TV), Windows and LG webOS.
Linux desktop is a development/testing target. See the
[documentation index](docs/README.md) for current architecture, work packages
and historical reference documents.

## Project layout

Platform detection and backend selection stay in `lib/platform/`.
Shared presentation depends on injected interfaces and available constraints:

```text
lib/
  app.dart
  main.dart
  models/
  app/                 composition, navigation and shortcuts
  features/            screens, widgets and feature controllers
  platform/            identity, profiles and platform-specific adapters
  ui/                  shared widgets, theme and layout tokens
  services/
    playback/          contracts, session boundary and backend implementations
  state/
linux/
windows/
webos/
web/
test/
```

## Development

Run Linux safely in the devcontainer:

```bash
bash tool/run-linux.sh
```

Build Linux release:

```bash
bash tool/build-linux.sh
```

On Windows 11, create the missing desktop folders once and build Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool/bootstrap-platforms.ps1
powershell -ExecutionPolicy Bypass -File tool/build-windows.ps1
```

Windows output is written to `build/windows/x64/runner/Release`.

If the build reports `Building native assets failed`, run
`flutter build windows --release -v` to see the underlying error. Flutter may
select an incomplete MSVC toolset directory left by a Visual Studio update,
even when `flutter doctor` succeeds. If the verbose output reports missing
`cl.exe`, `link.exe`, or `lib.exe`, use Visual Studio Installer to repair the
C++ desktop build tools or remove the incomplete toolset component, then retry.

## webOS packaging and deployment

Run these commands inside the Linux devcontainer. The build wrapper automatically sets
`IPTV_WEBOS=true`, requires Node.js 20 or newer on `PATH`, and writes an IPK under
`build/webos/`:

```bash
bash tool/build-webos.sh
bash tool/deploy-webos.sh --device tv
```

The device name is registered with the webOS CLI. It can also be supplied through
`WEBOS_DEVICE`. To install without launching:

```bash
bash tool/deploy-webos.sh --device tv --no-launch
```

Use the VS Code tasks for Linux release builds, Windows release builds, webOS debug/release
packaging, and webOS deployment. The webOS target uses the dedicated LG `video_player_drm` adapter.
The supported wrapper verifies and patches pinned native logging before enabling
playback; do not bypass it or manually set the safe-build marker. Real TV
playback, track selection and native-plane compositing still require hardware
validation; a desktop build or mocked-plugin test does not establish them.
