---Aicore shared configuration. All tuning lives here.

---@class AicoreConfig
Config = {}

-- How often the coalesced save scheduler runs (minutes).
-- Players with no dirty data are skipped entirely.
Config.saveIntervalMinutes = 10

-- How many players are processed per tick inside the save scheduler.
-- Keeps a full server from hitching when the interval fires.
Config.saveBatchSize = 20

-- Vitals (hunger/thirst/stress) decay per minute. Derived from timestamps,
-- never ticked in the database.
Config.vitals = {
    hungerRate = 1.0,
    thirstRate = 1.2,
    stressRate = 0.0,
}

-- Money types tracked as real DB columns (hot path). Everything else
-- lives in the JSON metadata blob.
Config.hotMoneyTypes = { 'cash', 'bank' }

-- State-bag strict mode expectation: clients must never write state.
-- Enforce in server.cfg: `setr sv_stateBagStrictMode true`
Config.expectStateBagStrictMode = true

-- Where first-time players spawn (vec4).
Config.defaultSpawn = vec4(-1035.0, -2739.0, 20.0, 0.0)

-- Paycheck settings.
Config.paycheck = {
    enabled = true,
    intervalMinutes = 30,
}

-- Character selection.
Config.characters = {
    -- true: ox_lib multichar menu + preview camera (client/character.lua).
    -- false: instant auto-login, first character is used/created.
    useMultichar = true,
    maxCharacters = 5,
    -- Where players wait while picking a character.
    previewLocation = vec4(-1035.0, -2739.0, 20.0, 0.0),
}
