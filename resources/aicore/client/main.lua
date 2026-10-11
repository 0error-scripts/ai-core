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
