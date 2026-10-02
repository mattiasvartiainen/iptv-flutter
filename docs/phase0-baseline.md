# Phase 0 Baseline

This document records measurements for the pre-redesign catalog import pipeline.
The benchmark deliberately uses the real repository and database adapter rather
than a parser-only microbenchmark.

## Reproducing the benchmark

Run the complete scenario set with a 500,000-item fixture:

```text
flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=500000 --dart-define=BENCHMARK_SCENARIO=all --dart-define=BENCHMARK_OUT=build/phase0-baseline.json
```

Use `BENCHMARK_NO_NETWORK=true` to isolate parsing and database work. Omit it to
include the loopback HTTP download path. The benchmark reports:

- cold import;
- identical refresh;
- 5% churn refresh; and
- reorder-only refresh.

Each run includes wall-clock timings, current import stage timings, RSS before
and after the run, peak RSS delta, and event-loop delay as a proxy for frame
responsiveness. The JSON report is intended to be attached to the performance
change or copied into the table below.

## Environment

| Date | Device/runtime | Flutter | Scenario | Network | Report |
| --- | --- | --- | --- | --- | --- |
| 2026-09-28 | Windows development machine | record with command output | smoke, 2,000 items | disabled | `build/phase0-smoke.json` |
| 2026-09-28 | Windows development machine | current local Flutter runtime | cold, 500,000 items | disabled | captured in benchmark output |
| pending | Android target device | pending | 500,000 items | pending | pending |
| pending | webOS target TV | pending | 500,000 items | pending | pending |

The 2,000-item smoke run validates the harness only; it is not a replacement
for the 500,000-item baseline or the on-device measurements.

The completed 500,000-item cold run measured approximately 72.8 seconds total,
including 66.9 seconds of database import and 53.8 seconds of search-index
draining. Peak RSS was approximately 1.54 GB, or 1.18 GB above the process RSS
at the start of that run. The event-loop probe recorded a maximum delay of
approximately 786 ms. These figures are desktop measurements for the current
implementation, not target limits.

The warm portion of the same run was stopped after the existing identical-refresh
path remained in episode reconciliation for several minutes. That behavior is
itself a useful baseline finding; the individual warm scenario measurements will
be collected after the benchmark is split into separately seeded runs or after
the current reconciliation path is instrumented further.

## Interpretation

The current implementation performs all database import work synchronously on
the UI isolate. The event-loop delay measurement is therefore expected to show
large pauses during the import stages. Later redesign phases should be compared
against the same scenario definitions and report fields.
