local _, ns = ...

-- Which spec's weights score items for this character. The player picks one
-- (`/nuugear spec`), kept in the character's record; until they do, it is
-- the talent tree with the most points, and with no points spent the class's
-- first spec. A pick is never changed for the player.
local Specs = {}

local function Config() return ns.modules.Config end
local function Client() return ns.modules.Client end

-- The class's specs from Data/Weights.lua, in order.
function Specs:ForClass(class)
    return class and ns.weights[class] or nil
end

function Specs:Find(class, key)
    for _, spec in ipairs(self:ForClass(class) or {}) do
        if spec.key == key then return spec end
    end
    return nil
end

-- The spec the talents point at: the first spec of the tree with the most
-- points. nil with no points spent or no talents to read.
function Specs:Guess(class, points)
    local best, most = nil, 0
    for tab, spent in ipairs(points or {}) do
        if spent > most then best, most = tab, spent end
    end
    if not best then return nil end
    for _, spec in ipairs(self:ForClass(class) or {}) do
        if spec.tab == best then return spec end
    end
    return nil
end

-- The spec in use, and how it was chosen: "picked", "talents" or "default".
function Specs:Active()
    local class = Client():GetPlayerClass()
    local specs = self:ForClass(class)
    if not specs then return nil end
    local store = Config():CharacterStore()
    local picked = store and store.spec and self:Find(class, store.spec)
    if picked then return picked, "picked" end
    local guessed = self:Guess(class, Client():GetTalentPoints())
    if guessed then return guessed, "talents" end
    return specs[1], "default"
end

-- Picks a spec by its key or name (any case); nil `key` goes back to the
-- talents' guess. Returns the spec, or nil when the class has none by that
-- name.
function Specs:Pick(key)
    local store = Config():CharacterStore()
    if not store then return nil end
    if not key then
        store.spec = nil
        return self:Active()
    end
    key = key:lower()
    for _, spec in ipairs(self:ForClass(Client():GetPlayerClass()) or {}) do
        if spec.key == key or spec.name:lower() == key then
            store.spec = spec.key
            return spec
        end
    end
    return nil
end

ns:RegisterModule("Specs", Specs)
