# Aspire Diagnostics

## Status

Implemented 2026-11-01. Windows-to-Aspire export is verified with synthetic
playlists and a temporary SQLite database. LG webOS hardware export and large
playlist overhead measurement remain pending. Telemetry is disabled by default.

The app sends OTLP/HTTP directly to Aspire. An AppHost, collector, browser bridge,
and browser CORS configuration are not required for this native Flutter app.
Port 18888 is the dashboard UI, not an ingestion endpoint.

## Windows Setup

Start a standalone dashboard with explicit endpoints. These loopback bindings are
for Windows-only testing and do not expose an unauthenticated receiver to the LAN:

```powershell
aspire dashboard run --frontend-url http://127.0.0.1:28888 --otlp-grpc-url http://127.0.0.1:24317 --otlp-http-url http://127.0.0.1:24318 --application-name iptv-debug --allow-anonymous
```

Do not stop an existing dashboard to free ports without checking which session
owns it. Use different ports if necessary. The installed Aspire CLI supports
`--otlp-http-url`; inspect `aspire dashboard run --help` on other installations.

In the Windows app, open **Settings > Diagnostics**:

1. Enable **Send telemetry**.
2. Set **OTLP HTTP endpoint** to `http://127.0.0.1:24318`.
3. Set service name and device alias, for example `iptv-app` and `windows-dev`.
4. Leave the key empty for the loopback-only anonymous dashboard above.
5. Apply, then select **Send test telemetry**.

Check Structured logs, Traces, and Metrics. The test command reports successful
export only when all three exporters deliver data. This does not guarantee
long-term retention; dashboard limits and persistence settings still apply.

For startup diagnostics before Settings can be opened:

```powershell
flutter run -d windows --dart-define=IPTV_TELEMETRY_ENABLED=true --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:24318 --dart-define=OTEL_SERVICE_NAME=iptv-app --dart-define=IPTV_DEVICE_ALIAS=windows-dev
```

Failures include up to eight filtered stack frames by default.
`IPTV_TELEMETRY_VERBOSE=true` increases this to 32 frames;
`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` is the default transport
(`http/json` is also supported). The app explicitly reads these defines; it does
not promise automatic handling of all OTEL environment variables.

Saved runtime settings override build defaults, including a saved disabled state.
The settings JSON lives in the application support directory and is independent
of the catalog database. The optional key is stored separately through the
platform secret store, never in the JSON or a build define. If settings cannot be
read, startup uses build defaults. Do not put keys in source-controlled launch files.

## Repeatable Smoke Test

With the dashboard running:

```powershell
flutter test test/diagnostics/aspire_smoke.dart --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:24318
aspire otel logs --dashboard-url http://127.0.0.1:28888 --non-interactive
aspire otel traces --dashboard-url http://127.0.0.1:28888 --non-interactive
```

The test uses 1,000 synthetic items, cold/identical/changed imports, paged reads,
and an HTTP 503 failure. It checks real delivery of all three signals and deletes
its temporary catalog. It does not read or modify saved playlists. The filename
deliberately lacks `_test.dart`, so ordinary `flutter test` does not require Aspire.
For authenticated smoke tests, set `IPTV_OTLP_API_KEY` locally in the terminal;
the test reads it without printing it. Remove it afterward. The dashboard browser
login token and telemetry-query API key are not OTLP ingestion keys.

## LG webOS And LAN Setup

`localhost` on the TV refers to the TV. Replace the ingestion host with the
Windows computer's TV-reachable LAN IP or DNS name. At investigation time,
`192.168.1.84` was Ethernet and `169.254.83.107` was a Tailscale interface.
Verify current addresses and TV routing instead of assuming either stays valid.

For trusted development networks, configure the dashboard's HTTP ingestion bind
to the LAN interface (for example `--otlp-http-url http://192.168.1.84:24318`).
Keep the frontend loopback-only unless remote UI access is actually required.
Do not use `--allow-anonymous` when exposing the receiver to a LAN. Configure:

- `Dashboard:Otlp:AuthMode=ApiKey`.
- `Dashboard:Otlp:PrimaryApiKey` with a locally generated secret.
- The same secret in the app's OTLP API key field (`x-otlp-api-key` on requests).
- A Windows Firewall inbound rule restricted to the TV address/trusted subnet,
  private network profile, and the selected ingestion port.

UI browser authentication, OTLP ingestion authentication, and dashboard telemetry
query API authentication are separate. Do not disable all three to fix ingestion.
Use HTTPS outside a controlled trusted LAN: API keys over HTTP are not encrypted.
Do not bypass TLS certificate validation to work around TV trust issues.
Firewall changes requiring elevation must be performed by the developer.

Build using the supported Linux/WSL/DevContainer toolchain, for example:

```bash
bash tool/build-webos.sh --dart-define=IPTV_TELEMETRY_ENABLED=true --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=http://192.168.1.84:24318 --dart-define=IPTV_DEVICE_ALIAS=lg-tv
```

After installation, enter the optional key in Settings, apply, send test telemetry,
then reproduce the playlist problem. Hardware acceptance includes slow/interrupted
downloads, a failing refresh preserving existing data, cancellation, standby and
resume, and operation with the dashboard disconnected. Endpoint changes are
rejected while instrumented operations are active; retry once they finish.

## Reading The Diagnostics

- `playlist.import`: one root per actual job; concurrent subscribers share it.
- `http.playlist.headers`: time to headers; status logs include non-2xx responses.
- Worker failures report the original exception type (for example
  `HandshakeException`, not just `CatalogImportWorkerException`) and the original
  worker stack. `failure.phase` distinguishes connection, response headers, body,
  parsing, and batch acknowledgement. Network failures include a fixed safe
  explanation, HTTP status, OS error code, timeout duration, or a recognized TLS
  failure reason when available. Raw provider error messages are not exported.
- The same exception can fail the header span, cold/warm import span, root import
  span, and controller operation. These are propagation records, not four separate
  requests. Use their trace context to follow the first failure.
- `playlist.import.worker`: cumulative synchronous parsing time, selection wait,
  acknowledgement wait, parsed count, and bytes. Parsing time is not profiler CPU
  usage. Download/parsing/database work overlap; do not sum overlapping durations.
- `db.import.diff`, `db.import.write`: main-isolate work blocking worker progress.
- Cold/warm finalization and cleanup spans, reconciliation counts, indexer work,
  `db.open`, version-only migrations, transactions, and named catalog query spans.
- Progress logs are throttled to about two seconds; stalled jobs have five-second
  heartbeats. Logs carry trace context and import/session IDs even while the root
  span is unfinished.
- `iptv.operation.duration` and `iptv.operations` use bounded operation/outcome
  dimensions, not playlist IDs or item titles. Byte/item counts are structured
  diagnostics, not separate time-series metrics in this first implementation.

## User-facing Playlist Failures

Playlist import/refresh errors appear in a full-width panel below the affected
playlist card's actions, not in an automatic modal. Refresh retries the request
without moving focus; errors on other playlists remain visible. Retry, a
successful source save, or deletion clears that playlist's session-only error.
A late failure from a superseded request is still logged but does not restore a
cleared error. Verbose exception/stack details remain opt-in and appear under
the same card; unowned failures retain a section-level fallback.

The shared playlist issue mapper uses structured HTTP status metadata, not
exception-text matching. HTTP 511 displays **Network sign-in may be required**:
check the device's internet sign-in requirements and, if other services work,
contact the playlist provider. This status is intended for network authentication
but does not prove a captive portal; a provider gateway can return it too. It is
not classified as invalid playlist credentials, and changing this message does
not resolve the underlying HTTP failure. Verify the panel and Refresh/Back flow
on LG hardware after installing a fresh build.

## Safety And Limits

Export uses 256-record queues, 64-record batches, two-second network timeouts,
and no retry backlog. Trace/log batches run every two seconds; metrics every ten
seconds. Queue overflow drops records. Delivery counters/status are exposed by
the telemetry service; queue-drop counters and a persistent offline spool are not
implemented. Export failure must not change the business result or throw from a
database/import operation. The Settings test explicitly checks delivery failure.

Export attributes are allowlisted. Raw URLs are removed entirely; playlist bodies,
SQL statements/arguments/results, headers, keys, file paths, and raw exception
messages are not exported. Filesystem and network failures include fixed safe
summaries and OS error codes when available. Failures contain the underlying
exception type and filtered package/Dart or release-AOT stack frames (up to eight
normally, 32 in verbose mode). AOT address-only frames may need symbolization
against the exact matching build. Local debug output continues using
the existing redaction policy.
Native plugin output is not automatically intercepted or shipped.

SDK 0.12.0 caches named providers. Each endpoint change shuts down old exporters
and creates a fresh named generation; closed registrations remain in the SDK
registry for the process lifetime. Avoid repeatedly applying settings in a loop.
This is not a persistent leak of active network clients/timers, but it is a reason
to revisit SDK upgrades for long-running production configuration management.

Crashes, forced termination, and power loss can lose buffered records and unfinished
spans. Durable import-session recovery remains necessary. This feature is a
development diagnostic path, not a native crash reporter or retention service.

## Verification Record

- Focused telemetry/settings/startup/architecture run: 64 passed.
- Final telemetry plus live Aspire smoke run: 25 passed.
- Aspire retained correlated logs, successful and failed import traces, migration
  and query spans, and both metric instruments under `iptv-windows-smoke`.
- Full suite: 557 passed, two failures in existing Windows/Linux keyboard-only
  playlist-editor focus restoration (`test/features/navigation_focus_test.dart`,
  after Escape). Reproduced independently with telemetry controls absent; baseline
  modal focus handling remains unresolved and was not changed by this work.
- Full analyzer: no new issues; existing `unawaited_futures` infos in
  `test/app/navigation_focus_test.dart` and `webos/flutter/main.dart` remain.
- TV delivery, native Windows Settings use, full-size playlist overhead, restart
  recovery with the dashboard offline, and Linux/webOS compilation remain pending.

References: https://aspire.dev/dashboard/standalone/ and
https://aspire.dev/dashboard/configuration/.

### Playlist Failure Diagnostics (2026-11-25)

- 55 focused network-diagnostic, worker, OTLP export, import, and controller tests
  passed, including a real worker-isolate HTTP 403 exported to a loopback OTLP
  receiver. Credential/body/SQL exclusion, original worker stacks, TLS reasons,
  release-AOT frame filtering and nonverbose stack export are covered.
- Analyzer retains only the two pre-existing informational findings above.
- Full suite reached 559 passes and the same two modal-focus failures, then
  stalled without further progress and was stopped. No focus code was changed.
- A new webOS build and TV reproduction are required to diagnose the
  Xtream-specific failure. In the first `http.playlist.headers` failure, capture
  `exception.type`, `exception.message`, `failure.phase`,
  `http.response.status_code`, `exception.os_error_code`, `tls.failure_reason`,
  and `exception.stacktrace` (some fields apply only to certain failures).
  No provider credentials or playlist URLs are needed. Do not disable TLS
  validation or change database behavior without evidence.