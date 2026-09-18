 We addressed the largest UI-isolate problem, but there are still important performance considerations.

  Addressed

  - Downloading and parsing for HttpPlaylistSource run through the worker isolate.
  - Parsing emits bounded batches with backpressure.
  - Standard imports no longer build a complete parsed playlist list before staging.
  - SQLite staging and reconciliation behavior remains functionally compatible.

  Still on the UI isolate

  - SQLite staging writes.
  - Set-based reconciliation SQL.
  - Category/series/episode reconciliation.
  - Search-index draining.
  - Conversion of worker messages into ContentItem objects.

  Those database calls are asynchronous at the Dart API level, but the underlying SQLite work can still consume CPU and I/O time on
  the UI isolate. On webOS and Android this is difficult to move because platform-channel SQLite access may not work from a
  background isolate.

  Important remaining issue

  The current implementation opens the SQLite transaction before consuming the network stream. That means a slow provider can keep a
  database transaction open while downloading and parsing. The next design should separate:

  download + parse
    → staging batches
    → short/focused reconciliation transaction

  A practical approach is to populate import_staging_items in bounded batch transactions, then run the catalog reconciliation in one
  final transaction. This improves lifecycle behavior but requires cleanup/resume handling for interrupted staging.

  Other remaining work

  - Move or incrementally report search-index processing; it currently remains fire-and-forget after import.
  - Add true cancellation that stops the worker, network stream, and database work.
  - Avoid accumulating all batches for legacy non-streaming PlaylistSource implementations.
  - Benchmark UI frame times, peak memory, and import duration on real webOS hardware.
  - Investigate reconciliation indexes and SQL stages using the existing import timing hooks.
  - Consider resumable imports for app backgrounding or process termination.

  So the current implementation is a meaningful first performance improvement, but it is not yet a fully backgrounded import
  pipeline.