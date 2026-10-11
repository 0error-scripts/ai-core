---Aicore client core.
---Design rule: ZERO per-frame (Wait(0)) loops in core. All synchronization is
---event- and state-bag-driven, per FiveM's official performance guidance.
---Features that need proximity use ox_lib zones/points (enter/exit events),
---never distance-check loops.

local playerState = LocalPlayer.state

-- Differential player-data sync: the server sends only the key that changed.
RegisterNetEvent('aicore:client:onPlayerData', function(field, value)
    -- Handled by feature resources; core only routes.
    TriggerEvent('aicore:playerDataChanged', field, value)
end)

-- Differential metadata sync.
RegisterNetEvent('aicore:client:onMetadata', function(meta, value)
    TriggerEvent('aicore:metadataChanged', meta, value)
end)

-- Vitals are derived from timestamps server-side and replicated via state bag.
-- React on change; never poll.
AddStateBagChangeHandler('vitals', 'player:' .. GetPlayerServerId(PlayerId()),
    function(_, _, value)
        if type(value) ~= 'table' then return end
        TriggerEvent('aicore:vitalsChanged', value)
    end
)

-- Spawn flow: the server drives login, then tells the client where to appear.
-- No spawn manager dependency; plain fade + teleport.
RegisterNetEvent('aicore:client:onPlayerLoaded', function(data)
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(100) end

    local pos = data.position or Config.defaultSpawn
    local ped = PlayerPedId()
    SetEntityCoords(ped, pos.x, pos.y, pos.z, false, false, false, false)
    SetEntityHeading(ped, pos.w or 0.0)
    FreezeEntityPosition(ped, false)

    -- Let the world stream in before revealing.
    Wait(500)
    DoScreenFadeIn(500)

    TriggerEvent('aicore:playerSpawned', data)
end)

-- Once the session is up, ask the server to log us in (which fires onPlayerLoaded).
-- Skipped when the multichar UI is enabled — client/character.lua owns the flow.
CreateThread(function()
    if Config.characters.useMultichar then return end
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(1000)
    TriggerServerEvent('aicore:server:requestSpawn')
end)

-- Notification relay for AICore.Notify.
RegisterNetEvent('aicore:client:notify', function(message, notifyType)
    lib.notify({ description = message, type = notifyType or 'info' })
end)
