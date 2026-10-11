---AicoreBridge: opt-in QBox/QBCore compatibility shim.
---Maps the most-used qb-core surface onto Aicore's API so existing scripts run
---without modification. This is a compatibility layer, not a full reimplementation:
---unsupported calls return false/nil and log a warning once.

local warned = {}

---@param key string
local function warnOnce(key, message)
    if warned[key] then return end
    warned[key] = true
    lib.print.warn(('[aicore_bridge] %s'):format(message))
end

---@param name string
---@return string firstname, string lastname
local function splitName(name)
    local first, rest = (name or 'Player'):match('^(%S+)%s*(.-)%s*$')
    if rest == '' then rest = 'Unknown' end
    return first, rest
end

---@param player Player Aicore player object
---@return table QBCore-shaped player
local function wrapPlayer(player)
    local data = player.data
    -- Aicore stores a single display name; expose it QB-style.
    local displayName = (data.metadata and data.metadata.fullname) or ('Player ' .. player.source)
    local firstname, lastname = splitName(displayName)

    local qbPlayer = {
        PlayerData = {
            source = player.source,
            citizenid = player.citizenid,
            cid = player.citizenid,
            name = displayName or ('Player ' .. player.source),
            money = { cash = data.cash or 0, bank = data.bank or 0 },
            charinfo = { firstname = firstname, lastname = lastname },
            job = {
                name = (data.job or {}).name or 'unemployed',
                grade = { level = (data.job or {}).grade or 0 },
                onduty = true,
            },
            gang = {
                name = (data.gang or {}).name or 'none',
                grade = { level = (data.gang or {}).grade or 0 },
            },
            metadata = data.metadata or {},
            position = data.position,
        },
        Functions = {},
    }

    local F = qbPlayer.Functions
    function F.AddMoney(moneytype, amount, _reason)
        return player:AddMoney(moneytype, amount)
    end
    function F.RemoveMoney(moneytype, amount, _reason)
        return player:RemoveMoney(moneytype, amount)
    end
    function F.SetMoney(moneytype, amount, _reason)
        local current = player:GetMoney(moneytype)
        amount = math.floor(tonumber(amount) or 0)
        if amount > current then
            return player:AddMoney(moneytype, amount - current)
        elseif amount < current then
            return player:RemoveMoney(moneytype, current - amount)
        end
        return true
    end
    function F.GetMoney(moneytype)
        return player:GetMoney(moneytype)
    end
    function F.SetJob(jobName, grade)
        return AICore.SetPlayerJob(player.source, jobName, grade or 0)
    end
    function F.SetGang(gangName, grade)
        return AICore.SetPlayerGang(player.source, gangName, grade or 0)
    end
    function F.GetJob()
        return qbPlayer.PlayerData.job
    end
    function F.SetMetaData(meta, value)
        player:SetMetadata(meta, value)
        return true
    end
    function F.GetMetaData(meta)
        return player:GetMetadata(meta)
    end
    function F.Save()
        return exports.aicore:SavePlayer(player.source)
    end
    -- Inventory lives in ox_inventory, not the core.
    function F.AddItem()
        warnOnce('items', 'Functions.AddItem is not provided by the core; use ox_inventory exports directly')
        return false
    end
    function F.RemoveItem()
        warnOnce('items', 'Functions.RemoveItem is not provided by the core; use ox_inventory exports directly')
        return false
    end

    return qbPlayer
end

---@class QBCoreCompat
local QBCore = { Functions = {} }

function QBCore.Functions.GetPlayer(source)
    local player = exports.aicore:GetPlayer(source)
    return player and wrapPlayer(player) or nil
end

function QBCore.Functions.GetPlayerByCitizenId(citizenid)
    local player = exports.aicore:GetPlayerByCitizenId(citizenid)
    return player and wrapPlayer(player) or nil
end

function QBCore.Functions.GetPlayers()
    return exports.aicore:GetPlayers()
end

-- Forward core lifecycle events under QBCore names for listening scripts.
AddEventHandler('aicore:server:onPlayerLoaded', function(source)
    TriggerEvent('QBCore:Server:OnPlayerLoaded', source)
    TriggerClientEvent('QBCore:Client:OnPlayerLoaded', source)
end)

AddEventHandler('aicore:server:onPlayerUnload', function(source)
    TriggerEvent('QBCore:Server:OnPlayerUnload', source)
    TriggerClientEvent('QBCore:Client:OnPlayerUnload', source)
end)

exports('GetCoreObject', function()
    return QBCore
end)

lib.print.info('AicoreBridge loaded: qb-core compatibility shim active')
