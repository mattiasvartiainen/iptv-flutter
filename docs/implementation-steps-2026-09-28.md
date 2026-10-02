**Recommended Approach**

Implement this as a sequence of independently testable vertical slices. Keep the current importer usable until the new catalog importer has passed the benchmark and recovery tests. The target schema described as v8 in the design is applied by migration v9 because v8 was already used for import-session tracking.

## Step 0 — Establish Baselines

**Goal:** Measure the current behavior before changing it.

- Extend the synthetic playlist generator with:
  - Live, movie, and series URLs.
  - Realistic group names.
  - Duplicate URLs.
  - Reordered playlists.
- Add benchmark scenarios:
  - Cold import.
  - Identical refresh.
  - 5% content churn.
  - Reorder-only refresh.
- Record:
  - Total import time.
  - Parse, staging, reconcile, and indexing timings.
  - Peak RSS.
  - Frame timing during import.
- Run the baseline on desktop, Android, and webOS if available.

Likely files:

- `test/benchmark/import_benchmark.dart`
- New or existing synthetic playlist tooling
- Import progress/diagnostics code

**Exit criteria:** Baseline numbers are recorded and reproducible.

***

## Step 1 — Add HTTP Refresh Short-Circuits (Deferred)

**Goal:** Avoid parsing when the provider confirms that nothing changed.

Implement this independently on the existing schema.

- Extend `HttpPlaylistSource` to support:
  - `ETag`.
  - `Last-Modified`.
  - `304 Not Modified`.
- Add playlist metadata columns:
  - `source_etag`
  - `source_last_modified`
  - `last_checked_at`
  - `last_changed_at`
  - `source_content_hash`
  - `source_content_length`
- Add automatic refresh cooldown:
  - Automatic refreshes respect `min_refresh_interval_s`.
  - Manual refresh always bypasses the cooldown.
- Replace the current total download timeout with:
  - Idle timeout between chunks.
  - Longer overall timeout.
- Record the short-circuit tier in import progress and metrics.

Tests:

- Conditional request sends the stored headers.
- `304` leaves catalog rows untouched.
- Cooldown skips automatic refreshes.
- Manual refresh bypasses cooldown.
- Idle timeout behaves correctly.

**Exit criteria:** Identical refreshes avoid parsing when possible and complete in approximately download time.

**Status:** Deferred by product decision on 2026-10-02. Proceed with Step 2; do not add
conditional request headers, body-hash short-circuits, or cooldown behavior yet.

***

## Step 2 — Add Import Session Tracking

**Goal:** Make imports observable and recoverable before introducing the new pipeline.

Add `import_sessions` while retaining the current import implementation.

Track:

- Start and finish timestamps.
- Current state.
- Short-circuit tier.
- Bytes received.
- Parsed/rejected/new/changed/moved/removed counts.
- Per-stage timings.
- Error details.

Update:

- `CatalogImportProgress`
- `CatalogImportCoordinator`
- `SqliteCatalogRepository`
- Storage migration tests

Also add startup cleanup for sessions left in `running` or `reconciling` states.

**Exit criteria:** Every import has a durable session record, including failures and cancellations.

**Status:** Implemented 2026-10-02. Migration v8 adds `import_sessions`; each actual
network import records lifecycle state, received bytes, parsed/rejected counts, available
stage timings and errors. Progress carries its session ID. Startup marks abandoned
`running`/`reconciling` sessions `aborted`; cancellation and failure receive terminal
states. New/changed/moved/removed counts remain nullable until the diff pipeline can
measure them. The app is unreleased, but the applied v8 migration remains immutable;
Step 5 adds the target catalog schema in v9.

***

## Step 3 — Introduce Shared Hash and Classification Utilities

**Goal:** Establish the new identity rules without changing the database yet.

Create focused utilities for:

- 64-bit hashing.
- `item_key = hash64(stream_url)`.
- Duplicate URL disambiguation.
- `content_hash`.
- `series_key`.
- Content classification.

Classification priority should follow the design:

1. Xtream URL path.
2. URL extension.
3. Group title hints.
4. `SxxEyy` title matching.
5. Live fallback.

Add unit tests for:

- Stable identity when title changes.
- Stable identity when order changes.
- Duplicate URL handling.
- Classification precedence.
- Hash input ordering.

Likely new files:

- `lib/services/catalog/catalog_hash.dart`
- `lib/services/catalog/catalog_classifier.dart`

**Exit criteria:** The identity rules are deterministic and independently tested.

**Status:** Implemented 2026-10-02. Added `catalog_hash.dart` with stable signed FNV-1a
64-bit item keys, duplicate occurrence disambiguation, typed ordered content fingerprints,
and playlist/group-scoped series keys. Added `catalog_classifier.dart` with the specified
Xtream path → extension → provider/group hint → episode-title → live priority. The active
legacy parser and database IDs are intentionally unchanged; the helpers are for the new
worker and v8 importer. `test/catalog_identity_test.dart` covers reference hash vectors,
identity stability, duplicate keys, typed/order-sensitive fingerprints, series scoping,
and classifier precedence.

***

## Step 4 — Build the Worker Parser Protocol

**Goal:** Move network, decoding, parsing, classification, and hashing off the UI isolate.

Implement a worker isolate with a small protocol:

- UI → worker: `start`
- Worker → UI: `headers`
- Worker → UI: `progress`
- Worker → UI: `keys`
- UI → worker: `want`
- Worker → UI: `rows`
- Worker → UI: `done`
- Worker → UI: `error`
- UI → worker: `cancel`

Start with a worker that parses batches and returns all rows. Then add the `keys`/`want` optimization.

Constraints:

- Stream UTF-8 decoding correctly.
- Bound the line buffer.
- Retain only one parsed batch.
- Use typed arrays or transferable data where supported.
- Keep the existing parser behavior covered by tests.

Tests:

- Chunk boundaries inside UTF-8 characters.
- Backpressure.
- Cancellation.
- Malformed line rejection.
- Worker error propagation.
- Batch ordering and completion.

**Exit criteria:** A 500k playlist can be parsed without retaining the complete playlist or blocking UI frames.

**Status:** Implemented 2026-10-02. Added `catalog_import_protocol.dart` and
`catalog_import_worker.dart`: the worker isolate owns HTTP fetch, UTF-8 streaming decode,
incremental body hashing, M3U parse, classification and row hashing. It transfers typed
key/hash/ordinal arrays, asks the coordinator which row indices are needed, transfers only
those rows, and waits for acknowledgement before advancing. Input is parsed in 16 KiB
slices, output batches cap at 1,000 rows, and the duplicate URL index uses compact typed
arrays. It reports response headers/progress, malformed records and errors, and supports
cancellation. `CatalogImportCoordinator.importPlaylist` exposes it through existing job
deduplication, lifecycle progress and cancellation. The current SQLite importer is
intentionally not switched to this protocol until the schema/importer steps; that avoids
mixing a transport rewrite with the current long-transaction reconciliation path.

Tests: `test/catalog_import_worker_test.dart`, coordinator integration coverage, and
`test/m3u_streaming_parser_test.dart` cover split UTF-8, ordered batches, acknowledgement
backpressure, cancellation, HTTP errors, malformed row counts and maximum line length.

***

## Step 5 — Add the Catalog Schema as a Separate Migration

**Goal:** Introduce the new storage model while preserving user data.

Add a new migration after the current schema version.

Create:

- `groups`
- `items`
- `series`
- `import_sessions`
- `import_rows`
- `import_seen`
- New `items_fts`
- New user-data keying tables
- `hidden_groups`

The new catalog should use:

- Integer row IDs.
- Integer `item_key`.
- Integer `content_hash`.
- Integer `series_key`.
- No foreign keys from user data into catalog rows.

Migration sequence:

1. Create replacement user tables.
2. Convert existing media IDs to `item_key` using `stream_url`.
3. Copy favorites, progress, and history.
4. Convert hidden categories to hidden groups.
5. Drop old catalog tables and old staging/search structures.
6. Create the target catalog tables.
7. Mark playlists for a cold re-import.
8. Trigger refresh on next startup.

Tests must verify:

- Favorites survive migration.
- Playback progress survives migration.
- Watch history survives migration.
- Hidden categories become hidden groups.
- Orphaned legacy rows are handled safely.
- Existing app startup works after migration.

**Exit criteria:** A migrated database contains no old catalog dependencies and user data remains usable.

**Status:** Implemented 2026-10-02 as `CatalogImportV9Migration`. Import-session tracking
already occupies migration v8, so the applied v8 migration remains immutable and the full
catalog schema is migration v9. It creates the target `groups`, `items`, `series_v8`,
`import_rows`, `import_seen`, external-content `items_fts`, HTTP metadata columns, and
key-based `favorites_v8`,
`playback_progress_v8`, `watch_history_v8`, and `hidden_groups_v8` tables. The old app code
still reads/writes legacy `series`, catalog and user tables, so those remain alongside the
new schema until Steps 6–9 switch the importer and query layer. The v8 user tables have no
foreign keys into catalog rows. Existing development databases at v8 automatically receive
the new v9 schema. Migration tests cover fresh creation, v8→v9 upgrade, FTS writes and
user-data independence from catalog deletes.

***

## Step 6 — Implement the Cold Catalog Import Path

**Goal:** Get the new schema working with the simplest import case first.

Create a new `CatalogImporter` instead of extending the existing large reconciliation method.

For a playlist with no existing `items`:

- Start an import session.
- Consume worker batches.
- Insert directly into `items` in short transactions.
- Build groups during import or final reconciliation.
- Build secondary indexes after bulk insertion where beneficial.
- Build derived series data.
- Queue or start search indexing.
- Mark the session complete.

Do not implement warm diffing yet.

Keep the old import path available behind a temporary feature flag or repository-level switch.

Tests:

- Cold import creates all expected items.
- Groups have correct counts and ordering.
- Series data is generated correctly.
- Rejected rows are counted.
- Partial failure does not replace the previous catalog.
- Catalog is browsable after import completion.

**Exit criteria:** Cold import works end-to-end on the target catalog schema.

**Status:** Implemented 2026-10-02. Added `CatalogImporter.importCold()` and an opt-in
`SqliteCatalogRepository(useCatalogImporterV9: true)` route; the legacy importer remains the
default until query/UI cutover. The v9 path consumes worker batches, inserts groups/items
in bounded short transactions, builds `series_v8` and group counts in a final transaction,
and populates external-content FTS per batch. Import sessions record progress/outcome. A
failed batch rolls back and removes all partial v9 rows; startup recovery performs the same
cleanup for abandoned sessions. Tests cover cold live/movie/series data, group order/counts,
FTS, repository opt-in, injected second-batch failure and recovery. Catalog screens still
read legacy tables until Step 9, so this opt-in is for validation/benchmarking, not yet the
default app path.

***

## Step 7 — Implement Warm Diffing and Reconciliation

**Goal:** Make refresh cost proportional to changes.

For every worker batch:

1. Look up existing `(item_key, content_hash, ord)` values.
2. Classify rows as:
   - New.
   - Changed.
   - Moved.
   - Same.
3. Request full rows only for new and changed items.
4. Store changed rows in `import_rows`.
5. Store seen keys and moved positions in `import_seen`.
6. Commit the batch transaction.

After parsing:

- Insert or update groups.
- Upsert changed items.
- Update `ord` for moved-only rows.
- Delete stale items not present in `import_seen`.
- Rebuild series only if episode data changed.
- Update counts only for touched groups.
- Queue FTS changes.

Important behavior:

- A title change must not change `item_key`.
- A reorder must only update `ord`.
- Unchanged rows must not be rewritten.
- User tables must not be cascade-deleted.

Tests:

- Identical playlist produces zero changed rows.
- 5% churn changes only the expected rows.
- Reorder changes only `ord`.
- Removed items disappear from the catalog.
- Favorites remain attached after title changes.
- Series rebuild is skipped when no episode changed.

**Exit criteria:** Warm imports satisfy the target benchmark and no Dart-loop fallback remains.

**Status:** Implemented 2026-10-02 in the opt-in v9 importer. Warm batches compare
`item_key`, `content_hash` and `ord`; full rows cross the isolate boundary only for new or
changed entries. Every valid key is recorded in `import_seen`, new/changed records in
`import_rows`, and moved-only rows carry their new ordinal. One final transaction upserts
changed rows/groups, updates moved ordinals, deletes stale rows only when no input rows
were rejected, maintains FTS/group counts and rebuilds series only when episode membership
changed. A failed/cancelled refresh discards scratch rows and leaves the previous catalog
and FTS intact; startup recovery clears abandoned warm scratch without touching live rows.
Tests cover no-op refresh, title change preserving row ID, reorder-only update, additions,
stale removals, FTS updates, failure preservation and recovery. The opt-in repository path
now invokes this warm path when v9 items already exist. 500k performance targets and device
benchmarks remain to be measured; passing functional tests does not yet establish the
15-second target.

Validation update: repository-level `networkOnly` refresh now routes a populated v9
catalog into the warm diff path. `test/catalog_importer_test.dart` verifies unchanged
refresh (0 new/changed/moved), changed title with stable row ID, reorder-only movement,
new/stale rows, FTS changes, failed-refresh preservation and startup recovery. Full suite:
110 passing. `flutter analyze` still reports the same 8 informational findings outside the
warm-import code. The 500k synthetic benchmark and TV/Android timing gates remain pending.

***

## Step 8 — Add Durability, Cancellation, and Recovery

**Goal:** Make the new importer safe under interruption.

Implement explicit state transitions:

- `running`
- `reconciling`
- `done`
- `unchanged`
- `failed`
- `cancelled`
- `aborted`

Add:

- Cleanup of abandoned `import_rows` and `import_seen`.
- Worker cancellation.
- Transaction boundaries around each batch.
- One final reconciliation transaction.
- Recovery after process termination.
- Preservation of the previous catalog until reconciliation succeeds.

Add concurrency tests:

- Favorite write during import.
- Playback progress write during import.
- Kill during staging.
- Kill during reconciliation.
- Cancel during download.
- Cancel while waiting for requested rows.
- SQL failure during a batch.

**Exit criteria:** The previous catalog remains browsable after any interruption or failed import.

**Status:** Implemented 2026-10-02 for the opt-in v9 path. Existing safeguards are now
covered at the actual importer boundary: warm scratch commits are short transactions,
catalog/FTS publication is one final transaction, startup recovery clears abandoned warm
scratch without deleting live items, and cold recovery removes partial cold state. Worker
cancellation now races an outstanding row-selection callback so `done` resolves without
waiting for that callback to return. Tests verify cancellation during a stalled download,
cancellation while row selection is pending, concurrent favorite and playback-progress
writes during a held warm download, a SQL error during final reconciliation preserving
items and FTS, recovery of interrupted cold/warm sessions, and the existing batch failure
case. These are injected failure/recovery tests rather than process-kill tests; a real
process termination test is not available inside the unit-test runner. The current v9 path
keeps the last catalog live until its reconciliation transaction commits.

***

## Step 9 — Switch Existing Flat Queries to v8

**Goal:** Make the rest of the application use the new catalog without changing navigation yet.

Update:

- `CatalogQueryService`
- `SqliteCatalogRepository`
- `CatalogItemSummary`
- `itemById`
- `queryItems`
- `homePreview`
- Series queries
- Favorite/progress/history joins

Initially preserve the flat screens:

- Live TV → all live items.
- Movies → all movies.
- Series → existing series flow.

This creates a compatibility checkpoint before introducing group-first navigation.

Tests:

- Existing catalog query tests pass against `items`.
- Details and playback still resolve stream URLs.
- Existing widget tests remain green.
- Favorite and progress lookups use `(playlist_id, item_key)`.

**Exit criteria:** The app can operate fully on the new catalog schema using the existing UI.

**Status:** Implemented 2026-10-02. The app bootstrap now enables the v9 importer for new
catalogs. `SqliteCatalogRepository` routes flat item pages, kind/group filters, FTS search,
home previews, series/seasons/episodes and selected-item lookup to `items`/`groups`/
`series_v8` when v9 rows exist, retaining the legacy query fallback during transition.
Integer SQLite ids are exposed as decimal strings to preserve the current Flutter screen
and playback contracts. Added v9 favorite, playback-progress, recent-history joins keyed by
`(playlist_id, item_key)`; title-change tests verify those joins still resolve the renamed
item. Playlist deletion explicitly clears v9 catalog, FTS, import-session and user-state
rows because those tables intentionally have no playlist/catalog foreign keys. Tests cover
the v9 query hierarchy, search, playback resolution and delete cleanup. Group-first UI
remains Step 11.

***

## Step 10 — Add Group Query APIs

**Goal:** Introduce group-first browsing at the data layer before changing screens.

Add query models:

- `GroupSummary`
- Updated `CatalogItemSummary`
- Updated `SeriesSummary`

Add query methods:

- `groups(...)`
- `itemsInGroup(...)`
- `seriesInGroup(...)`
- `seasons(seriesKey)`
- `episodes(seriesKey, seasonNumber)`
- Updated `search(...)`

Rules:

- Group queries are scoped by playlist and kind.
- Item queries are scoped by `group_id`.
- Series queries are scoped by group.
- Hidden groups are excluded.
- Counts come from `groups.item_count`.
- The synthetic “All channels” entry uses the existing kind-wide query.

Tests:

- Hidden groups are excluded.
- Group counts are correct.
- Group ordering works by playlist order and title.
- Paging uses group indexes.
- Series and episode queries use integer keys.

**Exit criteria:** The query layer supports the complete target information architecture.

***

## Step 11 — Implement Group-First Navigation

**Goal:** Change the UI in small screen-level slices.

Recommended order:

1. Live group list.
2. Live group items.
3. Movie group list.
4. Movie group items.
5. Series group list.
6. Series list within a group.
7. Seasons.
8. Episodes.
9. “All channels”.
10. Hidden group management.
11. Focus restoration.

Refactor:

- `catalog_screen.dart`
- New `group_list_screen.dart`
- New `group_items_screen.dart`
- `CatalogViewState`
- `AppScreen`
- App controller navigation

Use:

- A `PagedCollection<GroupSummary>`.
- Per-group item collections.
- A small LRU cache for recently visited groups.
- Group-scoped pagination.
- Remembered focus per group.

Widget tests:

- Opening each content kind shows groups.
- Opening a group shows only its items.
- Back navigation restores group focus.
- Hidden groups are absent.
- Series navigation remains usable with a remote.

**Exit criteria:** No normal browsing screen performs an unscoped full-kind query.

***

## Step 12 — Replace Search Indexing with External-Content FTS

**Goal:** Reduce duplicate title storage and make indexing incremental.

Implement:

- External-content `items_fts`.
- Queue entries containing:
  - Item ID.
  - Operation.
  - Old title.
  - Priority.
- Delete-and-insert behavior for changed titles.
- Batched cold rebuild by content kind.
- Live-first indexing priority.
- Search progress state in the UI.

Update search results to include:

- Group name.
- Content kind.
- Indexing status.

Tests:

- New items become searchable.
- Changed titles remove old matches.
- Deleted items disappear from search.
- Cold rebuild resumes after interruption.
- Live results become available before the full index completes.

**Exit criteria:** Warm refreshes index only changed rows and live search is available shortly after cold import.

***

## Step 13 — Hardware Tuning and Optional Isolation

Only start this after the functional redesign is stable.

Measure on webOS and Android:

- WAL versus rollback journal.
- Batch sizes of 1,000, 2,000, and 5,000.
- SQLite version and parameter limit.
- UI frame timing.
- Peak memory.
- FTS tokenizer quality.

Then decide:

- Whether to bundle SQLite.
- Whether to use `unicode61` or `trigram`.
- Whether to add a raw playlist cache.
- Whether SQL work must move to a database isolate.

The database isolate should remain optional. The worker/import protocol should make it possible to move the differ/stager later without redesigning the parser.

***

## Suggested Milestones

### Milestone A — Low-risk performance wins

Steps 0–2.

- No schema replacement.
- HTTP short-circuits.
- Cooldown.
- Import observability.
- Easy rollback.

### Milestone B — New storage and import engine

Steps 3–9.

- New identity model.
- v8 migration.
- Worker parser.
- Cold import.
- Warm diffing.
- Recovery.
- Existing UI running on v8.

### Milestone C — New browsing experience

Steps 10–12.

- Group query APIs.
- Group-first navigation.
- Hidden groups.
- Incremental search.

### Milestone D — Device optimization

Step 13.

- Hardware measurements.
- SQLite/WAL/batch tuning.
- Optional database isolate.

## Important Guardrails

- Do not remove the current importer until the v8 cold and warm paths pass all failure tests.
- Do not combine schema migration, importer replacement, and UI navigation in one change.
- Keep every migration reversible during development through database backups or fixture snapshots.
- Make benchmark scenarios part of CI or at least a repeatable local command.
- Treat the acceptance criteria in the redesign document as gates between milestones, not as final-only tests.
- Keep the existing flat browsing mode temporarily available as a fallback while group-first screens are introduced.