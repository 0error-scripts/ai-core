---Aicore storage adapter.
---Partial updates only: callers pass the player's dirty set and only those
---columns are written. Full-row writes happen on logout/migration only.

local Storage = {}

local DIRTY_COLUMN_MAP = {
    cash = '`cash` = ?',
    bank = '`bank` = ?',
    position = '`position` = ?',
    metadata = '`metadata` = ?',
    job = '`job` = ?',
    gang = '`gang` = ?',
}

---Persist only the dirty fields of a player.
---@param citizenid string
---@param dirty table<string, boolean>
---@param data table live player data
function Storage.savePartial(citizenid, dirty, data)
    local sets, values = {}, {}
    for field in pairs(dirty) do
        local col = DIRTY_COLUMN_MAP[field]
        if col then
            sets[#sets + 1] = col
            local value = data[field]
            values[#values + 1] = type(value) == 'table' and json.encode(value) or value
        end
    end
    if #sets == 0 then return end
    values[#values + 1] = citizenid
    MySQL.update.await(
        ('UPDATE `players` SET %s WHERE `citizenid` = ?'):format(table.concat(sets, ', ')),
        values
    )
end

---Full-row write. Logout / migration path only.
---@param citizenid string
---@param data table
function Storage.saveFull(citizenid, data)
    MySQL.update.await(
        'UPDATE `players` SET `cash` = ?, `bank` = ?, `position` = ?, `metadata` = ?, `job` = ?, `gang` = ? WHERE `citizenid` = ?',
        {
            data.cash, data.bank,
            json.encode(data.position),
            json.encode(data.metadata),
            json.encode(data.job),
            json.encode(data.gang),
            citizenid,
        }
    )
end

---Ensure hot columns exist. Hot fields are real indexed columns;
---cold data stays JSON. No JSON_EXTRACT in hot filters.
function Storage.ensureSchema()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `players` (
            `citizenid` varchar(50) NOT NULL,
            `cash` int NOT NULL DEFAULT 0,
            `bank` int NOT NULL DEFAULT 0,
            `position` text,
            `metadata` text,
            `job` text,
            `gang` text,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

return Storage
