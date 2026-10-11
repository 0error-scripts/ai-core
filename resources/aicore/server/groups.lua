---Aicore groups: lean jobs & gangs registry + per-player assignment.
---Job definitions live here (or are added via AICore.AddJob); assignment is
---server-validated and dirty-tracked like everything else.

---@class JobGrade {name:string, payment:integer}
---@class JobDef {label:string, type?:string, grades:table<integer, JobGrade>}

---@type table<string, JobDef>
AICore.Jobs = {
    unemployed = {
        label = 'Unemployed',
        type = 'none',
        grades = { [0] = { name = 'Freeloader', payment = 10 } },
    },
}

---@type table<string, JobDef>
AICore.Gangs = {
    none = {
        label = 'None',
        grades = { [0] = { name = 'Outsider', payment = 0 } },
    },
}

---@param name string
---@param def JobDef
function AICore.AddJob(name, def)
    AICore.Jobs[name] = def
end

---@param name string
---@param def JobDef
function AICore.AddGang(name, def)
    AICore.Gangs[name] = def
end

---@param source Source
---@param jobName string
---@param grade? integer
---@return boolean ok
function AICore.SetPlayerJob(source, jobName, grade)
    local player = AICore.GetPlayer(source)
    local def = jobName and AICore.Jobs[jobName]
    if not player or not def then return false end
    grade = math.tointeger(grade) or 0
    if not def.grades[grade] then return false end
    -- Preserve duty state across job/grade changes.
    local onduty = player.data.job and player.data.job.onduty or false
    player:Set('job', { name = jobName, grade = grade, onduty = onduty })
    TriggerEvent('aicore:server:onJobUpdate', source, player.data.job)
    TriggerClientEvent('aicore:client:onJobUpdate', source, player.data.job)
    return true
end

---@param source Source
---@param gangName string
---@param grade? integer
---@return boolean ok
function AICore.SetPlayerGang(source, gangName, grade)
    local player = AICore.GetPlayer(source)
    local def = gangName and AICore.Gangs[gangName]
    if not player or not def then return false end
    grade = math.tointeger(grade) or 0
    if not def.grades[grade] then return false end
    player:Set('gang', { name = gangName, grade = grade })
    TriggerEvent('aicore:server:onGangUpdate', source, player.data.gang)
    TriggerClientEvent('aicore:client:onGangUpdate', source, player.data.gang)
    return true
end

---@param jobName string
---@return JobDef?
function AICore.GetJob(jobName)
    return AICore.Jobs[jobName]
end

exports('SetPlayerJob', AICore.SetPlayerJob)
exports('SetPlayerGang', AICore.SetPlayerGang)
exports('GetJob', AICore.GetJob)
exports('AddJob', AICore.AddJob)
