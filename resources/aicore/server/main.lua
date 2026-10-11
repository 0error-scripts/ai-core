---Aicore core registry. O(1) player lookups, maintained on load/unload.

AICore = {}

---@type table<Source, Player>
AICore.Players = {}

-- Reverse lookup maps: citizenid / userId / identifier -> source.
-- Never scan the player list; fast paths revalidate and fall back to a scan
-- so they can never return stale data.
AICore.Registry = {
    ---@type table<string, Source>
    byCitizenId = {},
    ---@type table<integer, Source>
    byUserId = {},
    ---@type table<string, string>
    byIdentifier = {},
}

---@param source Source
---@param player Player
function AICore.RegisterPlayer(source, player)
    AICore.Players[source] = player
    AICore.Registry.byCitizenId[player.citizenid] = source
    AICore.Registry.byUserId[player.userId] = source
    for _, identifier in ipairs(player.identifiers) do
        AICore.Registry.byIdentifier[identifier] = source
    end
end

---@param source Source
function AICore.UnregisterPlayer(source)
    local player = AICore.Players[source]
    if not player then return end
    AICore.Registry.byCitizenId[player.citizenid] = nil
    AICore.Registry.byUserId[player.userId] = nil
    for _, identifier in ipairs(player.identifiers) do
        AICore.Registry.byIdentifier[identifier] = nil
    end
    AICore.Players[source] = nil
end

---@param source Source
---@return Player?
function AICore.GetPlayer(source)
    return AICore.Players[source]
end

---@param citizenid string
---@return Player?
function AICore.GetPlayerByCitizenId(citizenid)
    local source = AICore.Registry.byCitizenId[citizenid]
    local player = source and AICore.Players[source]
    -- Revalidate: fall back to a scan if the registry drifted.
    if player and player.citizenid == citizenid then return player end
    for src, p in pairs(AICore.Players) do
        if p.citizenid == citizenid then
            AICore.Registry.byCitizenId[citizenid] = src
            return p
        end
    end
end

exports('GetPlayer', AICore.GetPlayer)
exports('GetPlayerByCitizenId', AICore.GetPlayerByCitizenId)
