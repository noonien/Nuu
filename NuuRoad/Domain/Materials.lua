local _, ns = ...

-- The shopping list: what the steps still ahead ask the player to bring, and
-- how much of it is missing from their bags. A profession or crafting guide
-- names its materials per step (`needs`); this adds them up from the current
-- step to the end of the guide so the gathering, the vendor run, and the
-- auction house trip can all be done in one go instead of a step at a time.
--
-- Where each material comes from is whatever the step says. A written guide
-- authors it; a guide the profession planner (NuuProfessions, another addon)
-- saves fills it from its recipe data and the player's price book, and sizes
-- the counts at the chosen confidence. This module reads neither: it only
-- adds up the steps' `needs` against the bags. Nothing here buys, posts, or
-- searches the auction house.
local Materials = {}

local sourceWords = {
    gather = "gather", vendor = "vendor", ah = "auction house", drop = "drops", craft = "craft",
}
local sourceOrder = { gather = 1, drop = 2, craft = 3, vendor = 4, ah = 5 }

function Materials:SourceWord(source)
    return sourceWords[source] or "gather"
end

local function itemCount(itemID)
    local Client = ns.modules.Client
    if not Client or not Client.GetItemCount then return 0 end
    return Client:GetItemCount(itemID, true) or 0
end

-- One step's materials with what the player carries: `have`, and `short`, the
-- number still missing. Bags are the only stock counted; nothing assumes what
-- an earlier step produced.
function Materials:StepNeeds(node)
    local list = {}
    for _, material in ipairs(node and node.needs or {}) do
        local have = itemCount(material.itemID)
        table.insert(list, {
            itemID = material.itemID, count = material.count, source = material.source,
            have = have, short = math.max(material.count - have, 0),
        })
    end
    return list
end

-- True when the guide keeps its materials list to one section at a time
-- (`meta.materials = "section"`): a guide whose every section begins with its
-- own shopping, such as a profession route split by recipe.
function Materials:BySection(guide)
    return type(guide) == "table" and type(guide.meta) == "table" and guide.meta.materials == "section"
end

-- The last step the list reaches from `fromIndex`: the end of the guide, or,
-- for a guide listed by section, the end of the section holding that step.
-- Also returns that section.
function Materials:ListEnd(guide, fromIndex)
    local last = #(guide and guide.nodes or {})
    if not self:BySection(guide) or not fromIndex then return last, nil end
    for _, section in ipairs(guide.sections or {}) do
        local indexes = section.nodeIndexes or {}
        local first, final = indexes[1], indexes[#indexes]
        if first and fromIndex >= first and fromIndex <= final then return final, section end
    end
    return last, nil
end

-- Everything the guide still asks for, from `fromIndex` to the end (or to
-- the end of the section, see ListEnd): one entry per item, its counts added
-- up, the step that needs it first, and the shortfall against the bags. Steps
-- the player has already finished, and those their character is not eligible
-- for, ask for nothing.
--
-- A step that is only partly done still counts in full: the guide cannot know
-- how much of its work is left, and asking for too much is recoverable while
-- arriving short is not.
function Materials:Outstanding(guide, fromIndex, state)
    local Progress = ns.modules.Progress
    state = state or (Progress and Progress.PeekState and Progress:PeekState(guide))
    local byItem, order = {}, {}
    for index = fromIndex or 1, (self:ListEnd(guide, fromIndex)) do
        local node = guide.nodes[index]
        local done = state and state.statuses and Progress and Progress:IsDone(state.statuses[index])
        local available = not Progress or Progress:IsAvailable(node)
        if node and node.needs and not done and available then
            for _, material in ipairs(node.needs) do
                local entry = byItem[material.itemID]
                if not entry then
                    entry = { itemID = material.itemID, count = 0, source = material.source, firstStep = index }
                    byItem[material.itemID] = entry
                    table.insert(order, entry)
                end
                entry.count = entry.count + material.count
            end
        end
    end
    for _, entry in ipairs(order) do
        entry.have = itemCount(entry.itemID)
        entry.short = math.max(entry.count - entry.have, 0)
    end
    -- Grouped by where it comes from, so one trip covers one group, and in
    -- guide order inside a group so the first thing needed is at the top.
    table.sort(order, function(a, b)
        local left, right = sourceOrder[a.source] or 9, sourceOrder[b.source] or 9
        if left ~= right then return left < right end
        if a.firstStep ~= b.firstStep then return a.firstStep < b.firstStep end
        return a.itemID < b.itemID
    end)
    return order
end

-- What the tracker's button says: how many distinct materials are still
-- missing, and whether anything is needed at all.
function Materials:Summary(guide, fromIndex, state)
    local outstanding = self:Outstanding(guide, fromIndex, state)
    local missing = 0
    for _, entry in ipairs(outstanding) do
        if entry.short > 0 then missing = missing + 1 end
    end
    return missing, #outstanding, outstanding
end

-- True when the guide asks for materials anywhere, so the button and the
-- panel stay out of the way of guides that do not.
function Materials:GuideHasMaterials(guide)
    for _, node in ipairs(guide and guide.nodes or {}) do
        if node.needs then return true end
    end
    return false
end

ns:RegisterModule("Materials", Materials)
