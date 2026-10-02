local _, ns = ...

-- Training what the plan needs at a profession trainer, when the player
-- presses Train or Train all on the strip under the trainer's window
-- (UI/TrainerStrip.lua).
--
-- Every plan keeps what it learns at a trainer (Keep, per character in
-- `training[profession]`): the trainer recipes its steps use and the tiers
-- it passes. Kept, the strip can say what to train with the planner shut,
-- as the shopping list does. At a trainer, Match reads that against the
-- trainer's own list: what can be trained now, and what the plan needs here
-- later (the skill or the level the trainer asks for is not there yet).
--
-- Training, like the vendor strip's buying (Domain/MerchantBuying.lua), is
-- one call at a time, with a pause between, so the trainer's list has
-- settled before the next: each service is found again by its key (a
-- trained one leaves the list, which moves the others up), and the call is
-- made only while that row is still the service and still available. It
-- stops when the trainer closes or the money runs out, and says in chat
-- what it trained. It trains only on the player's press, only at a trainer
-- the player opened, and only what the plan needs.
local Training = {}

local TRAIN_INTERVAL = 0.5 -- seconds between two training calls

local function Client() return ns.modules.Client end
local function Tiers() return ns.modules.ProfessionTiers end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, callback) else callback() end
end

-- This character's record: { [profession] = { recipes, tiers } }.
function Training:Record(create)
    local Config = ns.modules.Config
    local store = Config and Config:CharacterStore()
    if not store then return nil end
    if create and type(store.training) ~= "table" then store.training = {} end
    return store.training
end

-- Keeping the plan's training ------------------------------------------------------------

-- The tier's training spell for a profession, from the authored tiers.
local function tierSpell(profession, name)
    local tiers = Tiers()
    for _, tier in ipairs(tiers and tiers.fullTiers or {}) do
        if tier.name == name then return tier.spells and tier.spells[profession] end
    end
end

-- What a plan just made learns at a trainer: `recipes` { spell, makes,
-- skill (where the route first makes it), untilSkill (where its last run
-- ends; nil for an intermediate) } and `tiers` { tier, cap, skill, level,
-- spell }. Called by the planner after every plan, with its recipe data.
function Training:Keep(profession, route, data)
    if not profession or not route then return end
    local record = self:Record(true)
    if not record then return end
    local untilSkill = {}
    for _, run in ipairs(route.runs or {}) do
        if run.spell and run.toSkill then untilSkill[run.spell] = math.max(untilSkill[run.spell] or 0, run.toSkill) end
    end
    local recipes, tiers = {}, {}
    for _, event in ipairs(route.events or {}) do
        if event.kind == "learn" and event.source == "trainer" then
            local recipe = data and data.recipes and data.recipes[event.spell]
            table.insert(recipes, { spell = event.spell, makes = recipe and recipe.makes or nil, skill = event.skill,
                untilSkill = untilSkill[event.spell] })
        elseif event.kind == "train" then
            table.insert(tiers, { tier = event.tier, cap = event.cap, skill = event.skill, level = event.level,
                spell = tierSpell(profession, event.tier) })
        end
    end
    record[profession] = (#recipes > 0 or #tiers > 0) and { recipes = recipes, tiers = tiers } or nil
    if self.onKeep then pcall(self.onKeep) end
end

-- Reading it against the open trainer ----------------------------------------------------

local function lower(value) return type(value) == "string" and value:lower() or nil end

local function isRecipe(service, recipe)
    if service.spellID then return service.spellID == recipe.spell end
    return recipe.makes ~= nil and service.itemID == recipe.makes
end

-- A tier's service: its spell where the client gave one, else the
-- profession's name with the tier as its subtext (as Prices:TierCost finds
-- a recorded fee).
local function isTier(service, tier, profession)
    if service.spellID and tier.spell and service.spellID == tier.spell then return true end
    local name = lower(service.name)
    return service.tier == tier.tier and name ~= nil and name:find(profession:lower(), 1, true) ~= nil
end

-- Why a service the plan needs cannot be trained yet: "at skill 125",
-- "at level 20", or "not yet".
local function whyNot(service, skill, level)
    if service.skill and (skill or 0) < service.skill then return "at skill " .. service.skill end
    if service.level and level and level < service.level then return "at level " .. service.level end
    return "not yet"
end

-- What the open trainer teaches of one profession's kept training:
-- { kind = "recipe"|"tier", key, index (the service's row in the trainer's
-- list), name, cost, available, why (when not),
-- skill (where the plan needs it), tier, cap }, tiers first, then by the
-- skill the plan needs each at. What is known, trained, or behind the skill
-- (its last run done) is left out.
function Training:Match(profession, kept, services)
    local api = Client()
    local live = api and api:GetProfessionSkills() or {}
    local entry = live[profession] or {}
    local skill = entry.skill or (api and api:GetSkillLevel(profession)) or 0
    local level = api and api:GetPlayerLevel()
    local lines = {}
    for _, service in ipairs(services or {}) do
        if service.state ~= "used" then
            local line
            for _, tier in ipairs(kept.tiers or {}) do
                if not line and isTier(service, tier, profession) and not (entry.maxSkill and entry.maxSkill >= tier.cap) then
                    line = { kind = "tier", name = tier.tier .. " " .. profession, skill = tier.skill, tier = tier.tier,
                        cap = tier.cap }
                end
            end
            for _, recipe in ipairs(kept.recipes or {}) do
                if not line and isRecipe(service, recipe) and not (recipe.untilSkill and skill >= recipe.untilSkill)
                    and not (api and (api:IsRecipeKnown(profession, recipe.spell)
                        or (recipe.makes and api:IsRecipeKnown(profession, "item:" .. recipe.makes)))) then
                    line = { kind = "recipe", name = service.name, skill = recipe.skill, spell = recipe.spell }
                end
            end
            if line then
                line.key, line.index, line.cost = service.key, service.index, service.cost or 0
                line.available = service.state == "available"
                if not line.available then line.why = whyNot(service, skill, level) end
                table.insert(lines, line)
            end
        end
    end
    table.sort(lines, function(a, b)
        if a.kind ~= b.kind then return a.kind == "tier" end
        if (a.skill or 0) ~= (b.skill or 0) then return (a.skill or 0) < (b.skill or 0) end
        return a.name < b.name
    end)
    return lines
end

-- The open trainer against every profession's kept training: the
-- profession it teaches (the one its services name, else the one with the
-- most to train here) and its lines. nil with no trainer open or nothing
-- the plans need here.
function Training:AtTrainer()
    local api = Client()
    local record = self:Record(false)
    if not (api and record) then return nil, {} end
    local services = api:TrainerOffers()
    if #services == 0 then return nil, {} end
    local named
    for _, service in ipairs(services) do named = named or service.profession end
    local best, bestLines
    for profession, kept in pairs(record) do
        if type(kept) == "table" then
            local lines = self:Match(profession, kept, services)
            if #lines > 0 then
                if lower(named) == profession:lower() then return profession, lines end
                if not best or #lines > #bestLines or (#lines == #bestLines and profession < best) then
                    best, bestLines = profession, lines
                end
            end
        end
    end
    if not best then return nil, {} end
    return best, bestLines
end

-- Training -------------------------------------------------------------------------------

function Training:Busy() return self.run ~= nil end

-- Starts training `lines` (Match's) that are available, one after the
-- other. `done()` is called once it ends. Answers true, or false and why not.
function Training:StartAll(lines, done)
    if self.run then return false, "Still training." end
    local steps, cost = {}, 0
    for _, line in ipairs(lines or {}) do
        if line.available then
            table.insert(steps, { key = line.key, name = line.name, cost = line.cost or 0 })
            cost = cost + (line.cost or 0)
        end
    end
    if #steps == 0 then return false, "Nothing to train." end
    if Client():GetMoney() < cost then return false, "Not enough money." end
    self.run = { steps = steps, trained = {}, copper = 0, done = done }
    local names = {}
    for _, step in ipairs(steps) do table.insert(names, step.name) end
    ns:Record("prof", { event = "train", services = names, cost = cost })
    self:Next()
    return true
end

-- One call, then the next after the interval, until none is left, a call
-- fails (the trainer closed, the service left the list or is no longer
-- available) or the money runs out.
function Training:Next()
    local run = self.run
    if not run then return end
    local step = table.remove(run.steps, 1)
    if not step then return self:Finish() end
    if Client():GetMoney() < step.cost then return self:Finish("ran out of money") end
    local found
    for _, service in ipairs(Client():TrainerOffers()) do
        if service.key == step.key then found = service end
    end
    if not (found and found.state == "available" and Client():BuyTrainerService(found.index, found.name)) then
        return self:Finish("the trainer closed or its list changed")
    end
    table.insert(run.trained, step.name)
    run.copper = run.copper + (found.cost or step.cost)
    if #run.steps == 0 then return self:Finish() end
    after(TRAIN_INTERVAL, function() if self.run == run then self:Next() end end)
end

-- "Trained Linen Bag and Journeyman Tailoring for 5s 50c."
function Training:Finish(stopped)
    local run = self.run
    if not run then return end
    self.run = nil
    local parts = run.trained
    if #parts > 0 then
        local words = #parts == 1 and parts[1]
            or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
        ns:Print(("Trained %s for %s%s."):format(words, ns.Kit.FormatMoney(run.copper),
            stopped and (" (stopped: " .. stopped .. ")") or ""))
    elseif stopped then
        ns:Print("Trained nothing: " .. stopped .. ".")
    end
    if run.done then pcall(run.done) end
end

function Training:Initialize()
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    pcall(frame.RegisterEvent, frame, "TRAINER_CLOSED")
    frame:SetScript("OnEvent", function() if self.run then self:Finish("the trainer closed") end end)
    self.frame = frame
end

ns:RegisterModule("TrainerTraining", Training)
