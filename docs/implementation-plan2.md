 - The current load() is asynchronous, but the expensive work still runs on the UI isolate:
      - Entire response is accumulated into a String in HttpPlaylistSource.fetch() (lib/services/catalog/
        catalog_repository.dart:46).

      - M3uParser.parse() creates a List<ContentItem> for the complete playlist (lib/services/catalog/m3u_parser.dart:24).
      - The repository validates and stages that full list inside the import transaction (lib/services/catalog/
        sqlite_catalog_repository.dart:184, :233).

  - The search-index worker starts only after load() completes (lib/services/catalog/sqlite_catalog_repository.dart:141).
    This explains why the UI can report completion while substantial work remains.

  - Progress currently has only two phases: downloading and importing (lib/services/catalog/
    catalog_import_progress.dart:3).

  - A second load() for the same playlist joins the existing future, but its progress callback is not attached to the
    original job. Progress should therefore be job-level and broadcast to all observers.

  - The existing documentation already identifies the critical platform constraint: sqflite_common_ffi can potentially run
    in an isolate, but platform-channel SQLite implementations on webOS and Android may not be usable from a background
    isolate.

  ## Recommended Architecture

  Use a background parser with a UI-isolate database writer as the default cross-platform design.

  UI isolate
    ImportCoordinator
      ├─ receives progress events
      ├─ controls cancellation
      ├─ owns the SQLite connection
      └─ writes bounded batches

  Background isolate
    PlaylistImportWorker
      ├─ downloads playlist
      ├─ incrementally parses M3U records
      ├─ normalizes lightweight import DTOs
      └─ sends bounded batches and progress events

  This avoids relying on background SQLite support on webOS and Android while removing the largest UI blocker: parsing and
  playlist materialization.

  The worker should not return List<ContentItem> or the entire playlist. It should send bounded batches, for example:

  ImportBatch
    batchNumber
    firstSourceIndex
    items[]
    parsedCount
    rejectedCount

  Use a batch size in the range of 500–2,000 records, then benchmark on real webOS hardware. Only one or two batches should
  be in flight at a time to maintain backpressure and bounded memory.

  ## Progress Model

  Extend CatalogImportProgress from a coarse two-phase model to an import job model.

  Suggested phases:

  enum CatalogImportPhase {
    starting,
    downloading,
    parsing,
    validating,
    staging,
    reconciling,
    indexing,
    completed,
    cancelled,
    failed,
  }

  Add fields similar to:

  class CatalogImportProgress {
    final String jobId;
    final String playlistId;
    final CatalogImportPhase phase;
    final DateTime startedAt;
    final DateTime updatedAt;

    final int? bytesReceived;
    final int? totalBytes;

    final int parsedItems;
    final int stagedItems;
    final int acceptedItems;
    final int rejectedItems;
    final int insertedItems;
    final int updatedItems;
    final int deletedItems;
    final int indexedItems;
    final int? totalItems;

    final int? currentBatch;
    final int? totalBatches;
    final String? currentOperation;
    final String? message;
    final Object? error;
  }

  Useful derived values:

  - phaseFraction
  - overallFraction
  - itemsPerSecond
  - bytesPerSecond
  - estimatedRemaining
  - isTerminal
  - isIndeterminate

  Do not force a misleading percentage during SQL operations where SQLite cannot provide incremental progress. Report:

  Reconciling catalog…
  12.4 seconds elapsed

  rather than displaying a stalled or inaccurate progress bar.

  ## Import Lifecycle

  The full lifecycle should become:

  starting
    → downloading
    → parsing
    → validating
    → staging
    → reconciling
    → indexing
    → completed

  Failure and cancellation can occur from any non-terminal phase:

                           ┌─ failed
                           ├─ cancelled
  starting → ... → completed

  ### 1. Starting

  Create an ImportJob and immediately publish:

  - job ID
  - playlist ID
  - start time
  - cached item count
  - whether this is a cold import or refresh
  - previous successful catalog availability

  Keep the existing catalog visible until the new import commits successfully.

  ### 2. Downloading

  Move download ownership into the worker where possible.

  Replace the current whole-string API:

  Future<String> fetch(...)

  with a streaming-oriented abstraction, such as:

  Stream<PlaylistChunk> fetchStream(...)

  or let the worker directly consume the response stream.

  Report:

  - bytes received
  - total bytes when Content-Length exists
  - download rate
  - elapsed time

  This eventually removes the current full playlist String from the UI isolate.

  ### 3. Parsing

  The worker should parse incrementally from chunks or lines.

  Important requirements:

  - Do not use split() or retain all lines.
  - Do not build a full List<ContentItem>.
  - Keep only the parser state needed for the current #EXTINF record.
  - Emit compact serializable DTOs in batches.
  - Report parsed count and source index.
  - Report rejected records separately from valid records.
  - Check for cancellation between records and batches.

  Initially, the worker can emit maps or a dedicated immutable DTO. Avoid sending UI/domain-heavy objects if they contain
  unnecessary metadata.

  ### 4. Staging

  Refactor the repository’s staging API. The current _reconcileViaStagingSqlWithinSavepoint() expects the entire parsed
  list (lib/services/catalog/sqlite_catalog_repository.dart:956).

  Split it into operations conceptually like:

  beginImportTransaction()
  clearStagingRows()
  stageBatch(batch)
  finishStaging()
  resolveIdentities()
  reconcileCatalog()
  commitImport()

  The UI isolate owns the SQLite transaction and writes each received batch as it arrives.

  Progress should report:

  - batch number
  - staged item count
  - rejected item count
  - staging rate
  - total item count if known

  The transaction can remain atomic initially. Staging batches inside one transaction still provide bounded Dart memory and
  allow progress callbacks between database calls.

  ### 5. Reconciliation

  Keep the existing set-based SQL reconciliation as the primary path. Do not reintroduce the per-item Dart path for normal
  operation.

  Split the reconciliation into reportable stages:

  resolve identities
  deduplicate staging rows
  upsert categories
  upsert media items
  rebuild derived series/seasons/episodes
  delete stale rows
  queue search-index changes

  Each stage should report:

  - stage name
  - elapsed duration
  - rows affected where available
  - whether the staging fallback was triggered

  The existing onStagingReconcileFallback hook should become a progress/error event rather than only a diagnostic callback.
  Falling back to per-item savepoints for a 500,000-item playlist should be treated as a visible performance failure.

  ### 6. Search indexing

  Make search indexing part of the import job lifecycle.

  Currently _startSearchIndexWorker() runs after load() returns, so the UI can show completion too early. Choose one of
  these semantics:

  Recommended:

  - load() completes only after catalog reconciliation commits.
  - The progress job continues through an indexing phase.
  - UI displays “Catalog ready — finishing search index…” during FTS work.
  - A final completed event is emitted after indexing drains.

  If immediate catalog availability is more important, expose both states explicitly:

  catalogReady = true
  searchIndexReady = false

  Do not hide the index phase behind a fire-and-forget worker.

  Add progress to processSearchIndexQueue():

  - queued row count
  - processed row count
  - current batch
  - index rate
  - remaining queue count

  ## Cancellation

  Add a cancellable import handle rather than relying only on Future cancellation:

  abstract interface class CatalogImportJob {
    String get id;
    Stream<CatalogImportProgress> get progress;
    Future<CatalogLoadResult> get result;
    Future<void> cancel();
  }

  Cancellation behavior:

  1. UI sends a cancel message to the worker.
  2. Worker stops reading the network stream.
  3. Worker stops parsing at the next record/batch boundary.
  4. Coordinator stops accepting new batches.
  5. SQLite transaction is rolled back.
  6. Existing catalog remains untouched.
  7. A terminal cancelled progress event is published.

  The transaction must not be committed after cancellation, even if some batches have already been staged.

  ## Platform Strategy

  ### webOS and Android

  Use:

  - background isolate for download and parsing
  - UI isolate for SQLite writes
  - bounded message batches
  - explicit backpressure
  - no dependency on background platform-channel SQLite

  This should be the baseline implementation.

  ### Windows/Linux

  Optionally optimize later by running the entire import, including SQLite, in a worker isolate using sqflite_common_ffi.
  That is not necessary for the first implementation and would create two execution paths.

  A better approach is:

  1. Implement the shared worker/UI-writer path first.
  2. Benchmark it.
  3. Add an FFI full-worker path only if Windows performance needs it.
  4. Keep the behavior and progress events identical across both paths.

  ### Web

  If the application also targets Flutter Web separately, treat it as a distinct adapter. The current dart:io-based HTTP
  source cannot be assumed to work there. Use browser-compatible streaming/fetch behavior and verify isolate support in the
  selected browser deployment.

  ## Suggested Implementation Phases

  ### Phase 1 — Progress contract

  No pipeline behavior change yet.

  - Extend CatalogImportPhase.
  - Add job ID and counters.
  - Add terminal states.
  - Add indexing progress.
  - Add stage names and elapsed durations.
  - Change AppController to store progress by playlist/job.
  - Ensure concurrent observers receive the same progress stream.
  - Add tests for progress ordering and terminal events.

  Relevant current UI state is in lib/state/app_controller.dart:82-92 and :445; rendering is in lib/screens/
  settings_screen.dart:345.

  ### Phase 2 — Extract an import coordinator

  Create a service responsible for orchestration, for example:

  lib/services/catalog/catalog_import_coordinator.dart
  lib/services/catalog/catalog_import_worker.dart
  lib/services/catalog/catalog_import_protocol.dart

  Responsibilities:

  - create job IDs
  - start/stop the worker
  - forward progress
  - apply backpressure
  - handle cancellation
  - coordinate the SQLite writer
  - expose one job stream to the UI

  Keep SqliteCatalogRepository focused on catalog persistence rather than isolate/message management.

  ### Phase 3 — Move parsing off the UI isolate

  - Start with the existing fetched string if necessary.
  - Parse it in a worker isolate.
  - Emit bounded batches.
  - Keep SQLite writes on the UI isolate.
  - Add memory and responsiveness benchmarks.
  - Verify that progress updates render continuously on webOS.

  This phase gives the largest immediate UI responsiveness improvement with the least database risk.

  ### Phase 4 — Stream download and parse

  - Replace whole-response accumulation.
  - Parse incrementally from byte/text chunks.
  - Send batches as they become available.
  - Remove the full playlist String and full parsed list from memory.
  - Add backpressure so the network/parser cannot outrun SQLite.

  This is the phase that addresses peak memory most directly.

  ### Phase 5 — Refactor staging and reconciliation

  - Accept batches rather than a complete list.
  - Keep the transaction atomic initially.
  - Add explicit reconciliation sub-stages.
  - Report affected-row counts.
  - Make fallback behavior fail loudly in diagnostics and progress.
  - Preserve all existing identity and user-data behavior.

  ### Phase 6 — Cancellation and lifecycle handling

  - Cancel on playlist switch.
  - Cancel when the app is hidden if policy requires it.
  - Resume or restart safely after webOS relaunch.
  - Ensure incomplete imports leave the previous catalog intact.
  - Add cleanup for worker ports, HTTP clients, and transactions.

  ### Phase 7 — Hardware validation

  Run the benchmark on:

  - a representative webOS TV
  - a low-memory Android device
  - Windows development hardware

  Test at:

  - 100,000 items
  - 200,000 items
  - 500,000 items
  - cold import
  - warm refresh
  - malformed rows
  - cancellation during parsing
  - cancellation during staging
  - app background/relaunch during import

  Track:

  - UI frame responsiveness
  - peak RSS
  - download time
  - parse time
  - staging time
  - reconciliation time
  - index time
  - total time
  - number of rejected rows
  - fallback occurrences
  - database size

  ## Acceptance Criteria

  The implementation should not be considered complete until:

  - The UI remains responsive during parsing of a 500,000-item playlist.
  - Peak memory does not scale due to duplicate full-playlist representations.
  - No full List<ContentItem> exists for the entire playlist.
  - Progress reports parsing, staging, reconciliation, and indexing separately.
  - The UI does not claim the import is complete while indexing is still pending.
  - Cancellation rolls back the active import and preserves the last good catalog.
  - Progress continues to work when multiple callers observe the same import.
  - No background isolate depends on platform-channel SQLite behavior.
  - The staging fallback is observable and measured.
  - The benchmark passes on real webOS hardware, not only the desktop Dart VM.

  Recommended first slice: implement the progress contract and import coordinator, then move only parsing into a worker
  isolate while keeping the existing SQLite transaction path. After that is stable, change the source/parser to a bounded
  streaming pipeline. This keeps the first change small and reversible while directly addressing the UI freeze.