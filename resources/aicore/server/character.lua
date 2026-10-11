---Aicore character lifecycle: login, logout, create, delete.
---Login loads the entity, builds the player object, registers it, and tells
---the client to spawn. Logout does a full save and unregisters.

local Storage = require 'server.storage'

---@param identifiers string[]
---@return string license
local function primaryLicense(identifiers)
    for i = 1, #identifiers do
        if identifiers[i]:sub(1, 8) == 'license:' then
            return identifiers[i]
        end
    end
    return identifiers[1] or 'unknown'
end

---@param source Source
---@return string license
function AICore.GetPlayerLicense(source)
    return primaryLicense(GetPlayerIdentifiers(source))
end

---@param source Source
---@param citizenid string
---@return boolean ok
---@return string? err
function AICore.Login(source, citizenid)
    if AICore.GetPlayer(source) then return false, 'already_logged_in' end

    local entity = Storage.fetchPlayerEntity(citizenid)
    if not entity then return false, 'character_not_found' end

    local identifiers = GetPlayerIdentifiers(source)
    local player = AICore.CreatePlayer(source, citizenid, entity.userId or 0, identifiers, {
        cash = entity.cash or 0,
        bank = entity.bank or 0,
        position = entity.position or Config.defaultSpawn,
        vitals = entity.vitals or { hunger = 100.0, thirst = 100.0, stress = 0.0, updatedAt = os.time() },
        metadata = entity.metadata or {},
        job = entity.job or { name = 'unemployed', grade = 0 },
        gang = entity.gang or { name = 'none', grade = 0 },
    })

    AICore.RegisterPlayer(source, player)
    AICore.AttachCompatShape(player, entity.name or citizenid)
    Player(source).state:set('isLoggedIn', true, true)

    TriggerClientEvent('aicore:client:onPlayerLoaded', source, {
        citizenid = citizenid,
        cash = player.data.cash,
        bank = player.data.bank,
        position = player.data.position,
        vitals = player:GetVitals(),
        metadata = player.data.metadata,
        job = player.data.job,
        gang = player.data.gang,
    })
    TriggerEvent('aicore:server:onPlayerLoaded', source)

    return true
end

---@param source Source
function AICore.Logout(source)
    local player = AICore.GetPlayer(source)
    if not player then return end
    local ok, err = pcall(Storage.saveFull, player.citizenid, player.data)
    if not ok then
        lib.print.error(('logout save failed for %s: %s'):format(player.citizenid, err))
    end
    AICore.UnregisterPlayer(source)
    TriggerEvent('aicore:server:onPlayerUnload', source)
end

---@param source Source
---@param name string display name for the new character
---@return string? citizenid
function AICore.CreateCharacter(source, name)
    if type(name) ~= 'string' or #name < 2 or #name > 60 then return nil end
    local identifiers = GetPlayerIdentifiers(source)
    local license = primaryLicense(identifiers)
    local userId = MySQL.scalar.await('SELECT `user_id` FROM `players` WHERE `license` = ? LIMIT 1', { license }) or 0
    return Storage.createCharacter(userId, license, name)
end

---@param source Source
---@param citizenid string
---@return boolean ok
function AICore.DeleteCharacter(source, citizenid)
    local identifiers = GetPlayerIdentifiers(source)
    local license = primaryLicense(identifiers)
    local owner = MySQL.scalar.await('SELECT `license` FROM `players` WHERE `citizenid` = ? LIMIT 1', { citizenid })
    if owner ~= license then return false end
    local player = AICore.GetPlayer(source)
    if player and player.citizenid == citizenid then
        AICore.Logout(source)
    end
    Storage.deleteCharacter(citizenid)
    return true
end

exports('Login', AICore.Login)
exports('Logout', AICore.Logout)
exports('CreateCharacter', AICore.CreateCharacter)
exports('DeleteCharacter', AICore.DeleteCharacter)

---Multichar select flow: client picked a character from the menu.
---Ownership is verified server-side before login.
RegisterNetEvent('aicore:server:selectCharacter', function(citizenid)
    local source = source --[[@as Source]]
    if AICore.GetPlayer(source) then return end
    if type(citizenid) ~= 'string' then return end

    local owner = MySQL.scalar.await('SELECT `license` FROM `players` WHERE `citizenid` = ? LIMIT 1', { citizenid })
    if owner ~= AICore.GetPlayerLicense(source) then
        lib.print.warn(('selectCharacter: license mismatch for source %s'):format(source))
        return
    end

    local ok, err = AICore.Login(source, citizenid)
    if not ok then
        DropPlayer(source, ('Aicore: login failed (%s).'):format(err or 'unknown'))
    end
end)

---Multichar delete flow: verify ownership, delete, tell the client to refresh.
RegisterNetEvent('aicore:server:deleteCharacter', function(citizenid)
    local source = source --[[@as Source]]
    if type(citizenid) ~= 'string' then return end
    local ok = AICore.DeleteCharacter(source, citizenid)
    TriggerClientEvent('aicore:client:characterDeleted', source, ok)
end)
