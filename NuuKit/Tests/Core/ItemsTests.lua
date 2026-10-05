-- Kit.Items: names now or a stand-in, and Track's runs again until nothing
-- is missing; each item asked for once,
-- asked again once without an answer, then given up.
local saved = { C_Item = _G.C_Item, CreateFrame = _G.CreateFrame, C_Timer = _G.C_Timer }

local names, requests, frame, now, timers
local function client()
    names, requests, frame, now, timers = { [2934] = "Ruined Leather Scraps" }, {}, nil, 0, {}
    _G.C_Item = {
        GetItemNameByID = function(id) return names[id] end,
        RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end,
    }
    _G.CreateFrame = function()
        frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(_, fn) self.onEvent = fn end
        return frame
    end
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
    return _G.LoadKit().Kit.Items
end
-- Runs the timers that fall due, in order, those they add included.
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
-- The server answers: the name is in, and the event comes.
local function answer(id, name, event)
    names[id] = name
    frame.onEvent(frame, event or "ITEM_DATA_LOAD_RESULT", id, name ~= nil)
end
local function count(list, id)
    local n = 0
    for _, value in ipairs(list) do if value == id then n = n + 1 end end
    return n
end

-- Name: the name, or "Item <id>" and the item asked for, once.
local Items = client()
assert(Items:Name(2934) == "Ruined Leather Scraps" and #requests == 0, "a known name asks nothing")
assert(Items:Name(4289) == "Item 4289" and requests[1] == 4289, "a missing name stands in and is asked for")
assert(Items:Name(4289) == "Item 4289" and #requests == 1, "asked once")
assert(Items:Name("x") == "Item x" and #requests == 1, "not an item ID: a stand-in, nothing asked")
assert(frame.events.ITEM_DATA_LOAD_RESULT and frame.events.GET_ITEM_INFO_RECEIVED, "both events heard")
answer(4289, "Salt", "GET_ITEM_INFO_RECEIVED")
assert(Items:Name(4289) == "Salt")

-- Answers to items not asked for here are ignored.
Items = client()
local seenRuns = 0
local function quiet() seenRuns = seenRuns + 1; Items:Name(4291) end
Items:Track(quiet)
frame.onEvent(frame, "ITEM_DATA_LOAD_RESULT", 6948, true)
advance(0)
assert(seenRuns == 1, "another item's answer runs nothing")

-- Preload asks for what is not in, once.
Items = client()
Items:Preload({ 2934, 4340, 4340, 1206 })
assert(#requests == 2 and requests[1] == 4340 and requests[2] == 1206, "only the missing ones, once each")

-- Track: one run again once every missed name is in, on the next tick.
Items = client()
local runs, seen = 0, nil
local function draw()
    runs = runs + 1
    seen = Items:Name(2934) .. ", " .. Items:Name(4289) .. ", " .. Items:Name(4291)
end
Items:Track(draw)
assert(runs == 1 and seen == "Ruined Leather Scraps, Item 4289, Item 4291")
answer(4289, "Salt")
advance(0)
assert(runs == 1, "one of two in: no run yet")
answer(4291, "Silken Thread")
assert(runs == 1, "not inside the event")
advance(0)
assert(runs == 2 and seen == "Ruined Leather Scraps, Salt, Silken Thread", "both in: run once again")
advance(10)
assert(runs == 2, "nothing missing: no more runs")

-- A run before the answers came replaces the wait: still one run again.
Items = client()
runs = 0
local function twice() runs = runs + 1; Items:Name(4289) end
Items:Track(twice)
Items:Track(twice)
answer(4289, "Salt")
advance(0)
assert(runs == 3, "one run again for two runs that missed: " .. runs)

-- Again while a run misses new items, until none is missing.
Items = client()
runs = 0
local function chain()
    runs = runs + 1
    if Items:Name(4289) ~= "Item 4289" then Items:Name(4291) end
end
Items:Track(chain)
answer(4289, "Salt")
advance(0)
assert(runs == 2 and requests[#requests] == 4291, "the second run asks for a new item")
answer(4291, "Silken Thread")
advance(0)
assert(runs == 3, "and runs again once it is in")
advance(10)
assert(runs == 3)

-- Nested: a name missed counts for the innermost Track only.
Items = client()
local outer, inner = 0, 0
local function innerDraw() inner = inner + 1; Items:Name(4289) end
local function outerDraw() outer = outer + 1; Items:Track(innerDraw) end
Items:Track(outerDraw)
answer(4289, "Salt")
advance(0)
assert(outer == 1 and inner == 2, "only the inner run again")

-- An error in fn is raised again, and the run is closed.
Items = client()
local ok, err = pcall(Items.Track, Items, function() error("boom", 0) end)
assert(not ok and err == "boom", tostring(err))
runs = 0
Items:Name(4289)
answer(4289, "Salt")
advance(0)
assert(runs == 0, "a name read after the failed run counts for no run")

-- No answer: asked again after a while, then given up; the waits end.
Items = client()
runs = 0
local function waits() runs = runs + 1; Items:Name(7777) end
Items:Track(waits)
advance(2)
assert(count(requests, 7777) == 2 and runs == 1, "asked again once")
advance(2)
assert(count(requests, 7777) == 2 and runs == 2, "then given up, and the run waiting on it runs again")
advance(10)
assert(runs == 2 and count(requests, 7777) == 2 and Items:Name(7777) == "Item 7777", "never asked again, no more runs")
-- A name that came without its event is found when the wait runs out.
runs = 0
local function gray() runs = runs + 1; seen = Items:Name(5555) end
Items:Track(gray)
names[5555] = "Gray Dye"
advance(2)
assert(runs == 2 and seen == "Gray Dye" and count(requests, 5555) == 1, "found, not asked again")

_G.C_Item, _G.CreateFrame, _G.C_Timer = saved.C_Item, saved.CreateFrame, saved.C_Timer
