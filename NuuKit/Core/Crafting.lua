local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit

-- What a Make button asks the profession window for: how many crafts a step
-- still needs, and the words for why the button cannot make them now. Pure:
-- it takes recipe tables and owns none. The making itself is the addon's
-- Client:Craft; the buttons are on the planner's Plan tab (NuuProfessions)
-- and on the tracker's craft steps (NuuRoad).
local Crafting = {}

local function SkillUp() return Kit.SkillUp end

-- A profession's recipe by its spell, else the recipe making `item`: the
-- recipe and its spell, or nil.
function Crafting:Recipe(data, spell, item)
    local recipes = type(data) == "table" and data.recipes
    if type(recipes) ~= "table" then return nil end
    spell, item = tonumber(spell), tonumber(item)
    if spell and recipes[spell] then return recipes[spell], spell end
    if not item then return nil end
    local found, foundSpell
    for id, recipe in pairs(recipes) do
        -- The lowest spell, so the pick does not hang on the table's order.
        if recipe.makes == item and (not foundSpell or id < foundSpell) then found, foundSpell = recipe, id end
    end
    return found, foundSpell
end

-- Crafts to order to take the skill from `skill` to `toSkill` with the
-- recipe: the low end of the planner's range at its confidence ("safe"
-- unless given), never fewer than the points left. The client cannot stop
-- a batch once the skill is there (docs/api-compatibility.md), so a batch
-- is ordered short rather than long; the button offers the rest from the
-- skill it leaves. `skills`: the planner's for the recipe (Planner:Skill levels,
-- where a trainer showed a learn skill the data does not have), else the
-- data's. 0 once there, nil when the recipe stops giving skill on the way
-- (or is not known).
function Crafting:ToSkill(recipe, skill, toSkill, confidence, skills)
    skill, toSkill = tonumber(skill), tonumber(toSkill)
    if not skill or not toSkill then return nil end
    if skill >= toSkill then return 0 end
    if type(recipe) ~= "table" or type(recipe.skills) ~= "table" then return nil end
    local expected, variance = SkillUp():Span(type(skills) == "table" and skills or recipe.skills, skill, toSkill)
    if not expected then return nil end
    return (SkillUp():Range(expected, variance, SkillUp():Z(confidence), toSkill - skill))
end

-- Crafts to have `need` of an item with `have` already made, each craft
-- making `made` (the recipe's average); 0 once there are enough.
function Crafting:ForItems(need, have, made)
    local short = (tonumber(need) or 0) - (tonumber(have) or 0)
    if short <= 0 then return 0 end
    made = math.max(tonumber(made) or 1, 1)
    return math.ceil(short / made - 1e-9)
end

function Crafting:AverageMade(recipe)
    local made = type(recipe) == "table" and recipe.made
    if type(made) ~= "table" then return 1 end
    return ((made[1] or 1) + (made[2] or made[1] or 1)) / 2
end

-- How many crafts the reagents carried make (`countOf(itemID)` the bags):
-- nil when the recipe lists no reagents to count.
function Crafting:CanMake(recipe, countOf)
    local reagents = type(recipe) == "table" and recipe.reagents
    if type(reagents) ~= "table" or #reagents == 0 or type(countOf) ~= "function" then return nil end
    local most
    for _, reagent in ipairs(reagents) do
        local need = math.max(tonumber(reagent[2]) or 1, 1)
        local can = math.floor((tonumber(countOf(reagent[1])) or 0) / need)
        if not most or can < most then most = can end
    end
    return most
end

-- How many crafts can be made: the window's count or the bags' by the
-- recipe data, whichever is higher (Forever's window was seen to say none
-- while the materials were carried), nil when neither says.
function Crafting:Available(said, carried)
    said, carried = tonumber(said), tonumber(carried)
    if said and carried then return math.max(said, carried) end
    return said or carried
end

-- What a Make button does now, from its order (MakeOrder in the UI) and
-- the open window's answer (Client:FindCraft: `found`, else `why` and
-- `other`). `canOpen` is true where the addon can open the profession's
-- window itself; `carried` the crafts the bags make (CanMake). Returns
-- { mode, count, words }: mode "window" makes a batch through the open
-- window, "open" opens the window on the recipe, nil neither (`words` then
-- says why).
function Crafting:Button(order, name, found, why, other, canOpen, carried)
    local wanted = order.count ~= math.huge and order.count or nil
    local available = found and self:Available(found.available, carried)
    if found and available ~= 0 then
        local count = found.api == "craft" and 1 or math.min(order.count, available or order.count)
        local words = "Make " .. count .. " x " .. name
            .. (order.untilSkill and (", stopping at " .. order.profession .. " " .. order.untilSkill) or "") .. "."
        if found.api ~= "craft" and wanted and available and available < wanted then
            words = words .. " The step wants " .. wanted .. "; you carry the materials for " .. available .. "."
        end
        return { mode = "window", count = count, words = words }
    end
    if found then why = "materials" end
    if why == "closed" and canOpen then
        return { mode = "open", count = wanted, words = "Open " .. order.profession .. " on " .. name
            .. ". Then this button makes " .. (wanted and (wanted .. " ") or "the step ") .. "at once." }
    end
    return { count = wanted, words = self:Why(why, order.profession, other), why = why }
end

-- A Make button's words when it cannot make: Client:FindCraft's and
-- Client:Craft's reasons.
function Crafting:Why(reason, profession, other)
    profession = profession or "the profession"
    if reason == "closed" then
        if other then return "The " .. other .. " window is open. Open " .. profession .. " to make it from here." end
        return "Open your " .. profession .. " window to make it from here."
    elseif reason == "missing" then
        return "Not in your " .. profession .. " window: learn it first, or open its header and clear the window's filters."
    elseif reason == "materials" then
        return "You do not carry the materials for one."
    elseif reason == "failed" then
        return "The game did not take the order. Make it from the " .. profession .. " window."
    end
    return nil
end

Kit.Crafting = Crafting
