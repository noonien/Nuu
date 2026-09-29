local Kit = _G.LoadKit().Kit
local Crafting = Kit.Crafting
local data = { recipes = {
    [2660] = { makes = 2862, made = { 1, 1 }, skills = { 1, 15, 35, 55 } },
    [9000] = { makes = 2862, made = { 1, 1 }, skills = { 1, 15, 35, 55 } },
    [3100] = { makes = 4000, made = { 2, 4 }, skills = { 10, 20, 25, 30 } },
} }

-- Recipes by spell, else by what they make (the lowest spell of several).
assert(select(2, Crafting:Recipe(data, 3100)) == 3100)
assert(select(2, Crafting:Recipe(data, nil, 2862)) == 2660)
assert(Crafting:Recipe(data, nil, 1) == nil and Crafting:Recipe(nil, 2660) == nil)

-- To a skill: orange is a craft a point; nothing left once there.
local recipe = data.recipes[2660]
assert(Crafting:ToSkill(recipe, 5, 15) == 10)
assert(Crafting:ToSkill(recipe, 15, 15) == 0 and Crafting:ToSkill(recipe, 20, 15) == 0)
assert(Crafting:ToSkill(recipe, 40, 50, "sure") < Crafting:ToSkill(recipe, 40, 50, "typical"), "the range's low end: a wider range orders fewer")
assert(Crafting:ToSkill(recipe, 40, 50, "sure") >= 10, "never fewer than the points left")
assert(Crafting:ToSkill(recipe, 50, 60) == nil, "grey on the way: unknown")
assert(Crafting:ToSkill(nil, 1, 5) == nil)
-- The planner's skill levels win: a trainer taught it before the data's first skill.
assert(Crafting:ToSkill(recipe, 50, 60) == nil and Crafting:ToSkill(recipe, 50, 55, nil, { 40, 60, 70, 80 }) == 5)

-- Items: what is short, over what a craft makes.
assert(Crafting:ForItems(10, 4, 1) == 6)
assert(Crafting:ForItems(10, 4, 3) == 2)
assert(Crafting:ForItems(5, 9, 1) == 0)
assert(Crafting:AverageMade(data.recipes[3100]) == 3 and Crafting:AverageMade({}) == 1)

-- What the bags make: the scarcest reagent decides.
local bags = { [1] = 7, [2] = 3 }
local function countOf(id) return bags[id] or 0 end
assert(Crafting:CanMake({ reagents = { { 1, 2 }, { 2, 1 } } }, countOf) == 3)
assert(Crafting:CanMake({ reagents = { { 1, 2 }, { 9, 1 } } }, countOf) == 0)
assert(Crafting:CanMake({ reagents = {} }, countOf) == nil and Crafting:CanMake(nil, countOf) == nil)
assert(Crafting:Available(0, 5) == 5 and Crafting:Available(nil, 2) == 2 and Crafting:Available(4, nil) == 4)
assert(Crafting:Available(nil, nil) == nil)

-- The button: the open window first, else opening it, else why not.
local order = { profession = "Mining", count = 10, untilSkill = 50 }
local state = Crafting:Button(order, "Copper Bar", { api = "tradeskill", available = 4 })
assert(state.mode == "window" and state.count == 4 and state.words:find("wants 10"))
state = Crafting:Button(order, "Copper Bar", nil, "closed", nil, true)
assert(state.mode == "open" and state.count == 10)
state = Crafting:Button(order, "Copper Bar", nil, "closed", "Cooking", false)
assert(state.mode == nil and state.why == "closed" and state.words:find("Cooking"))
state = Crafting:Button(order, "Copper Bar", { api = "tradeskill", available = 0 }, nil, nil, true)
assert(state.mode == nil and state.why == "materials" and state.count == 10)
state = Crafting:Button(order, "Copper Bar", nil, "missing", nil, true)
assert(state.mode == nil and state.why == "missing", "a window that is open but lacks it is not opened again")
state = Crafting:Button(order, "Copper Bar", { api = "modern", available = 0 }, nil, nil, true, 6)
assert(state.mode == "window" and state.count == 6, "the bags outvote a window that says none")
state = Crafting:Button(order, "Copper Bar", { api = "modern" }, nil, nil, true, nil)
assert(state.mode == "window" and state.count == 10, "a window that does not say is not read as none")
assert(Crafting:Button({ profession = "Mining", count = math.huge }, "x", nil, "closed", nil, true).words:find("the step"))

assert(Crafting:Why("closed", "Mining"):find("Open your Mining window"))
assert(Crafting:Why("closed", "Mining", "Cooking"):find("Cooking window is open"))
assert(Crafting:Why("missing", "Mining") and Crafting:Why("materials") and Crafting:Why(nil) == nil)

print("NuuKit crafting tests passed")
