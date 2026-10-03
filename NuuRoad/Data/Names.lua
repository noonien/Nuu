local _, ns = ...

-- Display names for the IDs that compact guide steps reference. Steps carry
-- only IDs; each guide carries the names of its own IDs in its `names` table
-- (npcs, quests, items, factions, spells), and Steps:Expand adds them here
-- before it writes the guide's titles. The client lookup fills in anything
-- missing and corrects the locale once it knows the thing.
local Names = { npcs = {}, quests = {}, items = {}, factions = {}, spells = {} }

-- The authored names, kept apart from the live corrections below so GuideAudit
-- can still say what the guide expected once the client has overwritten an entry.
Names.authored = { npcs = {}, quests = {}, items = {}, factions = {}, spells = {} }

-- Standing 1 to 8, as the reputation pane names them. Fixed by the client,
-- not authored, so guides say "Honored" and store the number.
Names.standings = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- A guide's `names` table. A name the client has already corrected stays
-- corrected; the authored one is still recorded for the audit.
function Names:Add(names)
    if type(names) ~= "table" then return end
    for kind, entries in pairs(names) do
        local live, authored = self[kind], self.authored[kind]
        if authored and type(entries) == "table" then
            for id, name in pairs(entries) do
                -- An NPC the guide visits is { "Name", at = ..., note = ... }.
                if type(name) == "table" then name = name[1] end
                if type(id) == "number" and type(name) == "string" then
                    authored[id] = name
                    if live[id] == nil then live[id] = name end
                end
            end
        end
    end
end

local function client()
    return ns.modules and ns.modules.Client
end

local function audit(kind, id, live)
    local GuideAudit = ns.modules and ns.modules.GuideAudit
    if GuideAudit then GuideAudit:Compare(kind, id, live) end
end

-- Live client names win so the text matches the player's locale; the table is
-- the fallback so titles never depend on the client cache being warm.
function Names:NPC(id)
    if type(id) ~= "number" then return nil end
    local live = client() and client().GetNPCName and client():GetNPCName(id)
    if live then
        audit("npcs", id, live)
        self.npcs[id] = live
        return live
    end
    return self.npcs[id]
end

function Names:Quest(id)
    if type(id) ~= "number" then return nil end
    local live = client() and client().GetQuestTitle and client():GetQuestTitle(id)
    if live then
        audit("quests", id, live)
        self.quests[id] = live
        return live
    end
    return self.quests[id]
end

function Names:Item(id)
    if type(id) ~= "number" then return nil end
    local live = client() and client().GetItemName and client():GetItemName(id)
    if live then
        audit("items", id, live)
        self.items[id] = live
        return live
    end
    return self.items[id]
end

function Names:Faction(id)
    if type(id) ~= "number" then return nil end
    local live = client() and client().GetFactionName and client():GetFactionName(id)
    if live then
        audit("factions", id, live)
        self.factions[id] = live
        return live
    end
    return self.factions[id]
end

function Names:Spell(id)
    if type(id) ~= "number" then return nil end
    local live = client() and client().GetSpellName and client():GetSpellName(id)
    if live then
        audit("spells", id, live)
        self.spells[id] = live
        return live
    end
    return self.spells[id]
end

function Names:DescribeSpell(id)
    return self:Spell(id) or ("spell " .. tostring(id))
end

function Names:DescribeFaction(id)
    return self:Faction(id) or ("faction " .. tostring(id))
end

-- 1 to 8; anything else is shown as the raw number rather than guessed at.
function Names:DescribeStanding(standing)
    return self.standings[standing or 0] or ("standing " .. tostring(standing))
end

-- "Honored" -> 6. Case-insensitive; nil for anything the pane does not name.
function Names:StandingValue(name)
    if type(name) == "number" then return name end
    if type(name) ~= "string" then return nil end
    for value, label in ipairs(self.standings) do
        if label:lower() == name:lower() then return value end
    end
    return nil
end

function Names:DescribeItem(id)
    return self:Item(id) or ("item " .. tostring(id))
end

function Names:DescribeNPC(id)
    return self:NPC(id) or ("NPC " .. tostring(id))
end

function Names:DescribeQuest(id)
    return self:Quest(id) or ("quest " .. tostring(id))
end

ns:RegisterModule("Names", Names)
