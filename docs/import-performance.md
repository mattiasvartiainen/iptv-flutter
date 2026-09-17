# Playlist Import Performance

This document records how playlist import performs, why it used to be slow, what was
changed, and what is worth attacking next. It covers both the historical work
(captured previously in [`improvements-1.md`](improvements-1.md)) and the most recent
round of measurement-driven optimisation.

It is the reference to read before touching
`lib/services/catalog/sqlite_catalog_repository.dart`,
`lib/services/catalog/m3u_parser.dart`, or `lib/services/storage/storage_migrations.dart`.

---

## 1. Why this matters: the footprint constraint

The app is not a desktop application that happens to run on a TV. It targets:

- **LG webOS TVs** — a few hundred MB of usable RAM for an app, a slow ARM CPU, and
  eMMC storage with poor random-write performance. The OS will kill an app that grows
  its resident set too far, and there is no swap worth relying on.
- **Android phones (future)** — background/foreground transitions, aggressive low-memory
  killing, and users on battery.
- **Windows/Linux desktop** — only used for development and as a convenience target.

A realistic provider playlist is **100,000–500,000 entries**. That means every decision
in the import pipeline must be judged against two questions:

1. **Does peak memory scale with playlist size?** Anything that holds the whole playlist
   in a second or third representation at the same time is a problem, not an optimisation.
2. **Does per-item cost stay constant?** Anything that is O(n) per item — a full table
   scan, an unindexed lookup, a statement round trip — becomes O(n²) across the import
   and will look like a hang on a TV even if it is merely "slow" on a developer laptop.

Wall-clock time is the symptom users report. Memory and per-item cost are the causes.
**Optimisations that trade memory for speed are usually the wrong trade for this product.**

---

## 2. The benchmark tool

Performance work here is measurement-driven. There are three pieces.

### 2.1 `tool/synthetic_playlist.dart`

Pure Dart (no Flutter dependency). Generates a deterministic synthetic M3U:

```dart
generateSyntheticPlaylist({itemCount, seed, liveFraction, seriesFraction, categoryCount})
churnSyntheticPlaylist(original, {churnFraction})
```

It deliberately mixes live channels, movies, and `S01E01`-style series episodes so the
category / series / season / episode reconcile paths are all exercised — not just a flat
`media_items` table.

`churnSyntheticPlaylist` appends `[updated]` to a fraction of `#EXTINF` titles to simulate
a refresh where some rows changed. Note the known pessimism: title feeds every identity
strategy, so a churned row reconciles as delete+insert rather than update-in-place. That
is an accepted worst-case proxy, not a bug.

### 2.2 `tool/generate_synthetic_playlist.dart`

Standalone CLI for producing a playlist file to test against by hand:

```powershell
dart run tool/generate_synthetic_playlist.dart --count=500000 --out=big.m3u
```

### 2.3 `tool/benchmark_import.dart` — the harness

`runBenchmark(List<String> args)`:

1. Generates the synthetic playlist.
2. Starts a real loopback `HttpServer` serving it, so the real `HttpPlaylistSource`
   streaming path is exercised rather than a fake.
3. Runs a real `SqliteCatalogRepository.load()` against a temporary SQLite file through
   `SqfliteDatabaseAdapter`.
4. Explicitly drains the search index via `processSearchIndexQueue()` and times it
   separately (the repository is constructed with `autoStartSearchIndexWorker: false`
   so the measurement is deterministic).
5. Reports wall clock split into download+parse / DB import / search index, plus
   `ProcessInfo.currentRss` and `maxRss`.
6. With `--refresh`, runs a second `load()` against a 5%-churned copy to benchmark the
   warm-refresh path.
7. Cleans up its database file (plus `-wal` / `-shm` / `-journal`) unless `--keep-db`.

### 2.4 How to run it

> **This file cannot be run with plain `dart run` or `flutter pub run`.** It transitively
> imports `package:flutter/foundation.dart`, which fails to resolve `dart:ui` outside a
> Flutter-aware VM (it surfaces as confusing `Offset`/`PointerDeviceKind` errors deep
> inside `flutter/gestures`). The `main()` in the tool just delegates to `runBenchmark()`.

The real entry point is **`test/benchmark/import_benchmark.dart`**, deliberately named
without a `_test.dart` suffix so a normal `flutter test` does not pick it up.

```powershell
flutter test test/benchmark/import_benchmark.dart `
  --dart-define=BENCHMARK_COUNT=200000 `
  --dart-define=BENCHMARK_REFRESH=true
```

Also supported: `BENCHMARK_KEEP_DB`, `BENCHMARK_NO_NETWORK`, `BENCHMARK_SEED`.

### 2.5 Per-stage attribution

Two static hooks on `SqliteCatalogRepository` make the import observable. They are
`null` by default and cost nothing in production:

```dart
SqliteCatalogRepository.onImportStageTiming        // (stage name, elapsed)
SqliteCatalogRepository.onStagingReconcileFallback // (error) — fast path was abandoned
```

The benchmark wires both. Output looks like:

```
[Cold import] stage-rows: 9927 ms
[Cold import] dedupe-resolved-id: 754 ms
[Cold import] upsert-media-items: 10931 ms
...
```

**`onStagingReconcileFallback` is the first thing to check when import timings regress.**
See §6.3 for why.

### 2.6 Reading the results honestly

- The benchmark runs under the **debug/JIT test VM on a developer machine**. It is a
  before/after reference point, not a prediction of TV performance. Expect a TV to be
  several times slower.
- **Run-to-run variance on this harness is significant** (individual stages have been
  observed to vary by 2x between identical runs). Only trust differences that are large
  and reproducible. Do not tune against a 10% delta.
- Killing a run mid-flight leaves orphaned `dart.exe` / `flutter_tester.exe` processes
  holding `build\native_assets\windows\sqlite3.dll`, and the next `flutter test` crashes
  with `PathExistsException`. Recovery:

  ```powershell
  Get-Process flutter_tester,dart -ErrorAction SilentlyContinue | Stop-Process -Force
  Remove-Item -Recurse -Force build\native_assets
  ```

---

## 3. History: how the pipeline got here

### 3.1 The original design and its problems

The first implementation loaded the entire catalog into memory in `AppController`,
deleted and reinserted every catalog row on each refresh, and rebuilt the entire FTS
index per playlist. Refreshing cascade-deleted favorites, watch history and playback
progress for items that still existed.

The seven-step plan in [`improvements-1.md`](improvements-1.md) addressed this:

| Step | Outcome |
| --- | --- |
| 1 | `catalog_query.dart` — paginated query types; migration v5 added `import_staging_items`, `search_index_queue`, and query-shaped indexes. |
| 2 | `CatalogQueryService` — SQL-backed paging and FTS search instead of in-memory lists. |
| 3 | `CatalogViewState` — the controller owns only the visible page window, never the full catalog. |
| 5 | Incremental FTS via `search_index_queue` instead of a full rebuild per import. |
| 6 (partial) | `_inFlightLoads` dedupes concurrent `load()` calls for the same playlist, removing real "database has been locked" errors. |

Alongside that, reconciliation was changed from delete-and-reinsert to a diff
(`_reconcilePlaylistContent`), which stopped destroying user data on every refresh,
and identity moved to SHA-256-based `strongStableId` with backward-compatible fallbacks.

### 3.2 "Path A" quick wins

- `M3uParser` stopped recompiling its attribute `RegExp` on every `#EXTINF` line.
- `HttpPlaylistSource` switched to `BytesBuilder(copy: false)`.
- `SettingsRepository.resolvePlaylistUrl()` stopped doing a redundant second DB query
  and secure-storage read per refresh.
- The single unbounded `Batch` covering an entire playlist was chunked
  (`_importBatchChunkSize = 2000`) to bound peak memory and platform-channel message size.
- A latent bug was fixed where stale-row deletion built one `DELETE ... WHERE id IN (?…)`
  with one placeholder per stale id, which could exceed SQLite's bound-parameter limit.
- Verbose progress UI throttled `notifyListeners()` to at most once per 200 ms.

### 3.3 "Path B" — the set-based staging reconcile

The per-item Dart loop was replaced (as the primary path) by
`_reconcileViaStagingSql`: parsed rows are streamed into `import_staging_items`, then
every active table is reconciled with whole-set SQL — `INSERT … SELECT … ON CONFLICT DO
UPDATE` for upserts and anti-join `DELETE`s for stale rows. SQLite's own indexes do the
diff instead of a Dart-side full-table `Set`/`Map` preload.

A notable finding from that round: an early episode-upsert implementation using a CTE
was pathologically slow (a 50k import spent ~110 s purely on episodes). It was replaced
by deriving episode ids from `(season_id, episode_number)` and doing
delete-this-playlist's-episodes + one grouped `INSERT OR IGNORE`. This is safe because
`episodes` is derived navigation data with no user-data children.

---

## 4. The problem this round was asked to solve

Reported symptom on a real ~500,000-item playlist:

1. ~8 seconds of "something happening" with no feedback.
2. ~1 minute of "importing items".
3. **A couple more minutes of something else**, after the UI said it was done.

### 4.1 Baseline measurement

200,000 items, developer machine, before this round:

| | Total | download+parse | DB import | Peak RSS |
| --- | --- | --- | --- | --- |
| Cold import | 92.8 s | 2.2 s | 89.6 s | 533 MB |
| Warm refresh (5% churn) | 109.2 s | 6.7 s | 101.8 s | 834 MB |

Two things stand out. The DB import dominates completely, and a **warm refresh was more
expensive than a cold import** — the opposite of what users expect.

The search-index phase was not measured at all, because it is fire-and-forget after
`load()` returns. That omission was hiding the worst problem.

---

## 5. Root causes found

### 5.1 Phase 3 — quadratic FTS maintenance (the worst)

`media_items_fts` is an FTS5 table declared with `media_item_id UNINDEXED`. Index
maintenance deleted rows with:

```sql
DELETE FROM media_items_fts WHERE media_item_id = ?
```

An `UNINDEXED` column has no index by definition, so **each of those statements scans the
entire FTS content table**. Across 500,000 queued rows that is quadratic. On top of that,
the drain issued three separate statements per row in batches of 250, i.e. ~1.5 million
statement round trips for a full playlist.

This is what the user saw as "a couple more minutes" — and it would not have finished in
any reasonable time at 500k.

### 5.2 Phase 2 — avoidable per-row work in the import

- **Ten secondary indexes on `import_staging_items`** that no reconcile statement ever
  chose (the reconcile statements are full-set scans and group-bys). Each one cost a
  b-tree insert per staged row: ~5 million wasted b-tree inserts for a 500k playlist.
- **One `INSERT` statement per staged row** through `Batch`, so per-statement overhead
  dominated the actual write.
- **A three-probe identity resolve** (`id` → `provider_item_hash` → `stream_url`+`title`+
  `source_index`) executed even on a first import, where by definition nothing exists.
- **`GROUP BY resolved_media_id` with 17 `MAX()` aggregates** on the `media_items` upsert,
  forcing a full sort of the catalog even though the dedupe passes already guarantee
  uniqueness.
- **Stale-row anti-joins** run on a cold import, where nothing can be stale.
- `media_signature` written into staging on every row and indexed, but never read.
- Every imported row queued for reindexing even when nothing about it had changed.

### 5.3 Phase 1 — parser memory and per-item allocation

- `LineSplitter().convert(text)` materialised a `List<String>` of every line — roughly
  1 million line strings held alive simultaneously, on top of the source text and the
  parsed items.
- `metadata: Map.unmodifiable(attributes)` retained **every** provider attribute on every
  `ContentItem`. Only four keys (`tvg-id`, `tvg-name`, `tvg-chno`, `xui-id`) are ever read.
- Content-type classification concatenated four strings and lowercased the result to
  throw it away immediately, per entry.
- `Uri.tryParse` ran on every stream URL, including the overwhelming majority that are
  already absolute.
- `List.unmodifiable(items)` copied the whole item list at the end.

### 5.4 A hidden landmine: silent fallback to the slowest possible path

`_reconcileResiliently` caught any failure from the set-based path and fell straight back
to **one `SAVEPOINT` per item**. At 200k items that is roughly 50x slower and is
indistinguishable from a hang.

This is not hypothetical: during this round a single missing column in a recreated
staging table made every import throw, and the observable symptom was "the import got 50x
slower" with no error anywhere. It cost about an hour to diagnose.

---

## 6. Changes made

All schema changes are in migration **v7 — `ImportPerformanceV7Migration`**
(`schema_version` is now `7`).

### 6.1 Search index (fixes §5.1)

- `media_items_fts` is **rebuilt so its `rowid` equals `media_items.rowid`**. All index
  maintenance is now an integer rowid lookup instead of a full scan.
- `search_index_queue` is recreated with a `media_rowid INTEGER` column (captured while a
  stale row still exists, so its index entry can be removed after the row is gone) and a
  widened `operation` CHECK: `('insert', 'upsert', 'delete')`.
- The new **`insert` operation** means "nothing is indexed under this rowid yet, skip the
  removal half of a reindex". It is queued only when the import is cold **and** the FTS
  table is empty — the emptiness check guards against entries orphaned by a kill between a
  catalog delete and the index drain, whose rowids would otherwise be reused and collide.
- The FTS table **no longer indexes `sort_title`**. It was a byte-for-byte duplicate of
  `title` after case folding, and the `unicode61` tokenizer case-folds anyway.
- The drain is now **set-based chunked SQL** (`_chunked` / `_placeholders`,
  `_deleteChunkSize = 500`) rather than three statements per row, and
  `searchIndexBatchSize` went from 250 to 2000 — the batch size now bounds the transaction,
  not the statement count.
- **Only genuinely changed rows are queued.** The upsert-queueing statement runs *before*
  the `media_items` upsert, while the previous `title` and `group_title` are still readable,
  and enqueues a row only if it is new or its indexed text differs.
- `AppController.initialize()` calls `SqliteCatalogRepository.resumeSearchIndexing()`
  (unawaited). This is required, not optional: v7 drops the FTS table and re-queues
  everything, so without it existing users would have no search until their next refresh.

### 6.2 Import (fixes §5.2)

- v7 drops nine `idx_staging_*` indexes, plus `idx_media_playlist_type` (a prefix of
  `idx_media_playlist_type_sort`) and `idx_media_playlist_signature` (whose prefix is
  already covered by `UNIQUE (playlist_id, stream_url, title)`).
- `import_staging_items` is recreated without the unused `media_signature` column.
- **Staged rows go in via multi-row `INSERT … VALUES (…),(…)`**
  (`_stagingRowsPerStatement = 40`; with 24 columns that stays under the 999-parameter
  limit of older SQLite builds, which some TV platforms still ship).
- **Identity resolve reduced from three probes to two** — the primary key, then the
  `UNIQUE (playlist_id, stream_url, title)` index. It **no longer requires `source_index`
  to match**, which is a behavioural improvement as well as a speed one: a channel that
  merely moves position in the playlist now keeps its id, and therefore keeps its
  favorites, watch history and playback progress.
- On a **cold import** the resolve pass is skipped entirely — `resolved_media_id` is
  staged as the item's own id from Dart — and so are the stale-row deletes and the
  unchanged-row probe.
- The `media_items` upsert dropped its `GROUP BY` (the dedupe passes already guarantee
  uniqueness) and gained a `NOT EXISTS` **skip-unchanged predicate** on warm refresh, so a
  refresh only rewrites rows that actually differ.
- `PRAGMA synchronous = NORMAL` and a bounded `cache_size = -8000` (8 MiB) are set in
  `SqfliteDatabaseAdapter.onConfigure`. The catalog is a rebuildable cache, so trading the
  last few transactions on power loss for far fewer fsyncs is the right call; the cache
  bound exists so an import cannot push a memory-constrained TV into swap.

> **WAL was tested and deliberately rejected.** Enabling `journal_mode = WAL` produced a
> roughly **10x regression**. A playlist import is one very large write transaction; the
> WAL grows far past the page cache and cannot be checkpointed while the transaction is
> open, so every page read goes through the wal-index. This is recorded here because WAL
> is the reflexive "obvious" SQLite optimisation and someone will try it again.

### 6.3 Resilience (fixes §5.4)

- `_reconcileResiliently` now has **three tiers**: set-based SQL → whole-playlist Dart
  loop → per-item savepoint isolation. The middle tier means a generic SQL failure no
  longer costs per-item isolation; only a genuinely bad row does.
- `SqliteCatalogRepository.onStagingReconcileFallback` makes the degradation observable.
- A regression test, *"a cold import and a refresh both reconcile via the set-based SQL
  path"* in `test/storage_pipeline_test.dart`, asserts the fast path is actually taken for
  both a cold import and a refresh. Correctness alone would not have caught this.

### 6.4 Parser (fixes §5.3)

`lib/services/catalog/m3u_parser.dart`:

- Lines are **scanned by index over the source string** instead of split into a list.
- Only the four attributes anything reads are retained in `ContentItem.metadata`.
- Content-type hints are tested piece by piece rather than concatenated into a throwaway
  lowercased string. The hints are whole words, so they cannot straddle two pieces —
  behaviour is unchanged.
- A cheap `scheme:` code-unit probe (`_hasScheme`) skips a full `Uri` parse for absolute
  URLs, which is nearly all of them.
- `List.unmodifiable` / `Map.unmodifiable` copies removed.

---

## 7. Current state

200,000 items, same machine and same harness as the baseline in §4.1:

| | Before | After | Change |
| --- | --- | --- | --- |
| **Cold import** total | 92.8 s | **33.4 s** | 2.8x faster |
| — download + parse | 2.2 s | 2.9 s | ~unchanged |
| — DB import | 89.6 s | 29.4 s | 3.0x faster |
| — search index (background) | not measured (quadratic) | 19.4 s | bounded |
| — peak RSS | 533 MB | **433 MB** | −19% |
| **Warm refresh (5% churn)** total | 109.2 s | **37.3 s** | 2.9x faster |
| — DB import | 101.8 s | 34.7 s | 2.9x faster |
| — search index (background) | full catalog reindex | 2.4 s | — |
| — rows reindexed | all 200,000 | **19,926** | 10x less work |
| — peak RSS | 834 MB | **534 MB** | −36% |

The whole test suite (73 tests) passes, and `flutter analyze` reports only four
pre-existing informational issues unrelated to this work.

### 7.1 Where the time goes now

Cold import, 200k, per stage:

| Stage | Time | Note |
| --- | --- | --- |
| `stage-rows` | ~9.9 s | Multi-row inserts into staging. |
| `upsert-media-items` | ~10.9 s | Six b-trees maintained per row on `media_items`. |
| `upsert-episodes` | ~3.1 s | Delete-and-rebuild of derived navigation data. |
| `queue-search-upserts` | ~2.2 s | |
| dedupe + categories + series + seasons | ~2.6 s | |
| search index (background) | ~19.4 s | FTS tokenisation, ~100 µs/row. |

Warm refresh adds `resolve-identity` (~4 s) and `delete-stale` (~6 s), and
`upsert-media-items` drops to ~4.9 s because unchanged rows are skipped.

---

## 8. Future work

### 8.1 Move parsing off the UI isolate (recommended, not yet done)

This is the main remaining user-visible problem and the only significant item from the
original architecture guidance that is still open.

**Current behaviour.** The download is asynchronous, but parsing runs synchronously on the
UI isolate immediately afterwards:

```dart
final parsed = const M3uParser().parse(text, sourceUrl: playlistUrl);
```

At 200k items that is roughly 3 s of a completely frozen UI; at 500k, around 7 s. During
that window the app cannot render frames, cannot animate a progress indicator, and —
critically on a TV — **cannot respond to remote-control input**. The user is likely to
conclude the app has crashed and start pressing buttons.

`docs/architecture.md` already calls for running fetch and parse off the UI isolate. It
was never implemented.

**Why it is not a one-liner.** The naive fix is `Isolate.run(() => parser.parse(text))`.
That fails the footprint test in §1: the result is a `List<ContentItem>` of up to 500,000
objects, and returning it over a port **deep-copies every one of them**. Peak memory
roughly doubles at exactly the moment it is already highest. On a TV that is a far worse
outcome than a frozen UI.

Options worth evaluating, in rough order of preference:

1. **Move download + parse + staging-insert all into the background isolate.** The isolate
   never returns the items — it writes them straight into `import_staging_items` and
   returns only a count. Peak memory drops (the item list never has to coexist with
   anything on the UI isolate) *and* the UI stays responsive. The blocker is database
   access: `sqflite_common_ffi` can open a database from any isolate, but the
   platform-channel `sqflite` used on webOS and Android cannot be driven from a background
   isolate. This needs a spike on real webOS hardware and may need a per-platform strategy.

2. **Stream results back in bounded chunks.** Parse in the isolate and send batches of a
   few thousand items over the port, staging each batch as it arrives. Memory stays
   bounded because only one batch is in flight, and the copy cost is paid incrementally.
   Simpler than option 1 and platform-agnostic, but pays the port-copy cost for every item.

3. **Yield to the event loop periodically during parse.** Make `parse` async and
   `await` a zero-duration future every N items so the UI can render and handle input.
   Cheapest to implement and zero memory cost, but note the known hazard: `testWidgets`
   runs in a `FakeAsync` zone where a real `Future.delayed`/`Timer` never fires unless the
   test pumps the clock. The parse path *is* exercised by widget tests, so this would need
   the tests adjusted, and getting it wrong causes a multi-minute hang rather than a
   failure.

4. **Transfer the parsed data as a compact binary buffer** (`TransferableTypedData`,
   which moves rather than copies). Fastest and lowest-memory in principle, but requires
   hand-written serialisation of `ContentItem` and is hard to justify unless 1–3 all fail.

Whichever is chosen, it should be paired with **cancellation**: a user who navigates away
or switches playlists mid-import should stop the work, not wait for it.

### 8.2 Other candidates, roughly by value

- **Never hold the full `List<ContentItem>` in memory.** Today parse produces the whole
  list and `_reconcileViaStagingSql` consumes it. Changing the reconcile to accept a
  `Stream`/`Iterable` would let parsing and staging be pipelined, cutting peak memory
  substantially. This composes naturally with §8.1 option 1 or 2.
- **Reduce the b-tree count on `media_items`.** The upsert maintains six indexes per row
  and is the single most expensive stage. Audit which of `idx_media_playlist_sort`,
  `idx_media_playlist_group_sort`, `idx_media_playlist_type_sort`,
  `idx_media_playlist_source_index` and `idx_media_playlist_provider_hash` are genuinely
  used by the query layer, and consider building the purely-browse indexes *after* the
  bulk insert rather than maintaining them during it.
- **Shrink the row.** `media_items.id` is a 69-character SHA-256 string used as the primary
  key and repeated in `episodes`, `favorites`, `watch_history`, `playback_progress` and the
  FTS table. `provider_item_hash` stores `streamUrl|title|group` in full and is also
  indexed. Both are significant DB size and write-amplification costs on eMMC. A compact
  64-bit identifier would help, but this is a migration with real user-data risk
  (favorites must survive) and should not be attempted casually.
- **Cheaper hashing.** The parser computes one SHA-256 per item. A fast non-cryptographic
  64-bit hash is collision-safe at this scale, but see the identity-migration caveat above.
- **Incremental / resumable imports.** A 500k import is currently one long transaction. If
  it is interrupted, everything is rolled back. Committing per staged chunk with a resume
  marker would make a TV that gets backgrounded mid-import far less painful, at the cost
  of a more complicated correctness story.
- **Report progress during the index phase.** The search-index drain is now bounded and
  incremental, but it is still invisible to the user. Surfacing it would explain why the
  device is busy after the import "finishes".
- **Measure on real hardware.** Everything above is calibrated on a desktop JIT VM. The
  relative ordering of costs on an ARM TV with eMMC storage will differ — I/O-bound stages
  will hurt more, CPU-bound stages proportionally less. A webOS benchmark run should
  happen before the next round of tuning.

---

## 9. Rules of thumb for future changes here

- **Measure first, with `onImportStageTiming`.** Intuition about which SQL statement is
  expensive has been wrong more than once in this codebase.
- **Check `onStagingReconcileFallback` before investigating anything else** when import
  time regresses. A silent drop to the Dart-loop path looks exactly like "SQLite got
  slower".
- **Never add an index without identifying the query that uses it.** Unused indexes on the
  staging table were one of the largest costs found this round.
- **Treat a correctness-preserving fallback as a performance bug when it triggers.** It is
  not a safety net if nobody can tell it fired.
- **Reject optimisations that scale memory with playlist size**, even fast ones. See §1.
- **Re-run the benchmark at 200k before and after**, and ignore differences under ~20%;
  harness variance is real.
