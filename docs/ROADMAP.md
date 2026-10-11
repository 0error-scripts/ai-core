# Aicore Roadmap

## v0.1 — Foundation (in progress)
- [x] Architecture design
- [x] QBox v1.24.0 performance audit ([`docs/AUDIT-qbox.md`](AUDIT-qbox.md))
- [x] Public repo + launch docs
- [ ] Player registry (O(1) lookups)
- [ ] Player object: shared metatable + dirty tracking
- [ ] Storage adapter: partial updates, normalized hot columns
- [ ] Coalesced save scheduler
- [ ] Client core: state-bag handlers, zero per-frame loops

## v0.2 — Sync & safety
- [ ] Differential client sync
- [ ] Time-based vitals system
- [ ] Server-side validation + anti-dupe guards
- [ ] ACE permission helpers

## v0.3 — Compatibility
- [ ] `aicore_bridge`: opt-in QBox/QBCore API compatibility layer
- [ ] Migration guide from QBox

## v0.4 — Benchmarks
- [ ] Benchmark harness (idle resmon, join latency, save burst)
- [ ] Published QBox-vs-Aicore numbers

## v1.0 — Production core
- [ ] Hardened, documented, production-ready
- [ ] Starter server template
