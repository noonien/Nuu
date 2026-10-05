local _, ns = ...

-- The place recorder: a small window of its own for walking a cave (or a
-- tunnel, a ramp, a building) into a guide place, with the guide editor put
-- away so the world is in view.
--
-- It records a trail and nothing else: a sample every three yards, and
-- whenever the indoors, falling or swimming flag or the map changes, of what
-- the client says - where the player is on the map and in world yards,
-- indoors, falling, swimming, facing, the subzone - plus any spot the author
-- names with Mark. No point is made while walking and none is placed by
-- hand. Every sample goes to the session log (`placetrail`) the moment it is
-- taken, after a `start` row naming the walk, so a reload or a crash mid-walk
-- loses nothing; Stop only adds a `stop` row. The place is worked out from
-- the trail afterwards (Domain/PlaceEditing.lua's Process): once here when
-- the walk stops, to show it, and outside the game with any settings
-- (Tools/SessionLog/places.py puts the rows back together, then
-- Tools/ProcessPlace.lua).
--
-- How to walk: stand outside the mouth, press Record, walk every passage,
-- and come back out. Walking back over a passage adds nothing once it is
-- processed, a loop closes itself, the mouths come from the indoors flag and
-- a drop is one way from its fall. Mark names the spot you stand on ("the
-- bank"), which a step can then stand on; it is optional.
--
-- Built from NuuKit's widgets.
-- The window's place is the kit's (NuuRoadDB.windows.placeRecorder); the
-- indoors switch is the `placeRecorder.outdoors` setting.
local PlaceRecorder = { interval = 0.2, minYards = 3 }

local WIDTH, HEIGHT = 340, 262

local function editing() return ns.modules.PlaceEditing end
local function client() return ns.modules.Client end
local function now() return GetTime and GetTime() or 0 end

-- A walk still going at logout is stopped, so its `stop` row is in the log.
function PlaceRecorder:Initialize()
    if type(CreateFrame) ~= "function" then return end
    local events = CreateFrame("Frame")
    pcall(events.RegisterEvent, events, "PLAYER_LOGOUT")
    events:SetScript("OnEvent", function() if self.recording then self:StopRecording() end end)
    self.events = events
end

-- Its settings as they apply (Config.settings.placeRecorder).
function PlaceRecorder:Settings()
    return ns.modules.Config:Get("placeRecorder") or {}
end

-- The switch changed, here or in Options: the place again from the walk.
function PlaceRecorder:OnSettingChanged(path)
    if path ~= "placeRecorder.outdoors" and path ~= "placeRecorder" then return end
    if self.win then self:Reprocess() end
end

-- The widgets' callbacks ------------------------------------------------------------------

local function nameCommitted() PlaceRecorder:ApplyName() end
local function recordClicked() PlaceRecorder:ToggleRecording() end
local function markClicked() PlaceRecorder:Mark() end
local function luaClicked() PlaceRecorder:ShowLua() end
local function editorClicked() PlaceRecorder:SendToEditor() end
local function newClicked() PlaceRecorder:Start(nil) end
local function indoorsToggled(on)
    ns.modules.Config:Set("placeRecorder.outdoors", not on)
end
local function windowHidden()
    local self = PlaceRecorder
    ns:GetUI():HideTooltip()
    self:StopRecording()
    local Places = ns.modules.PlacesPanel
    if Places then Places:DrawMap() end
end

local function sampleTick(frame, elapsed)
    frame.since = (frame.since or 0) + elapsed
    if frame.since < PlaceRecorder.interval then return end
    frame.since = 0
    PlaceRecorder:Sample()
end

function PlaceRecorder:Create()
    if self.win then return end
    local ui = ns:GetUI()
    local db = ns.db
    local places = db and db.windows
    if not places then
        places = {}
        if db then db.windows = places end
    end
    -- Escape leaves it up: it is walked with, not read, and closing it would
    -- stop the walk.
    local win = ui:Window({
        key = "placeRecorder", title = "Place recorder", width = WIDTH, height = HEIGHT,
        place = places, hidden = true, escape = false, point = { "TOPLEFT", UIParent, "TOPLEFT", 40, -200 },
    })
    win:HookScript("OnHide", windowHidden)
    self.win, self.frame = win, win

    local body = win:Column{ padding = 10, gap = 8 }
    self.name = body:Input{ placeholder = "Name in the tracker (default: the subzone)", onChange = nameCommitted }
    self.status = body:Text{ "", wrap = true }

    self.record = body:Button{ "Record", tone = "accent", onClick = recordClicked,
        tooltip = "Start outside the mouth, walk every passage, and come back out. A sample is taken every three"
            .. " yards; nothing else to press." }

    local mark = body:Row{ gap = 4 }
    self.markText = mark:Input{ placeholder = "the bank", grow = true }
    mark:Button{ "Mark", onClick = markClicked,
        tooltip = "Optional: name the spot you stand on, so a step can stand on it as place.name. It adds no point." }

    local row = body:Row{ gap = 6 }
    self.indoorsToggle = row:Toggle{ "Indoors only", onChange = indoorsToggled,
        tooltip = "Keep to where the game says you are indoors, and mark the ways in and out from that. Turn it off"
            .. " for a tunnel or ravine the game counts as outdoors; the place is worked out again from the same walk." }
    row:Spacer{}
    row:Button{ "Lua", onClick = luaClicked, tooltip = "The place as guide source, to copy into a guide's places list." }
    self.toEditor = row:Button{ "To editor", onClick = editorClicked,
        tooltip = "Add this place to the guide open in the editor (or the guide you are following), and open its"
            .. " Places tab." }

    local foot = body:Row{ gap = 8 }
    foot:Button{ "New place", onClick = newClicked,
        tooltip = "Start another place. The walk on screen stays in the session log." }
    self.hint = foot:Text{ "", style = "fine", color = "muted", wrap = true, grow = true }

    -- The sampler runs only while a walk is recorded.
    local sampler = CreateFrame("Frame")
    sampler:SetScript("OnUpdate", sampleTick)
    sampler:Hide()
    self.sampler = sampler
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

-- Each point's position in world yards, which only the client can work out
-- from map percentages; for a place that already has points.
local function positionsOf(place)
    local Client = client()
    local positions = {}
    for index, point in ipairs(place.points) do
        local map = point.map or place.map
        local _, wx, wy = Client:GetWorldPosition(map, point.at[1] / 100, point.at[2] / 100)
        positions[index] = wx and { x = wx, y = wy } or false
    end
    return positions
end

-- Where the walk goes: a place in the editor's guide (`target` from the
-- Places tab, extended from its selected point), or a fresh one of the
-- recorder's own.
function PlaceRecorder:Start(target)
    self:StopRecording()
    self.count = (self.count or 0) + 1
    local map = client():GetCurrentMapID()
    if target then
        self.guide, self.place, self.from, self.owned = target.guide, target.place, target.from, false
    else
        self.place = { place = "recorded" .. self.count, map = map, points = {}, connections = {} }
        self.guide = { places = { self.place }, nodes = {} }
        self.from, self.owned = nil, true
    end
    -- What the walk started from, so the trail can be worked out again.
    self.base, self.basePositions = copy(self.place), positionsOf(self.place)
    self.trail = { id = tostring(time and time() or 0) .. "-" .. self.count, map = map, samples = {}, marks = {} }
    self.lastSample, self.startedAt, self.walked, self.simplified = nil, nil, 0, nil
    self:Render()
end

function PlaceRecorder:Open(target)
    self:Create()
    if target or not self.place then self:Start(target) end
    self.win:Show()
    self:Render()
    local Places = ns.modules.PlacesPanel
    if Places then Places:DrawMap() end
end

function PlaceRecorder:Close()
    self:StopRecording()
    if self.win then self.win:Hide() end
    local Places = ns.modules.PlacesPanel
    if Places then Places:DrawMap() end
end

function PlaceRecorder:Toggle()
    if self.win and self.win:IsShown() then self:Close() else self:Open() end
end

function PlaceRecorder:ApplyName()
    local text = self.name and self.name:GetText()
    if not self.place or not text then return end
    if text:match("%S") and not text:find("[\128-\255]") then
        self.place.name = text
        if self.trail then self.trail.name = text end
    end
end

function PlaceRecorder:ToggleRecording()
    if self.recording then return self:StopRecording() end
    if not self.place then self:Start(nil) end
    self:ApplyName()
    self.recording = true
    ns:Record("placetrail", { event = "start", trail = self.trail.id, name = self.trail.name, map = self.trail.map,
        place = self.place.place })
    self.sampler.since = 0
    self.sampler:Show()
    self:Sample(true)
    self:Render()
end

-- Stopping finishes the trail in the session log and works the place out
-- from it, once.
function PlaceRecorder:StopRecording()
    if not self.recording then return end
    self.recording = false
    if self.sampler then self.sampler:Hide() end
    self:ApplyName()
    ns:Record("placetrail", { event = "stop", trail = self.trail.id, name = self.trail.name, samples = #self.trail.samples })
    self:Reprocess()
end

-- The place again from the whole trail with the settings on screen: what
-- Stop and the indoors switch do, and what Tools/ProcessPlace.lua does with
-- other settings outside the game.
function PlaceRecorder:Reprocess()
    if not self.trail or not self.base then return self:Render() end
    local place, stats = editing().Process(self.trail, { base = self.base, positions = self.basePositions,
        from = self.from, indoorsOnly = not self:Settings().outdoors, guide = self.guide })
    -- The editor's guide holds the place table itself, so its contents are
    -- replaced rather than the table.
    for key in pairs(self.place) do self.place[key] = nil end
    for key, value in pairs(place) do self.place[key] = value end
    self.simplified = stats and stats.removed
    self:Render()
    self:Changed()
end

-- One reading, kept when the player has moved three yards or a flag or the
-- map changed. Nothing is worked out from it until the walk stops.
function PlaceRecorder:Sample(force, marks)
    if not self.recording or not self.trail then return end
    local Client = client()
    if Client:IsOnTaxi() then return end
    local map = Client:GetCurrentMapID()
    if not map then return end
    local x, y = Client:GetPlayerMapPosition(map)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local _, wx, wy = Client:GetWorldPosition(map, x, y)
    if not wx then return end
    local indoors, falling = Client:IsIndoors(), Client:IsFalling()
    local swimming = Client:Read(rawget(_G, "IsSwimming"))
    local facing = Client:Read(rawget(_G, "GetPlayerFacing"))
    local zone = Client:GetSubzone()
    local last = self.lastSample
    local moved = not last or math.sqrt((wx - last.w[1]) ^ 2 + (wy - last.w[2]) ^ 2) >= self.minYards
    local swims = swimming == true or swimming == 1
    local changed = not last or (last.indoors or false) ~= (indoors or false) or (last.falling or false) ~= (falling or false)
        or (last.swimming or false) ~= swims or last.map ~= map
    if not (force or marks or moved or changed) then return end
    local sample = { t = math.floor((now() - (self.startedAt or now())) * 10 + 0.5) / 10, map = map,
        at = { math.floor(x * 10000 + 0.5) / 100, math.floor(y * 10000 + 0.5) / 100 },
        w = { math.floor(wx * 10 + 0.5) / 10, math.floor(wy * 10 + 0.5) / 10 } }
    if indoors ~= nil then sample.indoors = indoors end
    if falling then sample.falling = true end
    if swims then sample.swimming = true end
    if type(facing) == "number" then sample.facing = math.floor(facing * 100 + 0.5) / 100 end
    if zone and zone ~= self.lastZone then sample.zone = zone; self.lastZone = zone end
    self.startedAt = self.startedAt or now()
    if last and last.map == map then
        self.walked = (self.walked or 0) + math.sqrt((wx - last.w[1]) ^ 2 + (wy - last.w[2]) ^ 2)
    end
    table.insert(self.trail.samples, sample)
    self.lastSample = sample
    for _, mark in ipairs(marks or {}) do
        mark.sample = #self.trail.samples
        table.insert(self.trail.marks, mark)
    end
    -- Into the log at once; the marks ride on the sample they were made at.
    ns:Record("placetrail", { event = "sample", trail = self.trail.id, s = sample, marks = marks })
    self.indoors = indoors
    self:Render()
end

function PlaceRecorder:Mark()
    if not self.win then return end
    if not self.recording then
        self.status:SetText("Marks are made while recording: press Record first.")
        return
    end
    local label = self.markText:GetText()
    label = (label and label:match("%S") and not label:find("[\128-\255]")) and label or nil
    if not label then
        self.status:SetText("Type what the spot is called, then Mark.")
        return
    end
    self:Sample(true, { { label = label } })
    self.markText:SetText("")
end

-- The place lives in the editor's guide: its tab and map drawing follow.
function PlaceRecorder:Changed()
    local Places = ns.modules.PlacesPanel
    if not Places then return end
    if not self.owned and Places.frame and Places.frame:IsShown() then Places:Render() else Places:DrawMap() end
end

-- The place as guide source, in a window of its own to select and copy.
function PlaceRecorder:ShowLua()
    if not self.place or #self.place.points == 0 then return end
    self:ApplyName()
    local title = "Place " .. self.place.place .. " - paste into the guide's places = { ... }"
    local text = editing().Serialize(self.place)
    if not self.source then
        local ui = ns:GetUI()
        local places = ns.db and ns.db.windows or {}
        local win = ui:Window({ key = "placeSource", title = "Place source", width = 560, height = 380,
            resizable = true, minWidth = 360, minHeight = 220, place = places, hidden = true })
        local body = win:Column{ padding = 10, gap = 8 }
        self.sourceTitle = body:Text{ "", style = "label", wrap = true }
        self.sourceText = body:TextArea{ boxHeight = 260, grow = true }
        self.source = win
    end
    self.sourceTitle:SetText(title)
    self.sourceText:SetText(text)
    self.source:Show()
    self.sourceText:SetFocus()
end

-- A place of the recorder's own goes into the guide in the editor, or the
-- one being followed opened in it; it takes a free ID there.
function PlaceRecorder:SendToEditor()
    local Editor = ns.modules.Editor
    if not self.place or #self.place.points == 0 or not Editor then return end
    self:StopRecording()
    if not self.owned then
        Editor:Show()
        Editor:SelectTab("places")
        return
    end
    local guide = Editor:PlacesGuide()
    if not guide then return end
    guide.places = guide.places or {}
    local base, id, number = self.place.place, self.place.place, 1
    while editing().Find(guide, id) do number = number + 1; id = base .. "_" .. number end
    local added = copy(self.place)
    added.place = id
    table.insert(guide.places, added)
    -- From here on, more walking extends the copy in the editor.
    self.guide, self.place, self.owned, self.from = guide, added, false, nil
    self.base, self.basePositions = copy(added), positionsOf(added)
    self.trail = { id = self.trail.id .. "+", map = added.map, samples = {}, marks = {} }
    self.lastSample, self.startedAt = nil, nil
    local Places = ns.modules.PlacesPanel
    if Places then Places.placeIndex = #guide.places end
    Editor:Show()
    Editor:SelectTab("places")
    Editor:SetStatus("Added " .. id .. " to this guide.")
    self:Render()
end

function PlaceRecorder:Render()
    if not self.win then return end
    local place = self.place
    if place and not self.name:HasFocus() then self.name:SetText(place.name or "") end
    local points = place and #place.points or 0
    local where = self.owned and "own place" or "in the editor's guide"
    local samples = self.trail and #self.trail.samples or 0
    local status
    if self.recording then
        local inside = self.indoors == true and "indoors" or (self.indoors == false and "outdoors" or "indoors unknown")
        local marks = self.trail and #self.trail.marks or 0
        status = string.format("Recording: %d samples over %d yards, %d marked. You are %s.", samples,
            math.floor((self.walked or 0) + 0.5), marks, inside)
    elseif points > 0 then
        status = string.format("%d points, %d connections (%s).%s", points, #place.connections, where,
            (self.simplified or 0) > 0 and (" " .. self.simplified .. " straight-line points tidied.") or "")
    else
        status = "Stand outside the mouth, press Record, walk every passage, and come back out."
    end
    self.status:SetText(status)
    local outdoors = self:Settings().outdoors
    self.indoorsToggle:SetValue(not outdoors)
    self.record:SetText(self.recording and "Stop" or "Record")
    self.toEditor:SetText(self.owned and "To editor" or "Editor")
    self.hint:SetText(outdoors and "Keeping outdoor samples too; fix the mouths in the editor."
        or "Ways in and out come from the indoors flag.")
end

-- For the map drawing: the place on screen while the recorder is open.
function PlaceRecorder:ShownPlace()
    if self.win and self.win:IsShown() then return self.place end
    return nil
end

ns:RegisterModule("PlaceRecorder", PlaceRecorder)
