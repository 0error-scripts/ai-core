---Aicore client PlayerData (shared module).
---Ported from QBox Project qbx_core (GPL-3.0) under GPL-3.0.
---Original work © QBox Project contributors.
---
---Keeps a QB-shaped `AICORE.PlayerData` table live on the client, fed by
---the core's differential events. Satellites include this via
---`shared_script '@aicore/modules/playerdata.lua'`.

if IsDuplicityVersion() then return end

AICORE = AICORE or {} -- luacheck: ignore
AICORE.PlayerData = AICORE.PlayerData or {} -- luacheck: ignore

RegisterNetEvent('aicore:client:onPlayerLoaded', function(data)
    AICORE.PlayerData = {
        citizenid = data.citizenid,
        name = data.name,
        charinfo = data.charinfo or {},
        money = { cash = data.cash or 0, bank = data.bank or 0 },
        job = data.job or {},
        gang = data.gang or {},
        metadata = data.metadata or {},
    }
end)

-- Differential field updates from the server.
RegisterNetEvent('aicore:client:onPlayerData', function(field, value)
    local pd = AICORE.PlayerData
    if field == 'cash' or field == 'bank' then
        pd.money = pd.money or {}
        pd.money[field] = value
    elseif field == 'job' or field == 'gang' or field == 'metadata' then
        pd[field] = value
    end
end)

RegisterNetEvent('aicore:client:onMetadata', function(meta, value)
    AICORE.PlayerData.metadata = AICORE.PlayerData.metadata or {}
    AICORE.PlayerData.metadata[meta] = value
end)

RegisterNetEvent('aicore:client:onJobUpdate', function(job)
    AICORE.PlayerData.job = job
end)

RegisterNetEvent('aicore:client:onGangUpdate', function(gang)
    AICORE.PlayerData.gang = gang
end)

-- Cleared on logout (forwarded by the compat bridge under QB names).
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    AICORE.PlayerData = {} -- luacheck: ignore
end)
