# Aicore benchmark — run 2026-10-12 (synthetic I/O profile)

## Headline (128 players)

| Workload | Metric | Aicore | QBox model* | Reduction |
|---|---|---|---|---|
| Vitals-tick replay, 30 sim-min | DB write bytes | 113.6 KB | 5,209.2 KB | **97.8%** |
| Vitals-tick replay, 30 sim-min | DB queries | 384 | 7,680 | **95.0%** |
| Vitals-tick replay, 30 sim-min | Net event payload | 255.0 KB | 5,910.0 KB | **95.7%** |
| Save burst (35% players dirty) | DB write bytes | 3.8 KB | 86.5 KB | **95.6%** |

\* QBox figures are **modeled** from the hot spots documented in
`docs/AUDIT-qbox.md` (full-row `UPDATE` per metadata write; full PlayerData
push per change; vitals tick doing 2 writes + 2 pushes per player per minute;
save loop writing every player regardless of changes). Aicore figures run the
**real** `resources/aicore/server/player.lua` (shared-metatable objects, dirty
tracking, differential sync events) and the **real**
`resources/aicore/server/storage.lua` (`savePartial` — dirty columns only).

## What's real vs modeled

- **Real:** the exact Lua code paths that build the SQL (which columns, which
  JSON blobs, per-player vs coalesced), the dirty-flag behavior, and the
  differential client events. These come from executing the actual core files
  under stubbed FiveM globals (`MySQL`, `json`, `TriggerClientEvent`,
  `exports`, `CreateThread`/`Wait`, `Config` loaded from the real
  `shared/config.lua`).
- **Modeled:** byte sizes of JSON blobs use a compact encoder; the QBox side
  is a faithful replay of the audit's documented behavior, not executed QBox
  code. Representative player payloads are identical on both sides (fair).
- **Not measured here:** real MySQL latency/round-trips, network stack cost,
  FiveM server tick cost, join latency, idle `resmon`. Those still need a live
  FiveM test server — this harness doesn't replace that step, it just means
  the perf claim now has numbers instead of only an audit.

## Workloads

1. **Vitals-tick replay** — the audit's hot spot #1. 128 players × 30
   simulated minutes, each player receiving 2 metadata writes/minute
   (hunger + thirst tick). Aicore coalesces into the real 10-minute save
   interval writing only the dirty `metadata` column; QBox does 2 full-row
   writes + 2 full PlayerData pushes per player per minute.
2. **Save burst** — one save-interval pass over 128 players with 35% dirty
   (~2 fields each, e.g. paycheck `bank` touch + `position`). Aicore writes
   only dirty players, dirty columns; the QBox model writes the full row for
   all 128 players.

## Reproducing

```
cd bench && python3 run_bench.py
```

Needs `lupa` (pip). Set `AICORE_CORE=/path/to/resources/aicore` to point at a
different checkout. The harness loads `shared/config.lua` live, so tuning
`saveIntervalMinutes`/`saveBatchSize` re-runs against the new config
automatically.

## Where these numbers are safe to use

Fine: internal design validation, roadmap, and as a first quantitative
support for "dirty tracking beats full-row writes". For public marketing
copy, pair with the planned FiveM server-profiler run
(`docs/PERFORMANCE.md` budget) — these synthetic numbers alone don't make
"faster than QBox" a settled claim.
