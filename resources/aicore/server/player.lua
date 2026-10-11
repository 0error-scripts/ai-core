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

---@param amount number
---@return boolean valid finite positive number
local function validMoneyAmount(amount)
    return type(amount) == 'number' and amount == amount and amount ~= math.huge and amount ~= -math.huge and amount > 0 and amount < 1e12
end

---Server-validated money add. Never trusts client-supplied amounts.
---@param self Player
---@param moneytype 'cash'|'bank'
---@param amount number
---@return boolean ok
function PlayerMethods:AddMoney(moneytype, amount)
    if moneytype ~= 'cash' and moneytype ~= 'bank' then return false end
    if not validMoneyAmount(amount) then return false end
    amount = math.floor(amount)
    self.data[moneytype] = (self.data[moneytype] or 0) + amount
    self.dirty[moneytype] = true
    TriggerClientEvent('aicore:client:onPlayerData', self.source, moneytype, self.data[moneytype])
    TriggerEvent('aicore:server:onMoneyChange', self.source, moneytype, amount, self.data[moneytype])
    return true
end

---@param self Player
---@param moneytype 'cash'|'bank'
---@param amount number
---@return boolean ok false when insufficient funds or invalid
function PlayerMethods:RemoveMoney(moneytype, amount)
    if moneytype ~= 'cash' and moneytype ~= 'bank' then return false end
    if not validMoneyAmount(amount) then return false end
    amount = math.floor(amount)
    if (self.data[moneytype] or 0) < amount then return false end
    self.data[moneytype] = self.data[moneytype] - amount
    self.dirty[moneytype] = true
    TriggerClientEvent('aicore:client:onPlayerData', self.source, moneytype, self.data[moneytype])
    TriggerEvent('aicore:server:onMoneyChange', self.source, moneytype, -amount, self.data[moneytype])
    return true
end

---@param self Player
---@param moneytype 'cash'|'bank'
---@return number
function PlayerMethods:GetMoney(moneytype)
    return self.data[moneytype] or 0
end

---Vitals are time-derived: base values + timestamp, decay applied on read.
---Nothing is ticked in the database.
---@param self Player
---@return {hunger:number, thirst:number, stress:number}
function PlayerMethods:GetVitals()
    local v = self.data.vitals
    local elapsedMinutes = math.max(0, (os.time() - (v.updatedAt or os.time())) / 60)
    return {
        hunger = math.max(0, (v.hunger or 100) - elapsedMinutes * Config.vitals.hungerRate),
        thirst = math.max(0, (v.thirst or 100) - elapsedMinutes * Config.vitals.thirstRate),
        stress = v.stress or 0,
    }
end

---@param self Player
---@param hunger? number
---@param thirst? number
---@param stress? number
function PlayerMethods:SetVitals(hunger, thirst, stress)
    local current = self:GetVitals()
    self.data.vitals = {
        hunger = hunger ~= nil and math.min(100, math.max(0, hunger)) or current.hunger,
        thirst = thirst ~= nil and math.min(100, math.max(0, thirst)) or current.thirst,
        stress = stress ~= nil and math.min(100, math.max(0, stress)) or current.stress,
        updatedAt = os.time(),
    }
    self.dirty['vitals'] = true
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

---Force a partial save for one player. Used by the compatibility bridge.
---@param source Source
---@return boolean saved
function AICore.SavePlayer(source)
    local player = AICore.GetPlayer(source)
    if not player or not player:IsDirty() then return false end
    local Storage = require 'server.storage'
    local ok, err = pcall(Storage.savePartial, player.citizenid, player.dirty, player.data)
    if ok then player:MarkClean() end
    if not ok then lib.print.error(('SavePlayer failed for %s: %s'):format(player.citizenid, err)) end
    return ok
end

exports('SavePlayer', AICore.SavePlayer)
