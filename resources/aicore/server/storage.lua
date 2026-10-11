---Aicore storage adapter.
---Partial updates only: callers pass the player's dirty set and only those
---columns are written. Full-row writes happen on logout/migration only.
---Hot fields (cash, bank, position, vitals) are real indexed columns;
---cold data stays JSON. No JSON_EXTRACT in hot filters.

local Storage = {}

local DIRTY_COLUMN_MAP = {
    cash = '`cash` = ?',
    bank = '`bank` = ?',
    position = '`position` = ?',
    vitals = '`vitals` = ?',
    metadata = '`metadata` = ?',
    job = '`job` = ?',
    gang = '`gang` = ?',
}

---@param value any
---@return any
local function encodeIfTable(value)
    return type(value) == 'table' and json.encode(value) or value
end

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
            values[#values + 1] = encodeIfTable(data[field])
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
        'UPDATE `players` SET `cash` = ?, `bank` = ?, `position` = ?, `vitals` = ?, `metadata` = ?, `job` = ?, `gang` = ? WHERE `citizenid` = ?',
        {
            data.cash, data.bank,
            json.encode(data.position),
            json.encode(data.vitals),
            json.encode(data.metadata),
            json.encode(data.job),
            json.encode(data.gang),
            citizenid,
        }
    )
end

---@param row table
---@return table entity
local function decodeEntity(row)
    return {
        citizenid = row.citizenid,
        userId = row.user_id,
        license = row.license,
        name = row.name,
        cash = row.cash,
        bank = row.bank,
        position = row.position and json.decode(row.position) or nil,
        vitals = row.vitals and json.decode(row.vitals) or nil,
        metadata = row.metadata and json.decode(row.metadata) or {},
        job = row.job and json.decode(row.job) or nil,
        gang = row.gang and json.decode(row.gang) or nil,
    }
end

---@param citizenid string
---@return table? entity
function Storage.fetchPlayerEntity(citizenid)
    local row = MySQL.single.await('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', { citizenid })
    return row and decodeEntity(row) or nil
end

---@param license string
---@return table[] entities (lightweight: citizenid, name only)
function Storage.fetchCharacterList(license)
    return MySQL.query.await('SELECT `citizenid`, `name` FROM `players` WHERE `license` = ? ORDER BY `id`', { license }) or {}
end

---@return string citizenid
function Storage.generateCitizenId()
    local citizenid
    repeat
        citizenid = ('AC%06d'):format(math.random(0, 999999))
        local exists = MySQL.scalar.await('SELECT 1 FROM `players` WHERE `citizenid` = ? LIMIT 1', { citizenid })
        if not exists then break end
    until false
    return citizenid
end

---@param userId integer
---@param license string
---@param name string
---@return string citizenid
function Storage.createCharacter(userId, license, name)
    local citizenid = Storage.generateCitizenId()
    MySQL.insert.await(
        'INSERT INTO `players` (`citizenid`, `user_id`, `license`, `name`, `cash`, `bank`) VALUES (?, ?, ?, ?, 0, 0)',
        { citizenid, userId, license, name }
    )
    return citizenid
end

---@param citizenid string
function Storage.deleteCharacter(citizenid)
    MySQL.query.await('DELETE FROM `players` WHERE `citizenid` = ?', { citizenid })
end

---@param identifiers string[]
---@return table? ban {reason: string, expire: integer}
function Storage.fetchBan(identifiers)
    if #identifiers == 0 then return nil end
    local placeholders = {}
    for i = 1, #identifiers do placeholders[i] = '?' end
    local row = MySQL.single.await(
        ('SELECT `reason`, `expire` FROM `bans` WHERE `identifier` IN (%s) ORDER BY `expire` DESC LIMIT 1'):format(table.concat(placeholders, ', ')),
        identifiers
    )
    if row and (row.expire == 0 or row.expire > os.time()) then
        return { reason = row.reason, expire = row.expire }
    end
    return nil
end

---@param identifier string
---@param reason string
---@param expire integer 0 = permanent, else unix timestamp
---@param bannedBy string
function Storage.insertBan(identifier, reason, expire, bannedBy)
    MySQL.insert.await(
        'INSERT INTO `bans` (`identifier`, `reason`, `expire`, `banned_by`) VALUES (?, ?, ?, ?)',
        { identifier, reason, expire, bannedBy }
    )
end

---Ensure schema. Hot columns are real columns; bans are a flat table.
function Storage.ensureSchema()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `players` (
            `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `user_id` int UNSIGNED DEFAULT NULL,
            `license` varchar(50) DEFAULT NULL,
            `name` varchar(100) DEFAULT NULL,
            `cash` int NOT NULL DEFAULT 0,
            `bank` int NOT NULL DEFAULT 0,
            `position` text,
            `vitals` text,
            `metadata` text,
            `job` text,
            `gang` text,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_citizenid` (`citizenid`),
            KEY `idx_license` (`license`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `bans` (
            `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
            `identifier` varchar(60) NOT NULL,
            `reason` varchar(255) DEFAULT NULL,
            `expire` int UNSIGNED NOT NULL DEFAULT 0,
            `banned_by` varchar(100) DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end

return Storage
