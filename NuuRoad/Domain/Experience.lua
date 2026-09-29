local _, ns = ...

-- How much experience a level step still owes, and about how many kills that
-- is: the experience of the last few kills, read from the "X dies, you gain N
-- experience." chat line, averaged, with the
-- rested bonus taken off the base so a rested kill is not counted as two. Until
-- a kill is seen, a mob of the player's own level stands in (level * 5 + 45,
-- the game's formula, times the realm rate the player gave in Options).
--
-- Session-only: the kills are evidence about the mobs in front of the player
-- now, not something worth keeping. Pure apart from the reads in Reading(), so
-- Left() and ParseMessage() are testable outside the client.
local Experience = { kills = {}, keep = 5 }

-- Experience from one level to the next, levels 1 to 59, as the classic
-- client has it. Only levels past the current one are read from here; the
-- current level's figure comes from the client, and scales these, so a realm
-- with its own curve is still roughly right.
Experience.toNext = {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- A chat format string ("%s dies, you gain %d experience.") as a Lua pattern,
-- positional forms ("%1$s") included, capturing each argument.
local function toPattern(format)
    format = format:gsub("%%%d%$", "%%")
    local out = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
    out = out:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
    return "^" .. out
end

local function formats()
    local get = rawget
    return get(_G, "COMBATLOG_XPGAIN_EXHAUSTION1") or "%s dies, you gain %d experience. (%s exp %s bonus)",
        get(_G, "COMBATLOG_XPGAIN_FIRSTPERSON") or "%s dies, you gain %d experience."
end

-- The base experience of the kill a chat line reports, rested bonus taken
-- off, or nil for any other line (quest experience names no mob).
function Experience:ParseMessage(text)
    if type(text) ~= "string" or text == "" then return nil end
    local rested, plain = formats()
    local _, gained, bonus = text:match(toPattern(rested))
    if gained then
        local base = tonumber(gained) - (tonumber(tostring(bonus):match("%d+")) or 0)
        return base > 0 and base or nil
    end
    _, gained = text:match(toPattern(plain))
    gained = tonumber(gained)
    return gained and gained > 0 and gained or nil
end

function Experience:RecordKill(base)
    table.insert(self.kills, 1, base)
    self.kills[self.keep + 1] = nil
end

function Experience:OnMessage(text)
    local Client = ns.modules.Client
    if Client and Client.IsSecret and Client:IsSecret(text) then return false end
    local base = self:ParseMessage(text)
    if not base then return false end
    self:RecordKill(base)
    return true
end

-- Experience one kill is worth now: the recent average, else a mob of the
-- player's level.
function Experience:PerKill(level, rate)
    if #self.kills > 0 then
        local sum = 0
        for _, xp in ipairs(self.kills) do sum = sum + xp end
        return sum / #self.kills
    end
    return (level * 5 + 45) * (tonumber(rate) or 1)
end

-- What the player has: { level, xp, xpMax, rested, rate }, or nil when the
-- client will not say.
function Experience:Reading()
    local Client = ns.modules.Client
    local get = rawget
    local level = Client:Read(get(_G, "UnitLevel"), "player")
    local xp = Client:Read(get(_G, "UnitXP"), "player")
    if type(level) ~= "number" or level <= 0 or type(xp) ~= "number" then return nil end
    local xpMax = Client:Read(get(_G, "UnitXPMax"), "player")
    local rested = Client:Read(get(_G, "GetXPExhaustion"))
    local Config = ns.modules.Config
    local rate = Config and Config.Get and Config:Get("realm.xpRate")
    return { level = level, xp = xp, xpMax = type(xpMax) == "number" and xpMax > 0 and xpMax or nil,
        rested = type(rested) == "number" and rested or 0, rate = rate }
end

-- The experience still owed to reach `level` with `xp` into it: zero or
-- less once it is reached, nil when it cannot be worked out.
function Experience:Owed(level, xp, reading)
    level = tonumber(level)
    if not reading or not level then return nil end
    local have = reading.level
    if have > level then return 0 end
    if have == level then return (tonumber(xp) or 0) - reading.xp end
    local curve = self.toNext
    if not reading.xpMax and not curve[have] then return nil end
    local current = reading.xpMax or curve[have]
    local scale = (reading.xpMax and curve[have]) and reading.xpMax / curve[have] or 1
    local need = current - reading.xp
    for step = have + 1, level - 1 do
        if not curve[step] then return nil end
        need = need + math.floor(curve[step] * scale + 0.5)
    end
    return need + (tonumber(xp) or 0)
end

-- What reaching `level` (with `xp` into it) still takes, less `credit`, the
-- experience of turn-ins still ahead: { xp, kills }, or nil when it is
-- reached or cannot be worked out.
function Experience:Left(level, xp, reading, credit)
    reading = reading or self:Reading()
    local need = self:Owed(level, xp, reading)
    if not need then return nil end
    need = need - (credit or 0)
    if need <= 0 then return nil end
    -- Rested experience doubles a kill until the pool is spent; the bonus it
    -- still has to give is half the pool, and never more than half the need.
    local bonus = math.min((reading.rested or 0) / 2, need / 2)
    local perKill = self:PerKill(reading.level, reading.rate)
    return { xp = need, kills = math.max(1, math.ceil((need - bonus) / perKill)) }
end

-- Quest experience -----------------------------------------------------------
--
-- What a quest gives, for a level step that counts the turn-ins ahead of it
-- (`by`): the client's figure for a quest in the log, else what this account
-- saw it give before, at a turn-in or on the quest's offer. Nothing ships
-- with the addon; a quest never seen is unknown.

local function learned()
    return ns.db and ns.db.questXP
end

function Experience:LearnQuestXP(questID, xp)
    questID, xp = tonumber(questID), tonumber(xp)
    local store = learned()
    if not store or not questID or not xp or xp <= 0 then return false end
    store[questID] = xp
    return true
end

function Experience:QuestXP(questID)
    local Client = ns.modules.Client
    if Client and Client.GetQuestLogRewardXP and Client:IsQuestInLog(questID) then
        local xp = Client:GetQuestLogRewardXP(questID)
        if xp and xp > 0 then return xp end
    end
    local store = learned()
    return store and store[questID] or nil
end

local function addAll(into, value)
    if type(value) == "table" then for _, id in ipairs(value) do into[#into + 1] = id end
    elseif value ~= nil then into[#into + 1] = value end
end

-- The turn-ins in the steps after `from` and before `to` that still count:
-- a quest not handed in yet, which the player has or takes in that stretch,
-- on a step open to this character now. { xp, quests, unknown }.
function Experience:Pending(guide, from, to)
    local Client, Progress = ns.modules.Client, ns.modules.Progress
    local taken, handed = {}, {}
    for index = from + 1, to - 1 do
        local node = guide.nodes[index]
        local auto = node and node.auto
        if auto and (not Progress or Progress:IsAvailable(node)) then
            local accepts, turnins = {}, {}
            if auto.verb == "accept" then addAll(accepts, auto.quests)
            elseif auto.verb == "turnin" then addAll(turnins, auto.quests)
            elseif auto.verb == "talk" then addAll(accepts, auto.accept); addAll(turnins, auto.turnin) end
            for _, id in ipairs(accepts) do taken[id] = true end
            for _, id in ipairs(turnins) do handed[#handed + 1] = id end
        end
    end
    local pending, seen = { xp = 0, quests = 0, unknown = 0 }, {}
    for _, id in ipairs(handed) do
        if not seen[id] and not Client:IsQuestComplete(id) and (taken[id] or Client:IsQuestInLog(id)) then
            seen[id] = true
            local xp = self:QuestXP(id)
            pending.quests = pending.quests + 1
            if xp then pending.xp = pending.xp + xp else pending.unknown = pending.unknown + 1 end
        end
    end
    return pending
end

-- What a level step asks for now: { level, xp, credit, unknown }. A step with
-- `by` counts the turn-ins before that step as experience on the way. One
-- whose experience is not known yet is left out, so the player grinds a
-- little more rather than arriving short, and `unknown` says how many.
function Experience:Target(observed, stepIndex)
    local target = { level = observed.atLeast, xp = observed.xp, credit = 0, unknown = 0 }
    if not observed.by or not stepIndex then return target end
    local Progress = ns.modules.Progress
    local guide = Progress and Progress.GetActiveGuide and Progress:GetActiveGuide()
    if not guide or not guide.nodes[stepIndex] then return target end
    local pending = self:Pending(guide, stepIndex, observed.by)
    target.credit, target.unknown = pending.xp, pending.unknown
    return target
end

-- Whether a level observation holds, turn-ins ahead counted; nil when the
-- client will not say.
function Experience:Reached(observed, stepIndex)
    local target = self:Target(observed, stepIndex)
    local need = self:Owed(target.level, target.xp, self:Reading())
    if not need then return nil end
    return need - target.credit <= 0
end

-- The tracker's figure beside a level goal, or nil once it is reached.
function Experience:Progress(observed, stepIndex)
    local target = self:Target(observed, stepIndex)
    local text = self:Describe(self:Left(target.level, target.xp, nil, target.credit))
    if text and target.unknown > 0 then
        text = text .. string.format(", %d %s not counted", target.unknown, target.unknown == 1 and "turn-in" or "turn-ins")
    end
    return text
end

-- "4210 XP, ~23 kills": what the tracker prints beside a level goal.
function Experience:Describe(left)
    if not left then return nil end
    return string.format("%d XP, ~%d %s", left.xp, left.kills, left.kills == 1 and "kill" or "kills")
end

ns:RegisterModule("Experience", Experience)
