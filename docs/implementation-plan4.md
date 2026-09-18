We should design around webOS and Android first, treating Windows/Linux as development and benchmarking conveniences rather
  than architectural constraints.

  The implementation target will be:

  worker isolate:
    download
    incremental parse
    bounded batch production

  UI isolate:
    short staging transactions
    progress persistence
    final SQLite reconciliation transaction

  Key decisions for webOS/Android:

  - Do not depend on SQLite access from a background isolate.
  - Keep database ownership on the UI isolate.
  - Never hold a database transaction open during network download.
  - Commit staging batches independently.
  - Use an import_id to isolate attempts and support cleanup.
  - Keep the last successful catalog visible until final reconciliation commits.
  - Recover or discard interrupted staging sessions on startup.
  - Preserve bounded worker-to-UI backpressure.
  - Measure frame responsiveness and peak memory on real hardware.

  I would implement it in this order:

  1. Add the import-session migration and model.
  2. Add repository APIs for starting, staging, completing, and discarding imports.
  3. Move streaming batch writes into short transactions.
  4. Add durable progress/checkpoints.
  5. Refactor reconciliation to consume only one import_id.
  6. Add crash recovery and cancellation cleanup.
  7. Run webOS/Android-sized benchmarks and tune batch sizes.

  Windows/Linux will use the same path initially, which keeps behavior consistent. Any FFI-specific optimization can come later
  without influencing the primary architecture.