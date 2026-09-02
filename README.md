# iptv_flutter

Flutter IPTV application for LG webOS, Linux desktop, and Windows desktop.

## Project layout

Platform-specific code stays behind the playback adapter in `lib/services/playback/`:

```text
lib/
  app.dart
  main.dart
  models/
  screens/
  services/
    playback/
      playback_adapter.dart
      linux_playback.dart
      windows_playback.dart
      webos_playback.dart
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

## webOS packaging and deployment

Run these commands inside the Linux devcontainer. The build wrapper automatically sets
`IPTV_WEBOS=true` and writes an IPK under `build/webos/`:

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
packaging, and webOS deployment. The WebOS target still uses the intentionally isolated
adapter stub until hardware playback validation is completed.
