local _, ns = ...

-- The plan's change history: what changed in a profession's plan, and why,
-- one entry each time a new plan differs from the last in a way the player
-- would see. The planner window (UI/Planner.lua) hands every plan here; the
-- Plan changes panel (UI/PlanChanges.lua) lists the entries, newest first.
--
-- A plan is kept as a small snapshot (Snapshot) beside the entries, so the
-- next plan, in this session or after a /reload, is compared with it:
--
--   snapshot = { skill, target, net,
--                runs = { { spell, from, to, count } },
--                section = { title, spell, items = { [itemID] = count } } (the first that buys),
--                prices = { [itemID] = { each, source, count } },
--                have = { [itemID] = n }, known = { spell, ... } }
--
-- An entry says why (`causes`) and what (`effects`), as data; the words are
-- made when shown (Words), so item and recipe names the client did not know
-- yet still come out:
--
--   entry = { at, reason, own = reason|nil, text = what the strip said|nil,
--             causes = { { kind = "own"|"price"|"skill"|"learned"|"bags", ... } },
--             effects = { { kind = "run"|"added"|"dropped"|"more"|"buy"|"moreItems"|"target"|"net", ... } } }
--
-- Progress is not a change: a craft that gives its point, with materials
-- leaving the bags, leaves the same steps ahead. A plan the player asked for
-- always has an entry. Any other has one when the steps ahead, the target or
-- what the current section buys changed, or when prices alone moved the
-- route's cost by at least PRICE_SHARE.
local Changes = {}

-- Entries kept per profession; the oldest go first.
Changes.limit = 20
-- The share of the route's net cost prices alone must move it by.
local PRICE_SHARE = 0.01
-- Effects and causes named one by one; the rest are counted.
local SHOWN_RUNS, SHOWN_PRICES, SHOWN_ITEMS = 3, 2, 3

local function sortedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do table.insert(keys, key) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

local function round(value) return value and math.floor(value + 0.5) or nil end

-- Snapshots --------------------------------------------------------------------

-- A plan as the history keeps it. `sections` is Planner:Sections' answer;
-- `known` the recipes the plan knew ({ [spell] = true }).
function Changes:Snapshot(route, sections, known)
    local snap = { skill = route.startSkill or route.skill, target = route.target,
        net = route.summary and round(route.summary.net) or nil,
        runs = {}, prices = {}, have = {}, known = {} }
    for _, run in ipairs(route.runs or {}) do
        table.insert(snap.runs, { spell = run.spell, from = run.fromSkill, to = run.toSkill, count = run.count })
    end
    for _, item in ipairs(route.shopping or {}) do
        if item.itemID then
            if item.each then
                snap.prices[item.itemID] = { each = round(item.each), source = item.source, count = item.count }
            end
            if (item.have or 0) > 0 then snap.have[item.itemID] = item.have end
        end
    end
    for _, section in ipairs(sections or {}) do
        if section.shopping and #section.shopping > 0 then
            local items = {}
            for _, item in ipairs(section.shopping) do
                if item.source ~= "craft" and not item.made then items[item.itemID] = item.count end
            end
            snap.section = { title = section.title, spell = section.spell, kind = section.kind, items = items }
            break
        end
    end
    -- Spells only: a recipe item not yet resolved to its spell has no name
    -- to say.
    for spell in pairs(known or {}) do
        if type(spell) == "number" then table.insert(snap.known, spell) end
    end
    table.sort(snap.known)
    return snap
end

-- Comparing --------------------------------------------------------------------

-- The steps still ahead of `skill` in a snapshot: a step the skill has
-- reached the end of is done.
local function ahead(snap, skill)
    local out = {}
    for _, run in ipairs(snap.runs or {}) do
        if (run.to or 0) > skill then table.insert(out, run) end
    end
    return out
end

local function stepKey(run) return tostring(run.spell) .. "@" .. tostring(run.to) end

-- The steps that differ, as effects: each new step matched to the first
-- old one with its recipe; a new one with no match is added, an old one
-- left over is dropped. A step whose end moved shows its crafts too; its
-- old start is clipped to the skill, which progress moved.
local function compareRuns(oldRuns, newRuns, skill)
    local same = #oldRuns == #newRuns
    if same then
        for index, run in ipairs(newRuns) do
            if stepKey(run) ~= stepKey(oldRuns[index]) then same = false; break end
        end
    end
    if same then return {}, false end
    local used, effects = {}, {}
    for _, run in ipairs(newRuns) do
        local match
        for index, old in ipairs(oldRuns) do
            if not used[index] and old.spell == run.spell then match = index; break end
        end
        if match then
            used[match] = true
            local old = oldRuns[match]
            if old.to ~= run.to then
                table.insert(effects, { kind = "run", spell = run.spell, fromBefore = math.max(old.from or 0, skill),
                    toBefore = old.to, from = run.from, to = run.to, countBefore = old.count, count = run.count })
            end
        else
            table.insert(effects, { kind = "added", spell = run.spell, from = run.from, to = run.to, count = run.count })
        end
    end
    for index, old in ipairs(oldRuns) do
        if not used[index] then
            table.insert(effects, { kind = "dropped", spell = old.spell, from = old.from, to = old.to })
        end
    end
    return effects, true
end

-- What the current section buys, item by item, when it is the same section
-- (the same recipe, or the same heading) in both: the biggest moves first,
-- the rest counted.
local function compareSection(old, new)
    if not old or not new then return {}, false end
    local sameSection = (old.spell ~= nil and old.spell == new.spell)
        or (old.spell == nil and new.spell == nil and old.kind == new.kind)
    if not sameSection then return {}, false end
    local effects, changedSet = {}, false
    local items = {}
    for item in pairs(old.items or {}) do items[item] = true end
    for item in pairs(new.items or {}) do items[item] = true end
    for _, item in ipairs(sortedKeys(items)) do
        local before, after = old.items[item], new.items[item]
        if before == nil or after == nil then changedSet = true end
        if before ~= after then
            table.insert(effects, { kind = "buy", item = item, before = before or 0, after = after or 0,
                section = new.title, whole = new.kind == "shopping" or nil })
        end
    end
    table.sort(effects, function(a, b)
        local left, right = math.abs(a.after - a.before), math.abs(b.after - b.before)
        if left ~= right then return left > right end
        return a.item < b.item
    end)
    if #effects > SHOWN_ITEMS + 1 then
        local more = #effects - SHOWN_ITEMS
        for index = #effects, SHOWN_ITEMS + 1, -1 do table.remove(effects, index) end
        table.insert(effects, { kind = "moreItems", count = more })
    end
    return effects, changedSet
end

-- What moved the plan, from the snapshots: prices of what it buys, the
-- skill, recipes learned, the bags.
local function causesOf(old, new)
    local causes = {}
    if old.skill ~= new.skill then table.insert(causes, { kind = "skill", before = old.skill, after = new.skill }) end
    local had = {}
    for _, spell in ipairs(old.known or {}) do had[spell] = true end
    local learned = {}
    for _, spell in ipairs(new.known or {}) do
        if not had[spell] then table.insert(learned, spell) end
    end
    if #learned > 0 then table.insert(causes, { kind = "learned", spells = learned }) end
    local prices = {}
    for item, now in pairs(new.prices or {}) do
        local was = old.prices and old.prices[item]
        if was and was.each and now.each and was.each ~= now.each then
            table.insert(prices, { kind = "price", item = item, before = was.each, after = now.each, source = now.source,
                weight = math.abs(now.each - was.each) * math.max(now.count or 1, 1) })
        end
    end
    table.sort(prices, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.item < b.item
    end)
    for _, cause in ipairs(prices) do
        cause.weight = nil
        table.insert(causes, cause)
    end
    local items = {}
    for item in pairs(old.have or {}) do items[item] = true end
    for item in pairs(new.have or {}) do items[item] = true end
    local moved = {}
    for _, item in ipairs(sortedKeys(items)) do
        local delta = (new.have[item] or 0) - (old.have and old.have[item] or 0)
        if delta ~= 0 then table.insert(moved, { item = item, delta = delta }) end
    end
    if #moved > 0 then table.insert(causes, { kind = "bags", items = moved }) end
    return causes
end

-- The entry for a new plan against the last one, or nil when there is
-- nothing to tell. `own` is the reason the player gave (Panel:Changed), nil
-- for a plan the addon made on its own; `reason` what asked for it.
function Changes:Compare(old, new, reason, own)
    if not old then
        if not own then return nil end
        old = new
    end
    local effects = {}
    local skill = new.skill or 0
    local runEffects, stepsMoved = compareRuns(ahead(old, skill), ahead(new, skill), skill)
    if #runEffects > SHOWN_RUNS + 1 then
        local more = #runEffects - SHOWN_RUNS
        for index = #runEffects, SHOWN_RUNS + 1, -1 do table.remove(runEffects, index) end
        table.insert(runEffects, { kind = "more", count = more })
    end
    local buyEffects, itemsMoved = compareSection(old.section, new.section)
    -- The current section leads: its own step, then what it buys (the
    -- shopping list's counts), then the steps after it.
    local current = new.section and new.section.spell
    for _, effect in ipairs(runEffects) do
        if current and effect.spell == current then table.insert(effects, effect) end
    end
    for _, effect in ipairs(buyEffects) do table.insert(effects, effect) end
    for _, effect in ipairs(runEffects) do
        if not (current and effect.spell == current) then table.insert(effects, effect) end
    end
    local targetMoved = old.target ~= new.target
    if targetMoved then table.insert(effects, { kind = "target", before = old.target, after = new.target }) end
    if old.net and new.net and math.abs(new.net - old.net) >= 1 then
        table.insert(effects, { kind = "net", before = old.net, after = new.net })
    end

    local causes = causesOf(old, new)
    if not own then
        local shaped = stepsMoved or targetMoved or itemsMoved
        local priced = false
        for _, cause in ipairs(causes) do
            if cause.kind == "price" then priced = true end
        end
        -- Prices alone, with the skill where it was: the route's cost moved
        -- by a share worth telling.
        local share = old.net and new.net and math.abs(new.net - old.net) / math.max(math.abs(old.net), 1) or 0
        local pricedEnough = priced and old.skill == new.skill and share >= PRICE_SHARE
        if not shaped and not pricedEnough then return nil end
        -- The section's counts move with progress too; without a change of
        -- shape they are not the news.
        if not shaped and buyEffects[1] then
            local kept = {}
            for _, effect in ipairs(effects) do
                if effect.kind ~= "buy" and effect.kind ~= "moreItems" then table.insert(kept, effect) end
            end
            effects = kept
        end
    else
        table.insert(causes, 1, { kind = "own", reason = own })
    end
    return { reason = reason, own = own, causes = causes, effects = effects }
end

-- Keeping ----------------------------------------------------------------------

-- A profession's history in a character's record (`store.planChanges`):
-- { last = snapshot, entries = { newest first } }.
function Changes:Record(store, profession, create)
    if not store or not profession then return nil end
    if type(store.planChanges) ~= "table" then
        if not create then return nil end
        store.planChanges = {}
    end
    local record = store.planChanges[profession]
    if type(record) ~= "table" then
        if not create then return nil end
        record = { entries = {} }
        store.planChanges[profession] = record
    end
    record.entries = type(record.entries) == "table" and record.entries or {}
    return record
end

-- A new plan: compared with the last, an entry kept when there is one
-- (newest first, at most `limit`), and the plan kept as the last. Answers
-- the entry, or nil.
function Changes:Note(store, profession, snapshot, reason, own, now)
    local record = self:Record(store, profession, true)
    if not record then return nil end
    local entry = self:Compare(record.last, snapshot, reason, own)
    record.last = snapshot
    if not entry then return nil end
    entry.at = now
    table.insert(record.entries, 1, entry)
    for index = #record.entries, self.limit + 1, -1 do table.remove(record.entries, index) end
    return entry
end

-- A profession's entries, newest first.
function Changes:Entries(store, profession)
    local record = self:Record(store, profession, false)
    return record and record.entries or {}
end

-- Words ------------------------------------------------------------------------

-- What the player's own change was, when the strip said nothing.
local OWN_WORDS = {
    split = "You changed how the plan is cut into sections.",
    undo = "You took back a change.",
    prices = "You changed a price.",
    scope = "You changed the testing switch.",
}

-- What asked for a plan the addon made, when nothing else explains it.
local REASON_WORDS = {
    auction = "after the auction house", trainer = "after a trainer", merchant = "after a vendor",
    open = "when the planner opened", profession = "when the profession was picked", skill = "after a skill-up",
    bags = "after your bags changed", crafted = "after a craft", tradeskill = "after the profession window",
}

local SOURCE_WORDS = { ah = " at the auction house", vendor = " at a vendor", estimate = " (guessed)" }

local function range(from, to) return tostring(from) .. "-" .. tostring(to) end

local function plural(count, one, many) return count == 1 and one or many end

-- An entry in words: `cause` (one sentence) and `effects` (a line each).
-- `names` = { item = function(id), recipe = function(spell), money =
-- function(copper) }.
function Changes:Words(entry, names)
    local item, recipe, money = names.item, names.recipe, names.money
    local why, prices = {}, {}
    for _, cause in ipairs(entry.causes or {}) do
        if cause.kind == "own" then
            table.insert(why, entry.text or OWN_WORDS[cause.reason] or "You changed the plan.")
        elseif cause.kind == "price" then
            table.insert(prices, cause)
        elseif cause.kind == "skill" then
            table.insert(why, "Skill " .. tostring(cause.before) .. " -> " .. tostring(cause.after) .. ".")
        elseif cause.kind == "learned" then
            local learned = {}
            for index, spell in ipairs(cause.spells) do
                if index > 2 then
                    table.insert(learned, (#cause.spells - 2) .. " more")
                    break
                end
                table.insert(learned, recipe(spell))
            end
            table.insert(why, "Learned " .. table.concat(learned, ", ") .. ".")
        end
    end
    -- Prices: the ones that weigh most, then how many more.
    if #prices > 0 then
        local said = {}
        for index, cause in ipairs(prices) do
            if index > SHOWN_PRICES then break end
            local went = cause.after > cause.before and "went up" or "went down"
            table.insert(said, item(cause.item) .. " " .. went .. (SOURCE_WORDS[cause.source] or "")
                .. " (" .. money(cause.before) .. " -> " .. money(cause.after) .. ")")
        end
        local more = #prices - #said
        local text = table.concat(said, "; ")
        if more > 0 then text = text .. "; " .. more .. plural(more, " more price moved", " more prices moved") end
        table.insert(why, text .. ".")
    end
    -- The bags, only beside a change of shape (Compare dropped the rest).
    if not entry.own then
        for _, cause in ipairs(entry.causes or {}) do
            if cause.kind == "bags" then
                local said = {}
                for index, moved in ipairs(cause.items) do
                    if index > SHOWN_ITEMS then
                        table.insert(said, (#cause.items - SHOWN_ITEMS) .. " more")
                        break
                    end
                    table.insert(said, (moved.delta > 0 and "+" or "") .. moved.delta .. " " .. item(moved.item))
                end
                table.insert(why, "Bags: " .. table.concat(said, ", ") .. ".")
            end
        end
    end
    if #why == 0 then
        local when = REASON_WORDS[entry.reason]
        table.insert(why, "Planned again" .. (when and (" " .. when) or "") .. ".")
    end

    local lines = {}
    for _, effect in ipairs(entry.effects or {}) do
        local kind = effect.kind
        if kind == "buy" then
            local where = effect.whole and "the whole route" or tostring(effect.section)
            table.insert(lines, item(effect.item) .. " to get for " .. where .. ": " .. effect.before .. " -> " .. effect.after)
        elseif kind == "moreItems" then
            table.insert(lines, "and " .. effect.count .. plural(effect.count, " more item", " more items"))
        elseif kind == "run" then
            local crafts = ""
            if effect.countBefore and effect.count and effect.countBefore ~= effect.count then
                crafts = ", " .. effect.countBefore .. " -> " .. effect.count .. " crafts"
            end
            table.insert(lines, recipe(effect.spell) .. ": " .. range(effect.fromBefore, effect.toBefore) .. " -> "
                .. range(effect.from, effect.to) .. crafts)
        elseif kind == "added" then
            table.insert(lines, "Now " .. recipe(effect.spell) .. " " .. range(effect.from, effect.to)
                .. (effect.count and (", " .. effect.count .. plural(effect.count, " craft", " crafts")) or ""))
        elseif kind == "dropped" then
            table.insert(lines, "No more " .. recipe(effect.spell) .. " " .. range(effect.from, effect.to))
        elseif kind == "more" then
            table.insert(lines, "and " .. effect.count .. plural(effect.count, " more step", " more steps"))
        elseif kind == "target" then
            table.insert(lines, "Target " .. tostring(effect.before) .. " -> " .. tostring(effect.after))
        elseif kind == "net" then
            table.insert(lines, "Route cost " .. money(effect.before) .. " -> " .. money(effect.after))
        end
    end
    if #lines == 0 then table.insert(lines, "The plan stayed the same.") end
    return table.concat(why, " "), lines
end

-- One line for the status strip: the cause, then the first effect.
function Changes:Summary(entry, names)
    local cause, lines = self:Words(entry, names)
    local first = lines[1]
    if not first or first == "The plan stayed the same." then return cause end
    return cause .. " " .. first .. "."
end

ns:RegisterModule("PlanChanges", Changes)
