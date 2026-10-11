---Aicore coalesced save scheduler.
---One loop. Snapshots the player list, processes in staggered batches,
---skips players with no dirty data. A full server never hitches on save.

local Storage = require 'server.storage'

local SAVE_INTERVAL_MS = 60000 * Config.saveIntervalMinutes
local BATCH_SIZE = Config.saveBatchSize

CreateThread(function()
    while true do
        Wait(SAVE_INTERVAL_MS)

        -- Snapshot so joins/drops during yields can't corrupt iteration.
        local sources = {}
        for src in pairs(AICore.Players) do
            sources[#sources + 1] = src
        end

        for i = 1, #sources do
            local player = AICore.Players[sources[i]]
            if player and player:IsDirty() then
                local ok, err = pcall(Storage.savePartial, player.citizenid, player.dirty, player.data)
                if ok then
                    player:MarkClean()
                else
                    lib.print.error(('save failed for %s: %s'):format(player.citizenid, err))
                end
            end
            if i % BATCH_SIZE == 0 then
                Wait(0)
            end
        end
    end
end)

---Paycheck loop. Staggered like the save scheduler; pays the grade's configured
---amount into bank. Skipped entirely when paychecks are disabled in config.
CreateThread(function()
    if not Config.paycheck.enabled then return end
    while true do
        Wait(60000 * Config.paycheck.intervalMinutes)

        local sources = {}
        for src in pairs(AICore.Players) do
            sources[#sources + 1] = src
        end

        for i = 1, #sources do
            local player = AICore.Players[sources[i]]
            if player then
                local job = player.data.job or {}
                local def = job.name and AICore.GetJob(job.name)
                local grade = def and def.grades[job.grade or 0]
                local amount = grade and grade.payment or 0
                if amount > 0 then
                    player:AddMoney('bank', amount)
                end
            end
            if i % Config.saveBatchSize == 0 then
                Wait(0)
            end
        end
    end
end)
