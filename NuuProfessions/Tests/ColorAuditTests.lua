-- The colour audit (Dev/ColorAudit.lua): every recipe the window lists
-- against the data's colour at the window's skill, one `coloraudit` row a run.
-- The profession client suite leaves its Classic windows' calls in _G: put
-- aside for this suite, so only the modern window below is open.
local classic = {}
for name, value in pairs(_G) do
    if type(name) == "string" and (name:find("TradeSkill") or name:find("Craft")) and name ~= "C_TradeSkillUI" then
        classic[name] = value
    end
end
for name in pairs(classic) do _G[name] = nil end

local ns = NewNamespace()
Load(ns, "Config.lua")
Load(ns, "API/Client.lua")
Load(ns, "Data/ProfessionTiers.lua")
Load(ns, "Domain/Prices.lua")
Load(ns, "Domain/ProfessionPlanner.lua")
Load(ns, "Dev/ColorAudit.lua")
local Client, Audit = ns.modules.Client, ns.modules.ColorAudit
ns.modules.Config.characterStore = {}
ns.db = {}

local function audits()
    local rows = {}
    for _, record in ipairs(ns.records) do
        if record.channel == "prof" and record.data.event == "coloraudit" then table.insert(rows, record.data) end
    end
    return rows
end
local function printed(text)
    for _, line in ipairs(ns.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-- Toy Tailoring: Linen Belt and Reinforced Linen Cape as the data has them,
-- and a few made to sit on the band edges at 67.
ns.professionData = { Tailoring = { recipes = {
    [8776] = { makes = 7026, skills = { 50, 50, 68, 85 }, forever = "unchanged" },
    [2397] = { makes = 2580, skills = { 60, 60, 78, 95 }, forever = "changed" },
    [100] = { makes = 1000, skills = { 40, 50, 68, 90 }, forever = "changed" },
    [101] = { makes = 1001, skills = { 30, 40, 50, 67 }, forever = "unchanged" },
    [102] = { makes = 1002, skills = { 30, 40, 50, 68 }, forever = "unchanged" },
    [103] = { makes = 1003, skills = { 60, 67, 80, 90 }, forever = "new" },
    [104] = { makes = 1004, skills = { 70, 75, 80, 85 }, forever = "changed" },
} } }

local skill = 67
local window = {
    [8776] = { name = "Linen Belt", difficulty = "easy" },
    [2397] = { name = "Reinforced Linen Cape", difficulty = "medium" },
    [100] = { name = "Early Green", difficulty = "easy" },
    [101] = { name = "Grey On Time", difficulty = "trivial" },
    [102] = { name = "Early Grey", difficulty = "trivial" },
    [103] = { name = "Late Yellow", difficulty = "optimal" },
    [104] = { name = "Below Learn", difficulty = "optimal" },
    [999] = { name = "Not In Data", difficulty = "easy" },
}
local ids = { 8776, 2397, 100, 101, 102, 103, 104, 999 }
C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    GetBaseProfessionInfo = function() return { professionName = "Tailoring", skillLevel = skill, maxSkillLevel = 75 } end,
    GetAllRecipeIDs = function() return ids end,
    GetRecipeInfo = function(id)
        local row = window[id]
        return row and { name = row.name, difficulty = row.difficulty, learned = true } or nil
    end,
}

-- The pattern names and edges, alone.
assert(Audit.PatternName("green", -1) == "green -1" and Audit.PatternName("yellow", 1) == "yellow +1")
assert(Audit.PatternName("grey", nil) == "grey ?")
local band, offset, side, jump = Audit:Edge({ 50, 50, 68, 85 }, 67, "yellow", "green")
assert(band == "green" and offset == -1 and side == "early" and jump == 1, "Linen Belt green at 67 is green -1")
band, offset, side = Audit:Edge({ 50, 50, 68, 85 }, 68, "green", "yellow")
assert(band == "green" and offset == 1 and side == "late", "still yellow at G is green +1")
band, offset, side, jump = Audit:Edge({ 50, 50, 68, 85 }, 66, "yellow", "grey")
assert(band == "grey" and offset == -19 and jump == 2)
assert(Audit:Edge({ 1, 2, 3, 4 }, 2, "yellow", "yellow") == nil)

-- A run on the open window.
SlashCmdList = {}
local planner = {}
SlashCmdList.NUUPROFESSIONS = function(text) table.insert(planner, text) end
Audit:Initialize()
SlashCmdList.NUUPROFESSIONS("coloraudit")
local runs = audits()
assert(#runs == 1, "one run is one record")
local r = runs[1]
assert(r.profession == "Tailoring" and r.skill == 67 and r.api == "modern" and r.dataSet == "beta")
assert(r.recipes == 8 and r.compared == 7 and r.agree == 2 and r.disagree == 5 and r.unmatched == 1 and r.noColor == 0)
assert(r.missing[1].spell == 999 and r.missing[1].name == "Not In Data" and r.missing[1].live == "green")
assert(r.byForever.unchanged.agree == 1 and r.byForever.unchanged.disagree == 2)
assert(r.byForever.changed.agree == 1 and r.byForever.changed.disagree == 2)
assert(r.byForever.new.agree == 0 and r.byForever.new.disagree == 1)

local green = r.patterns["green -1"]
assert(green and green.total == 2 and green.changed == 1 and green.unchanged == 1, "both early greens at G-1")
assert(r.patterns["grey -1"].total == 1 and r.patterns["grey -1"].unchanged == 1)
assert(r.patterns["yellow +1"].total == 1 and r.patterns["yellow +1"].new == 1, "still orange at Y")
assert(r.patterns["orange -3"].total == 1 and r.patterns["orange -3"].changed == 1, "shown below the data's learn skill")

-- Every recipe that sits at G-1 is green already; the edges say so.
assert(r.edges.green.before == 2 and r.edges.green.beforeEarly == 2 and r.edges.green.at == 0)
assert(r.edges.green.byForever.changed.beforeEarly == 1 and r.edges.green.byForever.unchanged.beforeEarly == 1)
assert(r.edges.grey.before == 1 and r.edges.grey.beforeEarly == 1 and r.edges.grey.at == 1 and r.edges.grey.atLate == 0)
assert(r.edges.yellow.at == 1 and r.edges.yellow.atLate == 1 and r.edges.yellow.before == 0)
assert(r.edges.orange == nil, "no band edge for orange")

local belt
for _, m in ipairs(r.mismatches) do
    if m.spell == 8776 then belt = m end
end
assert(belt and belt.name == "Linen Belt" and belt.skill == 67 and belt.expected == "yellow" and belt.live == "green")
assert(belt.forever == "unchanged" and belt.skills[3] == 68 and belt.item == 7026 and belt.kind == "early")
assert(#r.mismatches == 5)

assert(printed("Colour audit: Tailoring 67, 2 agree, 5 disagree, 1 not in the data."))
assert(printed("green -1: 2 (changed 1, unchanged 1)"))
assert(printed("green: at G-1 2 of 2 already green; at G 0 of 0 not yet"))

-- Anything else goes on to the planner's own command.
SlashCmdList.NUUPROFESSIONS("shop")
assert(#planner == 1 and planner[1] == "shop" and #audits() == 1)

-- Another skill, another record: at 68 Linen Belt is green in the data too.
skill = 68
window[2397].difficulty = "medium"
Audit:Run("")
runs = audits()
assert(#runs == 2 and runs[2].skill == 68 and runs[2].edges.green.at == 2 and runs[2].edges.green.atLate == 0)

-- A Classic window links only the product: the recipe is found by it.
local byItem = Audit:Compare({ profession = "Tailoring", skill = 67, order = {
    { name = "Linen Belt", itemID = 7026, color = "green" },
    { name = "Red", spellID = 2397, color = "red" },
} }, ns.professionData.Tailoring, "beta")
assert(byItem.compared == 1 and byItem.disagree == 1 and byItem.mismatches[1].spell == 8776 and byItem.mismatches[1].byItem)
assert(byItem.noColor == 1, "a trainer's red is not a window colour")

-- No window: nothing recorded, unless one read this session is named.
Client:ScanTradeSkill("tradeskill")
C_TradeSkillUI = nil
local none, why = Audit:Run("")
assert(none == nil and why == "Open a profession window first." and #audits() == 2)
local named = Audit:Run("tailoring")
assert(named and named.skill == 68 and #audits() == 3, "the window last read this session")

-- Data the addon lacks, and another player's window.
ns.professionData = {}
assert(select(2, Audit:Run("Tailoring")) == "No recipe data for Tailoring.")
Client:GetTradeSkillSnapshot("Tailoring").linked = true
assert(select(2, Audit:Run("Tailoring")) == "That is another player's window.")
assert(#audits() == 3)

SlashCmdList, SLASH_NUUPROFESSIONS1, SLASH_NUUPROFESSIONS2 = nil, nil, nil
for name, value in pairs(classic) do _G[name] = value end
return true
