-- Aicore benchmark harness (synthetic I/O profile).
-- Runs the REAL core Lua (server/player.lua, server/storage.lua) under stubbed
-- FiveM globals, against a QBox-like baseline modeled from docs/AUDIT-qbox.md.
-- Measures what dirty tracking + differential sync actually save: DB write
-- bytes/queries and net event bytes. NOT a FiveM profiler run — those numbers
-- (resmon, server profiler) still need a live FiveM test server.
--
-- Run: lua bench.lua   (or via bench/run.sh)

local CORE = arg and arg[1] or (os.getenv('AICORE_CORE') or '../resources/aicore')

----------------------------------------------------------------------
-- Stubs: FiveM globals the core expects
----------------------------------------------------------------------
local _exports = {}
function exports(name, fn) _exports[name] = fn end

local NetEvents = { count = 0, bytes = 0 }
local function payloadBytes(name, args)
    local b = #name
    for i = 1, #args do
        local a = args[i]
        if type(a) == 'table' then a = json_encode(a) else a = tostring(a) end
        b = b + #a
    end
    return b
end
function TriggerClientEvent(name, src, ...)
    local args = { ... }
    NetEvents.count = NetEvents.count + 1
    NetEvents.bytes = NetEvents.bytes + payloadBytes(name, args)
end
function TriggerEvent(name, ...) end
function CreateThread(fn) end
function Wait(ms) end
lib = { print = { error = function(...) end } }
function vec4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

----------------------------------------------------------------------
-- Compact JSON encoder (for SIZE measurement, not wire compat)
----------------------------------------------------------------------
local function isArray(t)
    local n, c = 0, 0
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k ~= math.floor(k) then return false end
        n = math.max(n, k); c = c + 1
    end
    return c == n
end
function json_encode(v)
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"'
    elseif t == 'number' then
        return tostring(v)
    elseif t == 'boolean' then
        return v and 'true' or 'false'
    elseif t == 'table' then
        local parts = {}
        if isArray(v) then
            for i = 1, #v do parts[#parts + 1] = json_encode(v[i]) end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            for k, val in pairs(v) do
                parts[#parts + 1] = '"' .. tostring(k) .. '":' .. json_encode(val)
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    else
        return 'null'
    end
end
json = { encode = json_encode, decode = function(s) return {} end }

----------------------------------------------------------------------
-- DB stub: counts queries and models bytes on the wire (SQL + values)
----------------------------------------------------------------------
local DB = { queries = 0, bytes = 0, encodes = 0 }
local function countedAwait(sql, values)
    DB.queries = DB.queries + 1
    local b = #sql
    if values then
        for i = 1, #values do
            local v = values[i]
            if type(v) == 'table' then v = json_encode(v); DB.encodes = DB.encodes + 1 end
            b = b + #tostring(v)
        end
    end
    DB.bytes = DB.bytes + b
end
MySQL = {
    update = { await = countedAwait },
    insert = { await = function() end },
    single = { await = function() return nil end },
    query  = { await = function() return nil end },
    scalar = { await = function() return nil end },
}

----------------------------------------------------------------------
-- Load the REAL core code
----------------------------------------------------------------------
AICore = {}
dofile(CORE .. '/shared/config.lua')          -- real Config (save intervals, vitals)
package.loaded['server.storage'] = dofile(CORE .. '/server/storage.lua') -- real storage
dofile(CORE .. '/server/player.lua')          -- real player objects + dirty tracking
local Storage = package.loaded['server.storage']

assert(Config.saveIntervalMinutes == 10, 'unexpected config drift')
print(('[bench] loaded real core: saveInterval=%dmin batch=%d'):format(
    Config.saveIntervalMinutes, Config.saveBatchSize))

----------------------------------------------------------------------
-- Representative player payloads (same shapes both sides see)
----------------------------------------------------------------------
local function makeData(i)
    return {
        cash = 1250 + i,
        bank = 48200 + i * 7,
        position = { x = -1035.0 + i * 0.5, y = -2739.0, z = 20.0, w = 90.0 },
        vitals = { hunger = 100, thirst = 100, stress = 0, updatedAt = os.time() },
        metadata = {
            hunger = 100, thirst = 100, stress = 0, armor = 0,
            inlaststand = false, isdead = false, bloodtype = 'A+',
            alias = 'Player' .. i, walletid = 'W' .. tostring(100000 + i),
            fingerprint = 'FP' .. tostring(900000 + i), status = 'alive',
            callsign = '1-A-1', tracker = false, phone = '555-01' .. tostring(i % 100),
        },
        job = { name = 'unemployed', label = 'Civilian', grade = 0, onduty = false, payment = 50 },
        gang = { name = 'none', label = 'None', grade = 0 },
    }
end

-- QBox-style full PlayerData push size (audit: whole PlayerData per change).
-- Modeled from the same payloads, per docs/AUDIT-qbox.md hot spot #1.
local function qboxPlayerDataSize(data)
    local pd = {
        citizenid = 'AC000001', name = 'Test Player', cash = data.cash, bank = data.bank,
        money = { cash = data.cash, bank = data.bank },
        charinfo = { firstname = 'Test', lastname = 'Player', birthdate = '1998-01-01',
                     gender = 0, nationality = 'Indian', phone = '555-0100', account = 'AC000001' },
        job = data.job, gang = data.gang, position = data.position,
        metadata = data.metadata, vitals = data.vitals,
    }
    return #json_encode(pd)
end

-- QBox-style full-row write: json.encode(money, charinfo, job, gang, position,
-- metadata) + one UPDATE. Modeled per docs/AUDIT-qbox.md hot spot #1.
local function qboxFullWriteBytes(data)
    local money  = json_encode({ cash = data.cash, bank = data.bank })
    local charinfo = json_encode({ firstname = 'Test', lastname = 'Player',
        birthdate = '1998-01-01', gender = 0, nationality = 'Indian',
        phone = '555-0100', account = 'AC000001' })
    local job = json_encode(data.job)
    local gang = json_encode(data.gang)
    local pos = json_encode(data.position)
    local meta = json_encode(data.metadata)
    local sql = 'UPDATE `users` SET `money` = ?, `charinfo` = ?, `job` = ?, `gang` = ?, `position` = ?, `metadata` = ? WHERE `citizenid` = ?'
    return #sql + #money + #charinfo + #job + #gang + #pos + #meta + 8
end

----------------------------------------------------------------------
-- Workload A: vitals-tick replay (the audit's #1 hot spot)
-- 30 simulated minutes, 128 players. Per minute per player: 2 metadata
-- writes (hunger + thirst tick). QBox: 2x full-row write + 2x full push
-- per player per minute. Aicore: dirty flags coalesce; saves run on the
-- real 10-minute interval writing only dirty columns.
----------------------------------------------------------------------
local N = 128
local SIM_MINUTES = 30

local function resetCounters()
    DB.queries, DB.bytes, DB.encodes = 0, 0, 0
    NetEvents.count, NetEvents.bytes = 0, 0
end

local function runWorkloadA()
    resetCounters()
    local players = {}
    for i = 1, N do
        players[i] = AICore.CreatePlayer(i, 'AC' .. tostring(100000 + i), i, { 'license:' .. i }, makeData(i))
    end
    -- Aicore path: real SetMetadata + real savePartial on the real interval
    local aicore = { queries = 0, bytes = 0, events = 0, eventBytes = 0 }
    for minute = 1, SIM_MINUTES do
        for i = 1, N do
            local p = players[i]
            p:SetMetadata('hunger', 100 - minute * 0.5)
            p:SetMetadata('thirst', 100 - minute * 0.6)
        end
        if minute % Config.saveIntervalMinutes == 0 then
            -- the coalesced scheduler: only dirty players, only dirty columns
            for i = 1, N do
                local p = players[i]
                if p:IsDirty() then
                    Storage.savePartial(p.citizenid, p.dirty, p.data)
                    p:MarkClean()
                end
            end
        end
    end
    aicore.queries, aicore.bytes = DB.queries, DB.bytes
    aicore.events, aicore.eventBytes = NetEvents.count, NetEvents.bytes

    -- QBox path (modeled from the audit): every metadata write is a full
    -- write + full push, immediately, in its own thread.
    resetCounters()
    local qbox = { queries = 0, bytes = 0, events = 0, eventBytes = 0 }
    local pdSize = qboxPlayerDataSize(makeData(1))
    for minute = 1, SIM_MINUTES do
        for i = 1, N do
            local data = players[i].data
            -- 2 metadata writes per player per minute
            for w = 1, 2 do
                qbox.queries = qbox.queries + 1
                qbox.bytes = qbox.bytes + qboxFullWriteBytes(data)
                qbox.events = qbox.events + 1
                qbox.eventBytes = qbox.eventBytes + #'QBCore:Player:SetPlayerData' + pdSize
            end
        end
    end
    return aicore, qbox
end

----------------------------------------------------------------------
-- Workload B: single save-burst, 128 players, 35% dirty, ~2 fields each
-- QBox model (audit hot spot #4/#6): no dirty tracking, Save() writes the
-- full row for every player. Aicore: real savePartial, dirty players only.
----------------------------------------------------------------------
local function runWorkloadB()
    resetCounters()
    local players = {}
    for i = 1, N do
        players[i] = AICore.CreatePlayer(i, 'AC' .. tostring(100000 + i), i, { 'license:' .. i }, makeData(i))
    end
    math.randomseed(42)
    for i = 1, N do
        if math.random() < 0.35 then
            local p = players[i]
            p:AddMoney('bank', 50)                       -- paycheck touch
            if math.random() < 0.5 then
                p:Set('position', { x = -1035.0 + i, y = -2730.0, z = 20.0, w = 0.0 })
            end
        end
    end
    local saved = 0
    for i = 1, N do
        local p = players[i]
        if p:IsDirty() then
            Storage.savePartial(p.citizenid, p.dirty, p.data)
            p:MarkClean()
            saved = saved + 1
        end
    end
    local aicore = { queries = DB.queries, bytes = DB.bytes, playersSaved = saved }

    local qbox = { queries = 0, bytes = 0 }
    for i = 1, N do
        qbox.queries = qbox.queries + 1
        qbox.bytes = qbox.bytes + qboxFullWriteBytes(players[i].data)
    end
    qbox.playersSaved = N
    return aicore, qbox
end

----------------------------------------------------------------------
-- Report
----------------------------------------------------------------------
local function pct(a, b) return ('%.1f%%'):format((1 - a / b) * 100) end
local function kb(b) return ('%.1f KB'):format(b / 1024) end

print('\n================ BENCH RESULTS ================')
print(('players=%d'):format(N))

local a, q = runWorkloadA()
print('\n--- Workload A: vitals-tick replay, 30 sim-minutes ---')
print(('Aicore : DB queries=%d  bytes=%s'):format(a.queries, kb(a.bytes)))
print(('QBox*  : DB queries=%d  bytes=%s'):format(q.queries, kb(q.bytes)))
print(('--> DB write reduction: %s bytes, %s queries'):format(pct(a.bytes, q.bytes), pct(a.queries, q.queries)))
print(('Aicore : net events=%d  payload=%s'):format(a.events, kb(a.eventBytes)))
print(('QBox*  : net events=%d  payload=%s'):format(q.events, kb(q.eventBytes)))
print(('--> net payload reduction: %s'):format(pct(a.eventBytes, q.eventBytes)))

local b1, b2 = runWorkloadB()
print('\n--- Workload B: save burst, 35% of players dirty ---')
print(('Aicore : players saved=%d/%d  bytes=%s'):format(b1.playersSaved, N, kb(b1.bytes)))
print(('QBox*  : players saved=%d/%d  bytes=%s'):format(b2.playersSaved, N, kb(b2.bytes)))
print(('--> save-burst byte reduction: %s'):format(pct(b1.bytes, b2.bytes)))

print('\n* QBox figures are MODELED from docs/AUDIT-qbox.md hot spots')
print('  (full-row UPDATE per metadata write; full PlayerData push per change).')
print('  Aicore figures run the REAL server/player.lua + server/storage.lua.')
print('  Excludes: actual MySQL latency, network stack, FiveM tick cost.')
print('================================================\n')
