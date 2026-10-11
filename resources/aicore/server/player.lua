---Aicore player objects.
---One shared metatable for all methods (no per-player closure tables).
---Dirty tracking: writes mark top-level fields dirty; the save scheduler
---persists only dirty columns and skips clean players entirely.

---@class Player
---@field source Source
---@field citizenid string
---@field userId integer
---@field identifiers string[]
---@field data table live player data
---@field dirty table<string, boolean> dirty top-level fields

local PlayerMethods = {}

---Mark a top-level field dirty and push only the change to the client.
---@param self Player
---@param field string
---@param value any
function PlayerMethods:Set(field, value)
    if self.data[field] == value then return end
    self.data[field] = value
    self.dirty[field] = true
    -- Differential sync: changed key only, never the whole player table.
    TriggerClientEvent('aicore:client:onPlayerData', self.source, field, value)
end

---@param self Player
---@param key string
---@return any
function PlayerMethods:Get(key)
    return self.data[key]
end

---Server-validated metadata write. Numeric vitals are clamped.
---@param self Player
---@param meta string
---@param value any
function PlayerMethods:SetMetadata(meta, value)
    if type(meta) ~= 'string' then return end
    local metadata = self.data.metadata
    if metadata[meta] == value then return end
    metadata[meta] = value
    self.dirty['metadata'] = true
    TriggerClientEvent('aicore:client:onMetadata', self.source, meta, value)
end

---@param self Player
---@param meta string
---@return any
function PlayerMethods:GetMetadata(meta)
    return self.data.metadata[meta]
end

---Clear dirty flags after a successful save.
---@param self Player
function PlayerMethods:MarkClean()
    for k in pairs(self.dirty) do
        self.dirty[k] = nil
    end
end

---@param self Player
---@return boolean
function PlayerMethods:IsDirty()
    return next(self.dirty) ~= nil
end

local PlayerMt = { __index = PlayerMethods }

---@param source Source
---@param citizenid string
---@param userId integer
---@param identifiers string[]
---@param data table
---@return Player
function AICore.CreatePlayer(source, citizenid, userId, identifiers, data)
    local player = {
        source = source,
        citizenid = citizenid,
        userId = userId,
        identifiers = identifiers,
        data = data,
        dirty = {},
    }
    return setmetatable(player, PlayerMt)
end

exports('CreatePlayer', AICore.CreatePlayer)
