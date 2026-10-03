-- Keeping the route current (UI/Planner.lua, "Keeping the route current"):
-- the planner window on the kit's stand-in for the client, with a clock and
-- C_Timer of the test's own, taken through what one craft tells it (the
-- "You create" line, the bags, the skill line, the profession window). A
-- burst is one check and one plan, on the state the whole burst left; a plan
-- that changes nothing on screen draws nothing; and during the Make button's
-- batch the bags wait for the skill, which still plans at once.
--
-- It installs the stand-in in _G, as the window's smoke tests do.
_G = _G or _ENV

local frames = dofile("../NuuKit/Tests/Support/Frames.lua")
local Object = frames.Object
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 11, "" end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end
function Object:EnableMouse(on) self.mouse = on and true or false end
function Object:IsMouseEnabled() return self.mouse ~= false end

local errors = {}
_G.geterrorhandler = function() return function(err) table.insert(errors, tostring(err)) end end

-- The timers: After queues, and advance(seconds) runs what falls due.
local now, timers = 0, {}
_G.GetTime = function() return now end
_G.C_Timer = { After = function(seconds, callback) table.insert(timers, { at = now + seconds, fn = callback }) end }
local function advance(seconds)
    local stop = now + seconds
    while true do
        local soonest
        for index, timer in ipairs(timers) do
            if timer.at <= stop and (not soonest or timer.at < timers[soonest].at) then soonest = index end
        end
        if not soonest then break end
        local timer = table.remove(timers, soonest)
        now = math.max(now, timer.at)
        timer.fn()
    end
    now = stop
end

-- The kit as the client loads it in development, without the audit.
local kitNS = {}
for line in io.lines("../NuuKit/NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
        assert(loadfile("../NuuKit/" .. file))("NuuKit", kitNS)
    end
end
_G.NuuKit = kitNS.Kit

local ns = {}
for line in io.lines("NuuProfessions.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then assert(loadfile(file))("NuuProfessions", ns) end
end
ns:Initialize()
-- The prof channel's rows, as the session log keeps them.
local records, record = {}, ns.Record
ns.Record = function(self, channel, data)
    if channel == "prof" then table.insert(records, data) end
    return record(self, channel, data)
end

local function check(value, message)
    if not value then error(message, 2) end
end

local Panel = ns.modules.PlannerPanel
local Client = ns.modules.Client
local PROFESSION = "Leatherworking"

-- The character: Leatherworking at `skill`, and bags of the test's own.
local skill = 50
Client.GetSkillLevel = function(_, name)
    if type(name) == "string" and name:lower() == PROFESSION:lower() then return skill, 150 end
    return nil
end
local bags = {}
_G.GetItemCount = function(item) return bags[item] or 0 end

-- Every plan, every full draw and every Make button refresh, counted.
local plans, draws, makes = {}, 0, 0
local replan, render, refresh = Panel.Replan, Panel.Render, Panel.RefreshMake
Panel.Replan = function(self, reason, triggers)
    table.insert(plans, { reason = reason, triggers = triggers, skill = skill })
    return replan(self, reason, triggers)
end
Panel.Render = function(self, ...) draws = draws + 1; return render(self, ...) end
Panel.RefreshMake = function(self, ...) makes = makes + 1; return refresh(self, ...) end
local function reset() plans, draws, makes = {}, 0, 0 end

Panel:Open(PROFESSION)
advance(10)
check(Panel.win:IsShown() and Panel.route and #Panel.route.runs > 0, "a route for " .. PROFESSION)
check(Panel.route.skill == 50, "planned from the skill")

-- What the first step takes, for bags that move the plan.
local reagent
for _, entry in ipairs(Panel.route.shopping or {}) do
    if entry.itemID then reagent = entry.itemID; break end
end
check(reagent, "the route buys something")

-- One craft: the "You create" line first, then the bags, the skill line and
-- the profession window, a few tenths apart, the skill up between them.
local function craft(skillUp)
    Panel:ProfessionChanged("crafted", 999999, 1)
    advance(0.1)
    bags[reagent] = (bags[reagent] or 0) + 1
    Panel:OnEvent("BAG_UPDATE_DELAYED")
    advance(0.2)
    if skillUp then skill = skill + 1 end
    Panel:OnEvent("SKILL_LINES_CHANGED")
    advance(0.2)
    Panel:ProfessionChanged("tradeskill", PROFESSION)
end

-- A craft burst is one plan, at the new skill, after the last trigger.
reset()
craft(true)
advance(0.4)
check(#plans == 0, "nothing planned before the burst settles")
advance(0.2)
check(#plans == 1, "one plan for one craft (" .. #plans .. ")")
check(plans[1].skill == 51 and Panel.route.skill == 51, "planned on the skill the craft left")
check(plans[1].reason == "skill", "recorded under the skill: " .. tostring(plans[1].reason))
check(plans[1].triggers == "crafted,bags,skill,tradeskill", "the triggers gathered: " .. tostring(plans[1].triggers))
local row
for index = #records, 1, -1 do
    if records[index].event == "plan" then row = records[index]; break end
end
check(row and row.triggers == plans[1].triggers and row.first == Panel.route.runs[1].spell
    and row.firstCount == Panel.route.runs[1].count, "the plan record names its triggers and first step")
check(draws >= 1, "the new route is drawn")
advance(10)
check(#plans == 1, "and nothing after")

-- Nothing moved: a trigger checks, plans nothing, draws nothing.
reset()
Panel:ProfessionChanged("tradeskill", PROFESSION)
Panel:OnEvent("SKILL_LINES_CHANGED")
advance(1)
check(#plans == 0 and draws == 0 and makes == 1, "a check with nothing new neither plans nor draws")

-- The auction house closed: planned again (prices are not in the
-- signature), but the same route is not drawn again.
reset()
Panel:ProfessionChanged("auction")
advance(1)
check(#plans == 1 and plans[1].reason == "auction", "the auction house plans again")
check(draws == 0 and makes == 1, "an identical plan does not redraw (" .. draws .. ")")

-- Bags that move nothing a recipe uses plan nothing.
reset()
bags[1] = 5
Panel:OnEvent("BAG_UPDATE_DELAYED")
advance(1)
check(#plans == 0, "loot no recipe uses does not plan")

-- During a Make batch the bags wait.
reset()
Client.craftUntil = { profession = PROFESSION, skill = 60 }
craft(false)
advance(1)
check(#plans == 0, "the bags wait during a Make batch")
craft(false)
advance(1)
check(#plans == 0, "and keep waiting while it crafts")
-- The skill moving still plans, the bags with it.
craft(true)
advance(1)
check(#plans == 1 and plans[1].skill == skill, "a skill change during a Make batch plans")
check(Panel.route.skill == skill, "from the new skill")
-- A batch that goes quiet has stopped: the bags it left are planned.
reset()
bags[reagent] = bags[reagent] + 1
Panel:OnEvent("BAG_UPDATE_DELAYED")
advance(2)
check(#plans == 0, "held a while")
advance(6)
check(#plans == 1 and plans[1].triggers == "bags", "planned once the batch is quiet")
-- The batch stopped (the window shut): what waited is planned at once.
reset()
bags[reagent] = bags[reagent] + 1
Panel:OnEvent("BAG_UPDATE_DELAYED")
advance(1)
check(#plans == 0, "held again")
Client.craftUntil = nil
Panel:ProfessionChanged("window", "closed")
advance(1)
check(#plans == 1, "the window shut, the bags are planned")

-- The change history (Domain/PlanChanges.lua): the player's change is an
-- entry in the strip's words; a plan that changes nothing is none; the
-- panel lists them.
local Changes = ns.modules.PlanChanges
local View = ns.modules.PlanChangesView
local function entries() return Changes:Entries(Panel:Store(), PROFESSION) end
local before = entries()[1]
Panel:Change("target", function(changed) changed.target = skill + 20 end, "Target set to " .. (skill + 20) .. ".")
local entry = entries()[1]
check(entry ~= before and #entries() <= Changes.limit, "the player's change is an entry, the history kept to its limit")
check(entry.own == "target" and entry.text == "Target set to " .. (skill + 20) .. ".", "in the strip's words")
check(Panel.statusUndo ~= nil, "the strip keeps its Undo")
Panel:ProfessionChanged("auction")
advance(1)
check(entries()[1] == entry, "an auction house visit that changes nothing is no entry")
check(Panel.changesButton, "the Changes button")
View:SetShown(true)
check(View:IsShown(), "the panel is up")
View:Refresh()
View:SetShown(false)
check(not View:IsShown(), "and put away")

advance(10)
check(#errors == 0, "no errors: " .. table.concat(errors, "\n"))

-- The test's own clock and bags go, for whatever runs next.
Panel.win:Hide()
_G.C_Timer, _G.GetItemCount = nil, nil
_G.GetTime = function() return 0 end

print("NuuProfessions replan tests passed")
return true
