local _, ns = ...

-- How an item the client has never loaded gets its name. The planner's lists
-- showed "item 4289" until opened again: they ask C_Item.GetItemNameByID,
-- request the item (C_Item.RequestLoadItemDataByID) and redraw on
-- GET_ITEM_INFO_RECEIVED. The first run found its five items cached already,
-- so this one picks items that are not: it scans item IDs for ones that exist
-- and are not cached, and splits them three ways:
--
--   request  RequestLoadItemDataByID, as the planner does
--   name     only GetItemNameByID: does asking a name load the item?
--   none     left alone: does the scan itself load anything?
--
-- For each item: whether GET_ITEM_INFO_RECEIVED came and when, its success
-- flag, whether the name was readable at the event and a tenth of a second
-- later, and the name and cache flag at the end.
--
-- Run 1 (1.60.1 (70205), 2026-10-05) saw no GET_ITEM_INFO_RECEIVED at all,
-- while 22 of 60 items loaded; DoesItemExistByID said yes to every ID, and
-- most IDs past 22000 never loaded. So this run also listens for
-- ITEM_DATA_LOAD_RESULT (what newer clients send for RequestLoadItemDataByID),
-- times each name by polling every tenth of a second, and scans only up to
-- 20000.
local SCAN_TO = 20000
local PER_GROUP = 20
local GROUPS = { "request", "name", "none" }
local WAIT = 12

local function now() return GetTime and GetTime() or 0 end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function nameOf(id) return call(C_Item.GetItemNameByID, id) end
local function cached(id) return call(C_Item.IsItemDataCachedByID, id) and true or false end

ns:Experiment({
    id = "item-names",
    title = "Item names for items never loaded",
    run = function(t)
        t:Exists({ "C_Item.GetItemNameByID", "C_Item.RequestLoadItemDataByID", "C_Item.IsItemDataCachedByID",
            "C_Item.DoesItemExistByID", "GetItemInfo" })
        if not (C_Item and C_Item.DoesItemExistByID and C_Item.IsItemDataCachedByID and C_Item.GetItemNameByID) then
            t:Log("the C_Item functions this needs are missing")
            return
        end

        -- Existing, uncached items, spread over the range.
        local started = now()
        local candidates, existing, cachedCount = {}, 0, 0
        for id = 1, SCAN_TO do
            if call(C_Item.DoesItemExistByID, id) then
                existing = existing + 1
                if cached(id) then cachedCount = cachedCount + 1 else candidates[#candidates + 1] = id end
            end
        end
        t:Set("scan", { range = "1-" .. SCAN_TO, existing = existing, cached = cachedCount,
            uncached = #candidates, ms = math.floor((now() - started) * 1000) })
        local want = PER_GROUP * #GROUPS
        if #candidates < want then t:Log("only %d uncached items to try", #candidates) end
        local picked, step = {}, math.max(#candidates / want, 1)
        for index = 1, math.min(want, #candidates) do
            picked[#picked + 1] = candidates[math.floor((index - 1) * step) + 1]
        end

        -- Each item's row, by group.
        local rows, groupOf = {}, {}
        for index, id in ipairs(picked) do
            local group = GROUPS[(index - 1) % #GROUPS + 1]
            groupOf[id] = group
            rows[id] = { group = group }
        end

        local others = 0
        local begun = now()
        local function seconds() return math.floor((now() - begun) * 100 + 0.5) / 100 end
        local loadResults, loadOthers = 0, 0
        t:On("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
            local row = rows[itemID]
            if not row then
                others = others + 1
                return
            end
            row.events = (row.events or 0) + 1
            if row.events > 1 then return end
            row.eventAt = seconds()
            row.success = tostring(success)
            row.nameAtEvent = nameOf(itemID) ~= nil
            row.cachedAtEvent = cached(itemID)
            t:After(0.1, function() row.nameAfterTenth = nameOf(itemID) ~= nil end)
        end)
        t:On("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
            local row = rows[itemID]
            if not row then
                loadOthers = loadOthers + 1
                return
            end
            loadResults = loadResults + 1
            if row.loadAt then return end
            row.loadAt = seconds()
            row.loadSuccess = tostring(success)
            row.nameAtLoad = nameOf(itemID) ~= nil
        end)
        -- When each item is cached and its name reads, to a tenth of a
        -- second. Asking a name loads the item (run 1), so the poll asks
        -- only the cache flag, and a name once the item is cached.
        local polls = 0
        local function poll()
            polls = polls + 1
            for id, row in pairs(rows) do
                if not row.namedAt and cached(id) and nameOf(id) then row.namedAt = seconds() end
            end
            if polls < WAIT * 10 - 1 then t:After(0.1, poll) end
        end

        t:After(0.1, poll)
        for id, row in pairs(rows) do
            if row.group == "request" then
                call(C_Item.RequestLoadItemDataByID, id)
                row.nameRightAway = nameOf(id) ~= nil
            elseif row.group == "name" then
                row.nameRightAway = nameOf(id) ~= nil
            end
        end

        t:Wait(WAIT + 5)
        local ticks = 0
        local function tick()
            ticks = ticks + 1
            t:Progress(ticks, WAIT, "waiting for the server")
            if ticks < WAIT then t:After(1, tick) end
        end
        t:After(1, tick)
        t:After(WAIT, function()
            local summary, items = {}, {}
            for _, group in ipairs(GROUPS) do
                summary[group] = { items = 0, events = 0, namedAtEvent = 0, namedTenthAfter = 0, namedAtEnd = 0,
                    cachedAtEnd = 0, namedRightAway = 0, slowestEvent = 0, loadResults = 0, slowestName = 0 }
            end
            for id, row in pairs(rows) do
                local name = cached(id) and nameOf(id) or nil
                local sum = summary[row.group]
                sum.items = sum.items + 1
                if row.eventAt then
                    sum.events = sum.events + 1
                    sum.slowestEvent = math.max(sum.slowestEvent, row.eventAt)
                end
                if row.loadAt then sum.loadResults = sum.loadResults + 1 end
                if row.namedAt then sum.slowestName = math.max(sum.slowestName, row.namedAt) end
                if row.nameAtEvent then sum.namedAtEvent = sum.namedAtEvent + 1 end
                if row.nameAfterTenth then sum.namedTenthAfter = sum.namedTenthAfter + 1 end
                if row.nameRightAway then sum.namedRightAway = sum.namedRightAway + 1 end
                if name then sum.namedAtEnd = sum.namedAtEnd + 1 end
                if cached(id) then sum.cachedAtEnd = sum.cachedAtEnd + 1 end
                -- One line an item: "request: event 0.31s (true), name at event yes, +0.1s yes, end Salt".
                items[tostring(id)] = row.group .. ": "
                    .. (row.eventAt and ("event " .. row.eventAt .. "s (" .. row.success .. ")"
                        .. (row.events > 1 and (" x" .. row.events) or "")
                        .. ", name at event " .. (row.nameAtEvent and "yes" or "no")
                        .. ", +0.1s " .. (row.nameAfterTenth and "yes" or "no")) or "no event")
                    .. (row.loadAt and (", load result " .. row.loadAt .. "s (" .. row.loadSuccess .. "), name then "
                        .. (row.nameAtLoad and "yes" or "no")) or ", no load result")
                    .. (row.namedAt and (", named at " .. row.namedAt .. "s") or "")
                    .. ", end " .. (name or "no name") .. (cached(id) and "" or " (not cached)")
            end
            t:Set("summary", summary)
            t:Set("otherEvents", others)
            t:Set("loadResults", { ours = loadResults, others = loadOthers })
            t:Set("items", items)
            t:Done()
        end)
    end,
})
