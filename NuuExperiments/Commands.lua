local _, ns = ...

-- /nuux (/nuuexp):
--   /nuux              the experiments window (Window.lua); without the kit, the list
--   /nuux list         the loaded experiments and how each last went, in chat
--   /nuux run <id|all> run now (results replace the last ones), then show them
--   /nuux show <id|all> the last results in a window, to copy
--   /nuux clear <id|all> forget results
--   /nuux prune        forget the results of experiments no longer loaded
-- The game writes the results to disk on /reload or logout.

local function list()
    local results = ns:DB().results
    if #ns.order == 0 then ns:Print("no experiments loaded") end
    for _, id in ipairs(ns.order) do
        local experiment, last = ns.experiments[id], results[id]
        local auto = experiment.auto == false and "manual" or experiment.auto
        ns:Print(string.format("%s (%s): %s", id, auto,
            last and (last.status .. ", " .. tostring(last.build) .. ", " .. tostring(last.date)) or "not run"))
    end
    local stale = 0
    for id in pairs(results) do
        if not ns.experiments[id] then stale = stale + 1 end
    end
    if stale > 0 then ns:Print(stale .. " result(s) of retired experiments kept; /nuux prune forgets them") end
end

local function show(id)
    local ids = {}
    if id == "all" then
        for _, each in ipairs(ns.order) do ids[#ids + 1] = each end
    elseif ns:DB().results[id] then
        ids[1] = id
    else
        return ns:Print("no results for " .. tostring(id))
    end
    ns:ShowResults(ids)
end

local function clear(id)
    local results = ns:DB().results
    if id == "all" then
        wipe(results)
    else
        results[id] = nil
    end
    ns:Print("cleared " .. id)
    ns:Changed()
end

-- Forgets the results of experiments no longer loaded; answers how many.
function ns:Prune()
    local results, count = self:DB().results, 0
    for id in pairs(results) do
        if not self.experiments[id] then
            results[id] = nil
            count = count + 1
        end
    end
    self:Changed()
    return count
end

local function prune()
    ns:Print("forgot " .. ns:Prune() .. " retired result(s)")
end

local function run(id)
    local ids = {}
    if id == "all" then
        for _, each in ipairs(ns.order) do ids[#ids + 1] = each end
    elseif ns.experiments[id] then
        ids[1] = id
    else
        return ns:Run(id)
    end
    -- Shown together once the last of them is done.
    ns:ShowWhenDone(ids)
    for _, each in ipairs(ids) do ns:Run(each) end
end

SLASH_NUUEXPERIMENTS1 = "/nuux"
SLASH_NUUEXPERIMENTS2 = "/nuuexp"
SlashCmdList.NUUEXPERIMENTS = function(message)
    local command, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    if command == "" then
        if not ns:OpenWindow() then list() end
    elseif command == "list" then
        list()
    elseif command == "run" and rest ~= "" then
        run(rest)
    elseif command == "show" and rest ~= "" then
        show(rest)
    elseif command == "clear" and rest ~= "" then
        clear(rest)
    elseif command == "prune" then
        prune()
    else
        ns:Print("/nuux [list | run <id|all> | show <id|all> | clear <id|all> | prune]")
    end
end
