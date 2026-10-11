# ⚡ Aicore

### The performance-first FiveM server core.

> **Status:** 🚧 In active development (`v0.1.0` scaffold). Core systems are being built in the open — follow along, but don't run this in production yet.

Aicore is a new FiveM server core (framework) built from a single observation: existing cores re-save the **entire player row** and re-sync the **entire player object** on every tiny change — every hunger tick, every metadata write. That waste multiplies across every player, every minute.

Aicore is designed around one principle: **never do work you don't have to.**

## Why Aicore?

- 🧠 **Dirty-tracked saves** — only changed columns ever hit the database. Clean players are skipped entirely.
- 📡 **Differential sync** — clients receive only the keys that changed, not the whole player table.
- ⏱️ **Time-based vitals** — hunger/thirst/stress are derived from timestamps, never ticked in the DB.
- 🧵 **Zero per-frame core loops** — the client core ships with no `Wait(0)` loops. Everything is event- and state-bag-driven, per FiveM's own [performance best practices](https://forum.cfx.re/t/best-practice-improve-your-resource-performance/105509).
- 🔌 **Opt-in compatibility** — no forced bridge tax. A QBox/QBCore compatibility layer ships as a separate, optional resource.
- 📊 **Published perf budget** — every release is measured against a QBox baseline with `resmon` and the server profiler. Numbers, not claims.

## Performance budget

| Area | Budget |
|---|---|
| Client core, idle | `0.00 ms` |
| Server core, idle (100 players) | under FiveM's 5 ms slow-resource warning line |
| Player save | partial `UPDATE` of dirty columns only |
| Client sync payload | changed keys only, never full `PlayerData` |

Full details: [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)

## Architecture

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) covers the player manager, dirty-tracking save pipeline, differential sync, and storage layer. [`docs/AUDIT-qbox.md`](docs/AUDIT-qbox.md) is our public teardown of QBox v1.24.0 — the baseline we're beating.

## Install

See [`docs/INSTALL.md`](docs/INSTALL.md) and `server.cfg.example`. When it's ready:

```cfg
ensure ox_lib
ensure oxmysql
ensure aicore
# ensure aicore_bridge  # optional: run QBox/QBCore scripts on Aicore
```

## Contributing

Issues and PRs are welcome once the core systems land. Please read [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) first — every contribution must respect the perf budget.

## License

MIT — see [LICENSE](LICENSE).
