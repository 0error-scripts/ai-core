---Aicore shared server functions: notifications, permissions, listings.

---@param source Source
---@param message string
---@param notifyType? 'success'|'error'|'info'
function AICore.Notify(source, message, notifyType)
    TriggerClientEvent('aicore:client:notify', source, message, notifyType or 'info')
end

---@param source Source
---@param ace string e.g. 'aicore.admin'
---@return boolean
function AICore.HasPermission(source, ace)
    return IsPlayerAceAllowed(source, ace)
end

---@return Source[] online player sources
function AICore.GetPlayers()
    local out = {}
    for src in pairs(AICore.Players) do
        out[#out + 1] = src
    end
    return out
end

---@return integer count
function AICore.GetPlayerCount()
    local n = 0
    for _ in pairs(AICore.Players) do n += 1 end
    return n
end

exports('Notify', AICore.Notify)
exports('HasPermission', AICore.HasPermission)
exports('GetPlayers', AICore.GetPlayers)
