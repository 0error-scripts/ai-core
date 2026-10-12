# Aicore Ecosystem Performance Audit

**Date:** 2026-10-12 · **Scope:** 60 rebranded repos in `~/workspace/aicore/ecosystem/aicore_*` (440 Lua files)
**Method:** heuristic scan + manual verification of every high-severity hit. Read-only; nothing modified.
**Honesty note:** no resmon/profiler data — severity is judged from code structure (tick rate × work per tick × player count).

## Aggregate counts

| Signal | Count |
|---|---|
| `Wait(0)` occurrences | 107 (in 53 files) |
| `CreateThread` total | 228 |
| MySQL call sites | 206 |
| `SendNUIMessage` call sites | 160 |
| `json.encode` call sites | 59 |
| `GetActivePlayers()` call sites | 5 |
| Broadcast `TriggerClientEvent(..., -1, ...)` | weathersync SyncTime (2s), tunerchip nitro level (10Hz/boosting player), drugs RefreshDealers (on admin command only) |

## Top offender ranking (by verified severity)

1. **aicore_weathersync** — server tick at Wait(0) + 2s global broadcasts
2. **aicore_tunerchip** — 10Hz server events + global re-broadcast per boosting player
3. **aicore_phone** — ~9 sequential DB queries on every phone open + N+1 invoice loop
4. **aicore_taxijob** — 5+ per-frame distance-polling zone threads
5. **aicore_medical** — per-frame death loop for entire death duration
6. **aicore_drugs** — per-frame ped proximity scan while corner-selling
7. **aicore_lapraces** — per-frame pre-race distance check
8. **aicore_evidence** / **aicore_police** — duplicated per-frame shooting poll (same pattern twice)
9. **aicore_hud** — mostly fine already (50ms diff-based NUI); minor items
10. **aicore_smallresources** — vehiclepush per-frame (gameplay-legit), rest fine
11–15. **aicore_properties, aicore_vehiclekeys, aicore_customs, aicore_scoreboard, aicore_skillbar** — transient/menu-scoped loops, low priority

---

## Per-repo findings

### 1. aicore_weathersync — HIGH
**File:** `server/server.lua:222`
```lua
CreateThread(function()
    local previous = 0
    while true do
        Wait(0)  -- server tick, ~64x/sec
        local newBaseTime = os.time(os.date("!*t")) / 2 + 360
        if (newBaseTime % 60) ~= previous then ...
```
- **Severity: high.** A server-side thread spins every tick just to detect minute rollovers. `os.date`/`os.time` string formatting 64×/sec on the server for a 1-minute-granularity value.
- **Fix:** `Wait(1000)` (or schedule on minute boundary); compute once per second.

**File:** `server/server.lua:238`
```lua
while true do
    Wait(2000)
    TriggerClientEvent('qb-weathersync:client:SyncTime', -1, baseTime, timeOffset, freezeTime)
end
```
- **Severity: medium.** Broadcasts clock time to *every* client every 2 seconds, forever — even when nothing changed.
- **Fix:** broadcast only when the minute rolls over or a player joins; client already interpolates seconds locally (`client.lua:86`).

### 2. aicore_tunerchip — HIGH
**File:** `client/nos.lua:58`
```lua
CreateThread(function()
    while nitrousActivated do
        if vehicleNitrous[Plate].level - 1 ~= 0 then
            TriggerServerEvent('nitrous:server:UpdateNitroLevel', Plate, (vehicleNitrous[Plate].level - 1))
            TriggerEvent('hud:client:UpdateNitrous', ...)
```
**File:** `server/main.lua:45`
```lua
RegisterNetEvent('nitrous:server:UpdateNitroLevel', function(Plate, level)
    nitrousVehicles[Plate].level = level
    TriggerClientEvent('nitrous:client:UpdateNitroLevel', -1, Plate, level)  -- broadcast to ALL
```
- **Severity: high.** Every boosting player fires a server event every 100ms, and the server re-broadcasts each one to every client. 10Hz global event fan-out per nitro user.
- **Fix:** decrement level client-side; sync to server once on boost end (or on 25% thresholds). Server should relay, not broadcast — only players in scope need it.

### 3. aicore_phone — MEDIUM/HIGH
**File:** `server/main.lua:160-245` — on phone load:
```lua
local result   = MySQL.query.await('SELECT * FROM player_contacts WHERE citizenid = ? ...')
local invoices = MySQL.query.await('SELECT * FROM phone_invoices WHERE citizenid = ?', ...)
local garageresult = MySQL.query.await('SELECT * FROM player_vehicles WHERE citizenid = ?', ...)
local messages = MySQL.query.await('SELECT * FROM phone_messages WHERE citizenid = ?', ...)
local Tweets   = MySQL.query.await('SELECT * FROM phone_tweets WHERE `date` > NOW() - INTERVAL ? hour', ...)
local mails    = MySQL.query.await('SELECT * FROM player_mails WHERE citizenid = ? ...', ...)
local transactions = MySQL.query.await('SELECT * FROM crypto_transactions WHERE citizenid = ? ...', ...)
local images   = MySQL.query.await('SELECT * FROM phone_gallery WHERE citizenid = ? ...', ...)
```
- **Severity: medium.** ~9 sequential blocking queries every time a player opens/loads the phone. Latency adds up linearly.
- **Fix:** fire them concurrently (oxmysql promises / `Promise.all` pattern) or collapse into fewer queries; cache contacts/vehicles per session.

**File:** `server/main.lua:176` — N+1 inside invoice loop:
```lua
for _, v in pairs(invoices) do
    local Ply = exports.aicore:GetPlayerByCitizenId(v.sender)
    ...
    local res = MySQL.query.await('SELECT * FROM players WHERE citizenid = ?', {v.sender})
```
- **Severity: medium.** One extra `SELECT * FROM players` per invoice when sender is offline.
- **Fix:** batch with `WHERE citizenid IN (...)` or use the O(1) in-memory registry first, cache offline lookups.

### 4. aicore_taxijob — MEDIUM
**File:** `client/main.lua:102, 142, 191, 351, 590` — e.g.:
```lua
CreateThread(function()
    while true do
        local pos = GetEntityCoords(cache.ped)
        local dist = #(pos - vec3(sharedConfig.npcLocations.deliverLocations[...]))
        ...lib.showTextUI / NUI updates...
        Wait(0)
```
- **Severity: medium.** Five separate per-frame threads polling distances to fixed NPC pickup/dropoff zones, some also pushing NUI updates per frame.
- **Fix:** convert to ox_lib zone enter/exit events; one thread at 250ms max while on duty.

### 5. aicore_medical — MEDIUM
**File:** `client/dead.lua:32`
```lua
CreateThread(function()
    while DeathState == sharedConfig.deathState.DEAD do
        DisableControls()
        SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
        Wait(0)
    end
```
- **Severity: medium.** Spins per-frame for the *entire* death duration doing control disables + a weapon-set that only needs to happen once.
- **Fix:** hoist `SetCurrentPedWeapon` to death-state enter; keep `DisableControls` per frame or move to a `Wait(5)` control thread.

### 6. aicore_drugs — MEDIUM
**File:** `client/cornerselling.lua:45, 60, 262`
```lua
CreateThread(function()
    while cornerselling do
        local coords = GetEntityCoords(cache.ped)
        if not hasTarget then
            local closestPed = lib.getClosestPed(...)
```
- **Severity: medium.** Per-frame ped enumeration + distance math while corner-selling. Gameplay-bound, but 250ms tick is plenty for "find nearby ped".
- **Fix:** tick at 200-300ms; stop thread when sale completes instead of flag polling.

### 7. aicore_lapraces — MEDIUM/LOW
**File:** `client/main.lua:643`
```lua
CreateThread(function()
    while not CurrentRaceData.Started do
        local pos = GetEntityCoords(cache.ped)
        ... distance to checkpoint, countdown notify ...
        Wait(0)
    end
```
- **Severity: medium/low.** Per-frame coordinate + distance check for the whole pre-race waiting period.
- **Fix:** 500ms tick (countdown is 1s granularity anyway).

### 8. aicore_evidence + aicore_police — MEDIUM/LOW (duplicated pattern)
**Files:** `aicore_evidence/client/main.lua:154`, `aicore_police/client/evidence.lua:201`
```lua
while cache.weapon do  -- / while true do
    if IsPedShooting(cache.ped) then
        shotsFired += 1
        ...server events...
    Wait(0)
```
- **Severity: medium/low.** Two repos poll `IsPedShooting` every frame for GSR/bullet-casing logic.
- **Fix:** use the `CEventGunShot` game event handler instead of per-frame polling.

### 9. aicore_hud — LOW (already decent)
**File:** `client/main.lua` — main update loop runs at `Wait(50)`/`Wait(500)` with **diff-based** NUI (`updatePlayerHud` compares against `prevPlayerStats`, line 510). Compass runs at `Wait(0)` but only sends NUI on heading change (line 981). Speeding stress thread is `Wait(10000)` (line 802). Weapon stress is `Wait(0)` but only while armed + shooting (line 842).
- **Severity: low.** Already follows the diff/low-tick pattern. Only nit: compass `getCrossroads` native call per frame — could cache at 500ms.

### 10. aicore_smallresources — LOW
- `qbx_vehiclepush/client.lua:34` — per-frame physics while pushing a vehicle (gameplay-legit, transient).
- `qbx_afk/server.lua` — 1s loop over `GetPlayers()` for AFK checks; fine at 1Hz.
- `qbx_hudcomponents`, `qbx_cruise`, `qbx_noshuff`, `qbx_recoils`, `qbx_stun`, `qbx_staticemitters` — transient/menu-scoped `Wait(0)` loops; acceptable.

### 11–15. Low-priority repos
- **aicore_properties** — apartment-select/decorating loops are transient UI; `property.lua:219` already uses adaptive sleep (800ms base) — good pattern to copy.
- **aicore_vehiclekeys** — input polling (`IsControlJustPressed`) at `Wait(0)` is the correct pattern; carjack loop is transient.
- **aicore_customs** — `Wait(0)` only while tuning menu open (control disables).
- **aicore_scoreboard** — player enumeration + NUI only while scoreboard open.
- **aicore_skillbar** — transient minigame loops.
- **aicore_adminmenu / aicore_ambulancejob / aicore_busjob** — transient noclip/bed/NPC threads.

## Suggested fix order (biggest win first)
1. weathersync server tick → `Wait(1000)`; SyncTime broadcast on minute-change only.
2. tunerchip nitro → client-side level decrement, server sync on boost end; scope relay instead of `-1` broadcast.
3. phone load → concurrent queries + kill the N+1 invoice lookup.
4. taxijob/drugs/lapraces → zone events / 250-500ms ticks instead of `Wait(0)` polling.
5. evidence+police shooting poll → `CEventGunShot` handler.
6. medical death loop → hoist one-time setup out of the per-frame loop.

## Patterns to propagate (already good in-repo)
- HUD's diff-based NUI updates (`updatePlayerHud` + `prevPlayerStats`).
- properties' adaptive sleep (`local sleep = 800` raised/lowered by proximity).
- weathersync client's local second interpolation (server sends minutes only).
