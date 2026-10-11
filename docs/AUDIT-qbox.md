# QBox (qbx_core v1.24.0) performance audit — for Aicore design

Source: https://github.com/Qbox-project/qbx_core (cloned 2026-10-12, depth 1)
~5,579 lines Lua across server/client/shared/bridge.

## What QBox already does well (don't regress)
- O(1) player lookups: `QBX.PlayerRegistry` (byCitizenId/byUserId/byIdentifier), maintained on load/unload (server/main.lua). Recent perf commit #756.
- Staggered interval loops: hunger/thirst + paycheck loops snapshot the player list and yield every 20 players (server/loops.lua) — no full-server hitch.
- DB indexes on `users` identifier columns (server/storage/players.lua) — fixed ~1s join stall.
- Exports-based API instead of a global Core object; `provide 'qb-core'` bridge for compat.
- oxmysql prepared statements everywhere; ox_lib callbacks.
- State bags for replicated vitals (hunger/thirst/stress) instead of net events.

## Hot spots / waste found
1. **SetMetadata → full save + full sync** (server/player.lua ~1160-1225):
   - Every metadata write calls `UpdatePlayerData()` → `TriggerClientEvent('QBCore:Player:SetPlayerData', src, player.PlayerData)` — the ENTIRE player data table pushed to the client on every single metadata change.
   - Then `savePlayer(player)` → `Save()` → `storage.upsertPlayerEntity()` which json.encodes money, charinfo, job, gang, position, metadata (6 encodes) and does a full-row UPDATE. In a new thread each time.
   - loops.lua hunger/thirst tick calls SetMetaData twice AND Save() per player per interval → per player per minute: 2× full-row DB writes + 2× full PlayerData net pushes. This is the #1 overhead.
2. **Per-player method tables**: each player object builds a full `self.Functions.*` closure table (~100+ closures per player). Use a shared metatable instead.
3. **JSON-column everything**: money/charinfo/job/gang/metadata/position all JSON in one row → every save rewrites the whole row; JSON_EXTRACT filters can't index. Hot fields (cash, bank, position) should be real columns.
4. **Save() reads vitals from the ped + state bag every save** (GetEntityHealth etc.) — fine, but it runs even when nothing changed.
5. **Bridge tax**: `provide 'qb-core'` + bridge/qb compat layer always loaded; make it opt-in.
6. **No dirty tracking**: no distinction between "data changed" and "data touched" — everything is a full write.

## Aicore performance plan (how we beat it)
1. **Dirty-tracked partial saves**: mark which top-level fields changed; save loop writes only dirty columns (`UPDATE players SET cash=?, position=? ...`). Full-row write only on logout/migration.
2. **Differential client sync**: send only changed keys (`{metadata={hunger=..}}`), not the whole PlayerData table.
3. **Time-based vitals**: don't tick hunger/thirst in DB at all — store `lastVitalsUpdate` timestamp and compute on read; persist on logout or every N minutes, coalesced.
4. **Coalesced save scheduler**: one staggered loop; per-player save at most once per interval; skip players with no dirty flags.
5. **Shared metatable** for player methods (one function table, not per-player closures).
6. **Normalized hot columns**: cash, bank, position xyz as real indexed columns; cold data stays JSON.
7. **Opt-in compat bridge**: core ships clean; `aicore_bridge` resource provides qb-core/QBox API shims only if installed.
8. **Benchmark harness from day one**: idle resmon, join latency, 100-player save burst vs QBox baseline. No claim of "faster" without numbers.

## FiveM official guidance applied to Aicore
Sources: Cfx.re "[Best practice] Improve your resource performance" (forum.cfx.re/t/105509),
"FiveM Script Performance Budgeting" (resmon/server profiler workflow).

What FiveM itself suggests, and how Aicore uses each:
1. **Frequency (their #1 rule)**: only code that must run every tick runs every tick
   ("ThisFrame" natives). Everything else gets a sane interval; expensive checks are
   segregated behind flags. → Aicore client ships ZERO `Wait(0)` loops; slow checks
   (death, vehicle state) update flags on 500ms+ timers, per-frame code only reads flags.
2. **Natives are expensive**: cache native results; never call the same native twice in
   one scope; keep natives out of hot paths. → Aicore caches ped handles/coords per tick,
   resolves once per handler.
3. **DRY / don't recompute**: take the previous result instead of recomputing. → dirty
   flags, computed vitals from timestamps, cached lookups.
4. **Idle cost must be ~0**: a resource doing work while the player isn't using it is the
   expensive kind. → zones/points (enter/exit events) instead of distance-check loops;
   NUI pushes data on change, never polls.
5. **Events vs state bags**: one-off actions = events; durable properties = state bags.
   Server-written, client-read; `sv_stateBagStrictMode true`; flat keys (nested writes
   don't replicate); don't write entity bags for far-away entities (console + net spam).
6. **No DB in loops**: cache, batch writes, find hot spots with the server profiler.
   → coalesced save scheduler (already in plan).
7. **Measure, don't guess**: `resmon 1` baseline (quiet area + busy area), server profiler
   during busy sessions, per-resource budget written down. → Aicore ships with a perf
   budget: client idle 0.00ms, server core under the 5ms/64-tick slow-resource warning line.
8. **One system per job**: no duplicate inventories/targets/notifications. → Aicore core
   stays thin; defers to ox_lib/ox_inventory/ox_target instead of reimplementing.
