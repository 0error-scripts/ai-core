---Aicore server events: connect deferrals (ban check), drop handling,
---and the client-driven spawn request flow.
---v0.1 flow: on spawn request the server ensures the player has at least one
---character (auto-creating on first join), logs them in, and the client spawns.
---A multicharacter selection UI can replace the auto-select later.

local Storage = require 'server.storage'

CreateThread(function()
    Storage.ensureSchema()
    lib.print.info('Aicore core initialized')
end)

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local source = source
    deferrals.defer()
    deferrals.update('Checking Aicore...')
    Wait(0)

    local identifiers = GetPlayerIdentifiers(source)
    local ban = Storage.fetchBan(identifiers)
    if ban then
        local msg = ('You are banned%s'):format(ban.reason and (': ' .. ban.reason) or '.')
        deferrals.done(msg)
        return
    end

    deferrals.done()
end)

AddEventHandler('playerDropped', function()
    AICore.Logout(source --[[@as Source]])
end)

---Client calls this when it's ready to enter the world.
lib.callback.register('aicore:server:getCharacters', function(source)
    local identifiers = GetPlayerIdentifiers(source)
    local license
    for i = 1, #identifiers do
        if identifiers[i]:sub(1, 8) == 'license:' then license = identifiers[i] break end
    end
    return Storage.fetchCharacterList(license or 'unknown')
end)

RegisterNetEvent('aicore:server:requestSpawn', function()
    local source = source --[[@as Source]]
    if AICore.GetPlayer(source) then return end -- already in world

    local identifiers = GetPlayerIdentifiers(source)
    local license
    for i = 1, #identifiers do
        if identifiers[i]:sub(1, 8) == 'license:' then license = identifiers[i] break end
    end
    license = license or 'unknown'

    local chars = Storage.fetchCharacterList(license)
    local citizenid = chars[1] and chars[1].citizenid
    if not citizenid then
        -- First join: auto-create a character so the core is usable with no UI.
        citizenid = AICore.CreateCharacter(source, GetPlayerName(source) or 'Player')
        if not citizenid then
            DropPlayer(source, 'Aicore: character creation failed.')
            return
        end
    end

    local ok, err = AICore.Login(source, citizenid)
    if not ok then
        DropPlayer(source, ('Aicore: login failed (%s).'):format(err or 'unknown'))
    end
end)

RegisterNetEvent('aicore:server:createCharacter', function(name)
    local source = source --[[@as Source]]
    local citizenid = AICore.CreateCharacter(source, name)
    TriggerClientEvent('aicore:client:characterCreated', source, citizenid ~= nil)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Flush every dirty player on shutdown so nothing is lost.
    for src, player in pairs(AICore.Players) do
        if player:IsDirty() then
            local ok, err = pcall(Storage.savePartial, player.citizenid, player.dirty, player.data)
            if ok then player:MarkClean() end
            if not ok then lib.print.error(('shutdown save failed for %s: %s'):format(player.citizenid, err)) end
        end
    end
end)
