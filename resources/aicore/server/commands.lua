---Aicore admin commands (ox_lib, ACE-gated).

-- Force-save one player (or all dirty players when no id given).
lib.addCommand('aicore_save', {
    help = 'Force-save player data (admin)',
    params = {
        { name = 'id', type = 'playerId', optional = true, help = 'Player server id' },
    },
    restricted = 'aicore.admin',
}, function(source, args)
    local Storage = require 'server.storage'
    local count = 0
    if args.id then
        local player = AICore.GetPlayer(args.id)
        if player and player:IsDirty() then
            Storage.savePartial(player.citizenid, player.dirty, player.data)
            player:MarkClean()
            count = 1
        end
    else
        for _, player in pairs(AICore.Players) do
            if player:IsDirty() then
                local ok = pcall(Storage.savePartial, player.citizenid, player.dirty, player.data)
                if ok then player:MarkClean() count += 1 end
            end
        end
    end
    AICore.Notify(source, ('Saved %d player(s).'):format(count), 'success')
end)

-- Set a player's job (validates job + grade server-side).
lib.addCommand('aicore_setjob', {
    help = 'Set a player job (admin)',
    params = {
        { name = 'id', type = 'playerId', help = 'Player server id' },
        { name = 'job', type = 'string', help = 'Job name' },
        { name = 'grade', type = 'number', optional = true, help = 'Grade level' },
    },
    restricted = 'aicore.admin',
}, function(source, args)
    local ok = AICore.SetPlayerJob(args.id, args.job, args.grade or 0)
    AICore.Notify(source, ok and 'Job updated.' or 'Invalid job or grade.', ok and 'success' or 'error')
end)

-- Give money (admin; every grant is validated + logged via onMoneyChange).
lib.addCommand('aicore_givemoney', {
    help = 'Give a player money (admin)',
    params = {
        { name = 'id', type = 'playerId', help = 'Player server id' },
        { name = 'type', type = 'string', help = 'cash or bank' },
        { name = 'amount', type = 'number', help = 'Amount' },
    },
    restricted = 'aicore.admin',
}, function(source, args)
    local player = AICore.GetPlayer(args.id)
    local ok = player and player:AddMoney(args.type, args.amount)
    AICore.Notify(source, ok and 'Money granted.' or 'Invalid type or amount.', ok and 'success' or 'error')
end)
