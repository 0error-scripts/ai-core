# Aicore Architecture

## Overview

Aicore is a FiveM server core: the layer that owns players, persistence, and
server↔client synchronization. Everything else (jobs, inventory, phones) builds
on top of it.

```
resources/aicore/
├── fxmanifest.lua        # cerulean, lua54, ox_lib + oxmysql
├── shared/
│   └── config.lua        # all tuning in one place
├── server/
│   ├── main.lua          # AICore registry (O(1) player lookups)
│   ├── player.lua        # player objects: shared metatable + dirty tracking
│   ├── storage.lua       # DB adapter: partial updates, prepared statements
│   └── loops.lua         # coalesced save scheduler (staggered, batched)
├── client/
│   └── main.lua          # state-bag handlers only — zero Wait(0) loops
└── locales/
    └── en.json
```

## Player manager (`server/player.lua`)

- One **shared metatable** for all player methods — no per-player closure tables.
- Each player carries a **dirty set**: top-level fields (`money`, `metadata`,
  `position`, …) are marked dirty on write, cleared on save.
- Writes go through setters that validate server-side, mark dirty, and trigger
  **differential sync** (only changed keys to the client).

## Save pipeline (`server/loops.lua` + `server/storage.lua`)

1. A single scheduler ticks on a configured interval.
2. It snapshots the online player list, iterates in **staggered batches**
   (yielding between batches so a full server never hitches).
3. Players with an **empty dirty set are skipped entirely**.
4. Dirty players get a **partial `UPDATE`** — only dirty columns — via prepared
   statements. Full-row writes happen only on logout / migration.

## Vitals without ticking (`time-based`)

Hunger/thirst/stress are **not** decremented in the database. The core stores a
`vitalsUpdatedAt` timestamp; current values are derived on read:

```
current = lastValue - rate * (now - vitalsUpdatedAt)
```

Persisted on logout and on the coalesced interval — never per tick.

## Sync model

- **One-off actions** → events (validated server-side).
- **Durable properties** (duty, vitals, flags) → state bags, server-written,
  client-read, flat keys.
- **Big / rarely-read data** → server-side table + `lib.callback`, never
  pushed speculatively.

`sv_stateBagStrictMode` is expected to be `true`: clients never write state.

## Schema direction

Hot fields become real indexed columns (`cash`, `bank`, `position`), cold data
stays JSON. No `JSON_EXTRACT` in hot filters.

## Compatibility

QBox/QBCore API compatibility ships as a **separate opt-in resource**
(`aicore_bridge`), never as a tax on the core.
