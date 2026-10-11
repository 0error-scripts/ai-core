---Aicore QB-compatibility shape.
---QBox-derived resources talk to the core through `exports.aicore:GetPlayer`
---and expect the QBCore/qbx player shape: `player.PlayerData` and
---`player.Functions`. This file attaches that shape to our native player
---objects without changing the fast native API underneath.
---
---Reads stay live: money/job/gang/metadata are proxies or shared references
---into `player.data`, so there is no snapshot to go stale and no second
---copy to keep in sync.

---@param player Player
---@param key 'cash'|'bank'
---@return table proxy
local function moneyProxy(player)
    return setmetatable({}, {
        __index = function(_, k)
            if k == 'cash' then return player.data.cash or 0 end
            if k == 'bank' then return player.data.bank or 0 end
            if k == 'crypto' then return player.data.metadata.crypto or 0 end
            return nil
        end,
        __newindex = function(_, k, v)
            -- Direct writes are validated through the native path.
            if k == 'cash' or k == 'bank' then player:SetMoney(k, v) end
        end,
    })
end

---@param player Player
---@return table proxy
local function jobProxy(player)
    return setmetatable({}, {
        __index = function(_, k)
            local job = player.data.job or {}
            local def = AICore.Jobs[job.name] or {}
            if k == 'name' then return job.name end
            if k == 'label' then return def.label or job.name end
            if k == 'type' then return def.type or 'none' end
            if k == 'onduty' then return job.onduty or false end
            if k == 'grade' then
                local grades = def.grades or {}
                local g = grades[job.grade or 0] or {}
                return { name = g.name or '', level = job.grade or 0, payment = g.payment or 0 }
            end
            return nil
        end,
        __newindex = function(_, k, v)
            if k == 'onduty' then AICore.SetDuty(player.source, v and true or false) end
        end,
    })
end

---@param player Player
---@return table proxy
local function gangProxy(player)
    return setmetatable({}, {
        __index = function(_, k)
            local gang = player.data.gang or {}
            local def = AICore.Gangs[gang.name] or {}
            if k == 'name' then return gang.name end
            if k == 'label' then return def.label or gang.name end
            if k == 'grade' then
                local grades = def.grades or {}
                local g = grades[gang.grade or 0] or {}
                return { name = g.name or '', level = gang.grade or 0 }
            end
            return nil
        end,
    })
end

---@param fullName string
---@return table charinfo
local function buildCharinfo(fullName)
    local first, last = fullName:match('^(%S+)%s+(.-)%s*$')
    return {
        firstname = first or fullName,
        lastname = last or '',
        birthdate = '1990-01-01',
        nationality = 'American',
        phone = '',
    }
end

---Attach PlayerData + Functions to a native player object. Idempotent.
---@param player Player
---@param charName string
function AICore.AttachCompatShape(player, charName)
    if player.PlayerData then return end

    player.PlayerData = {
        source = player.source,
        citizenid = player.citizenid,
        name = charName,
        charinfo = buildCharinfo(charName or player.citizenid),
        money = moneyProxy(player),
        job = jobProxy(player),
        gang = gangProxy(player),
        metadata = player.data.metadata, -- live shared reference
    }

    local source = player.source
    player.Functions = {
        AddMoney = function(moneytype, amount) return player:AddMoney(moneytype, amount) end,
        RemoveMoney = function(moneytype, amount) return player:RemoveMoney(moneytype, amount) end,
        SetMoney = function(moneytype, amount) return player:SetMoney(moneytype, amount) end,
        GetMoney = function(moneytype) return player:GetMoney(moneytype) end,
        SetMetaData = function(meta, value) player:SetMetadata(meta, value) end,
        GetMetaData = function(meta)
            if meta then return player:GetMetadata(meta) end
            return player.data.metadata
        end,
        SetJob = function(job, grade) return AICore.SetPlayerJob(source, job, grade) end,
        SetGang = function(gang, grade) return AICore.SetPlayerGang(source, gang, grade) end,
        SetJobDuty = function(onDuty) AICore.SetDuty(source, onDuty) end,
        AddItem = function(item, amount, slot, info)
            return exports.ox_inventory:AddItem(source, item, amount or 1, info, slot)
        end,
        RemoveItem = function(item, amount, slot)
            return exports.ox_inventory:RemoveItem(source, item, amount or 1, nil, slot)
        end,
        GetItemByName = function(item)
            local count = exports.ox_inventory:GetItemCount(source, item)
            if not count or count <= 0 then return nil end
            return { name = item, label = item, amount = count }
        end,
        GetItemsByName = function(item)
            local count = exports.ox_inventory:GetItemCount(source, item) or 0
            return { [item] = { name = item, label = item, amount = count } }
        end,
        ClearInventory = function()
            return exports.ox_inventory:ClearInventory(source)
        end,
        Save = function() return AICore.SavePlayer(source) end,
        Logout = function() AICore.Logout(source) end,
        UpdatePlayerData = function() return true end, -- no-op: our data is always live
    }
end

---Toggle/set job duty. Persists inside the job JSON column.
---@param source Source
---@param duty boolean
function AICore.SetDuty(source, duty)
    local player = AICore.GetPlayer(source)
    if not player then return end
    player.data.job.onduty = duty and true or false
    player.dirty['job'] = true
    TriggerEvent('aicore:server:onJobUpdate', source, player.data.job)
    TriggerClientEvent('aicore:client:onJobUpdate', source, player.data.job)
end

exports('SetDuty', AICore.SetDuty)

---QB-style primary group check (job or gang name).
---@param source Source
---@param group string|string[]
---@return boolean
function AICore.HasPrimaryGroup(source, group)
    local player = AICore.GetPlayer(source)
    if not player then return false end
    if type(group) == 'table' then
        for i = 1, #group do
            if AICore.HasPrimaryGroup(source, group[i]) then return true end
        end
        return false
    end
    local job = player.data.job or {}
    local gang = player.data.gang or {}
    return job.name == group or gang.name == group
end

exports('HasPrimaryGroup', AICore.HasPrimaryGroup)

---Count on-duty players whose job type matches (e.g. 'leo', 'ems').
---@param jobType string
---@return integer
function AICore.GetDutyCountType(jobType)
    local count = 0
    for _, player in pairs(AICore.Players) do
        local job = player.data.job or {}
        local def = AICore.Jobs[job.name] or {}
        if (def.type or 'none') == jobType and job.onduty then
            count = count + 1
        end
    end
    return count
end

exports('GetDutyCountType', AICore.GetDutyCountType)

---QB-compat alias.
exports('GetQBPlayers', AICore.GetPlayers)

---Usable-item registry (qbx:CreateUseableItem compat). Item use itself is
---handled by ox_inventory; this keeps the registration call working.
---@type table<string, any>
AICore.UsableItems = AICore.UsableItems or {}

---@param item string
---@param data any
function AICore.CreateUseableItem(item, data)
    AICore.UsableItems[item] = data
end

exports('CreateUseableItem', AICore.CreateUseableItem)

---@param entity integer
---@return boolean
function AICore.DeleteVehicle(entity)
    if not entity or not DoesEntityExist(entity) then return false end
    DeleteEntity(entity)
    return true
end

exports('DeleteVehicle', AICore.DeleteVehicle)

---Find vehicles by model name (case-insensitive display name match).
---@param modelName string
---@return integer[]
function AICore.GetVehiclesByName(modelName)
    local found = {}
    if type(modelName) ~= 'string' then return found end
    local want = modelName:lower()
    for _, veh in ipairs(GetAllVehicles()) do
        local display = GetDisplayNameFromVehicleModel(GetEntityModel(veh) or 0)
        if display and display:lower() == want then
            found[#found + 1] = veh
        end
    end
    return found
end

exports('GetVehiclesByName', AICore.GetVehiclesByName)

-- joaat for weapon-hash keyed lookup (qbx:GetWeapons compat).
local function joaat(str)
    local hash = 0
    str = str:lower()
    for i = 1, #str do
        hash = hash + str:byte(i)
        hash = hash + bit.lshift(hash, 10)
        hash = bit.bxor(hash, bit.rshift(hash, 6))
    end
    hash = hash + bit.lshift(hash, 3)
    hash = bit.bxor(hash, bit.rshift(hash, 11))
    hash = hash + bit.lshift(hash, 15)
    return hash
end

local WEAPON_NAMES = {
    'weapon_pistol', 'weapon_combatpistol', 'weapon_appistol', 'weapon_pistol50',
    'weapon_snspistol', 'weapon_heavypistol', 'weapon_vintagepistol', 'weapon_microsmg',
    'weapon_smg', 'weapon_assaultsmg', 'weapon_machinepistol', 'weapon_minismg',
    'weapon_assaultrifle', 'weapon_carbinerifle', 'weapon_advancedrifle', 'weapon_specialcarbine',
    'weapon_bullpuprifle', 'weapon_compactrifle', 'weapon_mg', 'weapon_combatmg',
    'weapon_gusenberg', 'weapon_sniperrifle', 'weapon_heavysniper', 'weapon_marksmanrifle',
    'weapon_pumpshotgun', 'weapon_sawnoffshotgun', 'weapon_assaultshotgun', 'weapon_bullpupshotgun',
    'weapon_knife', 'weapon_nightstick', 'weapon_hammer', 'weapon_bat', 'weapon_crowbar',
    'weapon_golfclub', 'weapon_bottle', 'weapon_dagger', 'weapon_hatchet', 'weapon_knuckle',
    'weapon_machete', 'weapon_flashlight', 'weapon_switchblade', 'weapon_battleaxe',
}

local weaponsCache
---@return table<integer, {name:string}>
function AICore.GetWeapons()
    if not weaponsCache then
        weaponsCache = {}
        for i = 1, #WEAPON_NAMES do
            weaponsCache[joaat(WEAPON_NAMES[i])] = { name = WEAPON_NAMES[i] }
        end
    end
    return weaponsCache
end

exports('GetWeapons', AICore.GetWeapons)

---QB-shaped PlayerData for a source (server-side).
---@param source Source
---@return table?
function AICore.GetPlayerData(source)
    local player = AICore.GetPlayer(source)
    return player and player.PlayerData or nil
end

exports('GetPlayerData', AICore.GetPlayerData)

---Vehicle type lookup with a self-populating cache (used by aicore.spawnVehicle).
---@param hash integer|string model hash or name
---@return {type:string}
function AICore.GetVehiclesByHash(hash)
    local model = type(hash) == 'string' and joaat(hash) or hash
    AICore._vehicleTypeCache = AICore._vehicleTypeCache or {}
    if not AICore._vehicleTypeCache[model] then
        local temp = CreateVehicle(model, 0, 0, -200, 0, true, true)
        local tries = 0
        while not DoesEntityExist(temp) and tries < 50 do Wait(0) tries += 1 end
        AICore._vehicleTypeCache[model] =
            DoesEntityExist(temp) and GetVehicleType(temp) or 'automobile'
        if DoesEntityExist(temp) then DeleteEntity(temp) end
    end
    return { type = AICore._vehicleTypeCache[model] }
end

exports('GetVehiclesByHash', AICore.GetVehiclesByHash)

---@param entity integer
---@param bucket integer
function AICore.SetEntityBucket(entity, bucket)
    SetEntityRoutingBucket(entity, bucket)
end

exports('SetEntityBucket', AICore.SetEntityBucket)

---No-op: Aicore does not do vehicle persistence (dirty-tracked player saves
---only). Kept so ported resources don't error.
---@return boolean
function AICore.EnablePersistence()
    return true
end

exports('EnablePersistence', AICore.EnablePersistence)
