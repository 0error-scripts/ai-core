# Aicore Performance Budget

Performance is a feature, and it's measured — not claimed. These budgets are
enforced on every release using FiveM's own tools: `resmon 1` on the client
and the built-in server profiler.

## Budgets

| Area | Budget | Measured with |
|---|---|---|
| Client core, idle (standing still) | `0.00 ms` | `resmon 1`, quiet area |
| Client core, busy area | `≤ 0.05 ms` | `resmon 1`, busy area |
| Server core, idle, 100 players | below FiveM's 5 ms slow-resource warning | server profiler |
| Single player save | one partial `UPDATE`, dirty columns only | `mysql_slow_query_warning` |
| Scheduled save burst, 100 players | staggered, no tick over 5 ms | server profiler |
| Client sync per change | changed keys only | packet inspection |

FiveM warns players when a resource averages over **5 ms across 64 ticks**
([source](https://forum.cfx.re/t/best-practice-improve-your-resource-performance/105509)).
Aicore treats that line as a hard ceiling, not a target.

## Rules (from FiveM's official guidance)

1. **Frequency** — no `Wait(0)` loops in core. Per-frame code only reads flags;
   slow checks run on timers.
2. **Natives are expensive** — cache handles/coords per tick; never call the
   same native twice in one scope.
3. **Idle cost ≈ 0** — zones/points with enter/exit events instead of
   distance-check loops; UI pushes on change, never polls.
4. **No DB in loops** — one coalesced save scheduler; prepared statements only.
5. **Events vs state bags** — one-off actions are events; durable properties are
   server-written state bags with flat keys.
6. **One system per job** — the core stays thin and defers to `ox_lib`,
   `ox_inventory`, `ox_target` instead of reimplementing them.

## Benchmark harness (planned)

- Baseline: QBox v1.24.0 on identical hardware/scripts.
- Metrics: idle resmon, join latency, 100-player save burst, tick p99.
- Results published per release in `docs/benchmarks/`.
