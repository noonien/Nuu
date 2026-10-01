local _, ns = ...

-- The options window, and the diagnostics window beside it.
--
-- Ported from OpenRoad's UI/MainWindow.lua (CreateOptions, ResetOptions,
-- RefreshOptionLabels, SyncOptions, PlaceWindows, CreateDiagnostics,
-- ShowDiagnostics), rebuilt on NuuKit: each option is a kit Setting row,
-- what it is and what it does on the left, its control on the right, and a
-- reset beside it while the player's choice is stored.
--
-- Every control is bound (`bind`) to NuuRoadDB.settings through `store`
-- below, a stand-in table whose keys are setting paths ("tracker.scale"):
-- reading one answers the player's stored choice (nil when there is none),
-- writing one goes through Config:Set, or the setter that checks the value
-- (Config:SetStepListRows, SetRealmSetting...), and writing nil goes through
-- Config:Reset. So a choice made here is stored exactly as Config stores it,
-- and Config:Changed tells every module that shows the setting
-- (OnSettingChanged). This window listens the same way, so a setting
-- changed elsewhere (the tracker's menu) shows here too.
--
-- What changed from OpenRoad: the panel opacity slider is gone (the look's
-- opacity in Appearance replaces it); window places are the kit's
-- (NuuRoadDB.windows), so "Reset window positions" forgets them rather than
-- resetting point and offset settings; Appearance (the kit's LookPicker) is
-- new. tracker.shown and tracker.collapsed are the tracker's own state, not
-- options, and stay off this page as they were in OpenRoad.
local Options = {}

local LABEL_WIDTH = 250

local function Config() return ns.modules.Config end

-- Settings shown as something other than what is stored: the tracker's
-- size is stored as a scale (1.05) and shown in percent (105); the realm's
-- experience rate is typed as text.
local CODECS = {
    ["tracker.scale"] = {
        read = function(value) return math.floor((tonumber(value) or 1) * 100 + 0.5) end,
        write = function(value) return (tonumber(value) or 100) / 100 end,
    },
    ["realm.xpRate"] = {
        read = function(value) return value ~= nil and tostring(value) or nil end,
    },
}

-- Settings a plain Config:Set would store unchecked: these go through the
-- setter that holds them to their range, or through the module that must
-- hear about the change first.
local WRITES = {
    ["recording.enabled"] = function(value)
        local Recording = ns.modules.Recording
        -- Through the recorder, so the log says when recording started or
        -- stopped.
        if Recording then Recording:SetEnabled(value) else Config():Set("recording.enabled", value and true or false) end
    end,
    ["recording.keepDays"] = function(value) Config():SetRecordingKeepDays(value) end,
    ["stepList.rows"] = function(value) Config():SetStepListRows(value) end,
    ["navigation.mapPinsAhead"] = function(value) Config():SetMapPinsAhead(value) end,
    ["realm.xpRate"] = function(value) Config():SetRealmSetting("xpRate", value) end,
    ["realm.auctionHouse"] = function(value) Config():SetRealmSetting("auctionHouse", value) end,
    ["realm.selfFound"] = function(value) Config():SetRealmSetting("selfFound", value) end,
}

local RESETS = {
    -- Back to the default goes through the recorder too.
    ["recording.enabled"] = function()
        local Recording, wanted = ns.modules.Recording, Config():Default("recording.enabled") and true or false
        if Recording and Recording:Enabled() ~= wanted then Recording:SetEnabled(wanted) end
        Config():Reset("recording.enabled")
    end,
}

-- Writes a setting as the player chose it; nil forgets the choice.
function Options:Write(path, value)
    local config = Config()
    if not config then return end
    if value == nil then
        local reset = RESETS[path]
        if reset then reset() else config:Reset(path) end
        return
    end
    local codec = CODECS[path]
    if codec and codec.write then value = codec.write(value) end
    local write = WRITES[path]
    if write then write(value) else config:Set(path, value) end
end

-- The table the controls are bound to: its keys are setting paths.
local store = setmetatable({}, {
    __index = function(_, path)
        local config = Config()
        if not (config and config:IsSet(path)) then return nil end
        local value = config:Get(path)
        local codec = CODECS[path]
        if codec and codec.read then value = codec.read(value) end
        return value
    end,
    __newindex = function(_, path, value) Options:Write(path, value) end,
})
Options.store = store

-- `bind` for a control showing the setting at `path`; the RecordingPanel
-- binds its switch and its days the same way.
function Options:Bind(path) return { store, path } end

-- The setting's default as its control shows it.
function Options:DefaultValue(path)
    local value = Config():Default(path)
    local codec = CODECS[path]
    if value ~= nil and codec and codec.read then value = codec.read(value) end
    return value
end

-- The page ---------------------------------------------------------------------------------

-- Section by section. `kind` is the control; `label` names the row, `caption`
-- is a toggle's own words, `help` says what it does (OpenRoad's tooltip).
local SECTIONS = {
    { title = "Tracker", rows = {
        { path = "tracker.scale", kind = "slider", label = "Tracker size", min = 80, max = 140, step = 5, format = "%d%%",
            help = "How big the tracker, the arrow and the strips beside it are." },
        { path = "stepList.rows", kind = "slider", label = "Steps on screen", min = 0, max = 20, step = 1, format = "%d",
            help = "How many steps of the guide list show under the current one. 0 puts the list away." },
        { path = "tracker.markWaiting", kind = "toggle", label = "Steps not open yet", caption = "Mark them on the bar",
            help = "Paints amber the steps the guide will wait on: a quest to take first, a level, an item." },
        { path = "tracker.upward", kind = "toggle", label = "Tracker growth", caption = "Grow upward",
            help = "Its controls at the foot and the tracker growing up from them: tabs, bar and step card stack"
                .. " above in reverse, the step list on top." },
    } },
    { title = "Arrow and map", rows = {
        { path = "navigation.standalone", kind = "toggle", label = "Arrow window", caption = "Show the arrow window",
            help = "The arrow and the distance to the step in a window of their own." },
        { path = "navigation.mapPinsAhead", kind = "slider", label = "Map pins ahead", min = 0, max = 15, step = 1, format = "%d",
            help = "How many steps past the current one get a numbered pin on the world map. 0 pins the current step only." },
    } },
    { title = "Travel routes", rows = {
        { path = "navigation.travel.suggest", kind = "toggle", label = "Routes", caption = "Suggest travel routes",
            help = "Off, the arrow points straight at the step." },
        { path = "navigation.travel.flights", kind = "toggle", label = "Flights", caption = "Use flight paths" },
        { path = "navigation.travel.teleports", kind = "toggle", label = "Teleports", caption = "Use hearthstone and teleports",
            help = "Counts any cooldown left; the button appears in the item strip." },
        { path = "navigation.travel.links", kind = "toggle", label = "Boats", caption = "Use boats and zeppelins" },
        { path = "navigation.travel.highlight", kind = "toggle", label = "Flight master",
            caption = "Highlight the destination", help = "The route's next stop is lit on the flight master's map." },
    }, foot = "Click the route line under a step to walk instead for that step. Flight times are learned as you fly." },
    { title = "NPC conveniences", rows = {
        { path = "automation.markTargets", kind = "toggle", label = "Marks", caption = "Mark the step's NPCs",
            help = "A click on the target strip, its Mark all, or a mark key gives each of the step's creatures its own raid marker." },
        { path = "automation.acceptQuests", kind = "toggle", label = "Accept", caption = "Accept the step's quests",
            help = "Accepts only the quests the current step asks for." },
        { path = "automation.turnInQuests", kind = "toggle", label = "Turn in", caption = "Turn in the step's quests",
            help = "Hands in the step's finished quests; a choice of rewards is left to you." },
        { path = "automation.selectQuestInLog", kind = "toggle", label = "Quest log", caption = "Select the step's quest",
            help = "Opening the quest log lands on the step's quest, once per step." },
        { path = "automation.sellJunk", kind = "toggle", label = "Junk", caption = "Sell junk at vendors",
            help = "Sells grey items only; they can be bought back from the vendor." },
        { path = "automation.lootReminder", kind = "toggle", label = "Loot", caption = "Remind me to loot quest drops",
            help = "After a fight, names the item still on a boss or named creature the guide wants it from." },
    }, foot = "Hold Shift when talking to an NPC or opening a vendor to handle the whole visit yourself. Kills of a"
        .. " step's targets are counted from the combat log." },
    { title = "Beside the tracker", rows = {
        { path = "npcPanel.shown", kind = "toggle", label = "Target strip", caption = "Show the step's targets",
            help = "Portraits of the step's creatures; a click targets and marks one. Keys under Key Bindings, AddOns, NuuRoad." },
        { path = "npcPanel.inViewOnly", kind = "toggle", label = "Targets in view", caption = "Only creatures in view",
            help = "Only creatures you have targeted, moused over, or can see a nameplate on." },
        { path = "itemPanel.shown", kind = "toggle", label = "Item strip", caption = "Show the step's items",
            help = "The step's usable items you carry; a click or a bound key uses one." },
        { path = "materials.shown", kind = "toggle", label = "Materials", caption = "Show the guide's materials list",
            help = "What the steps ahead ask you to bring, and what is still missing from your bags." },
    } },
    -- Three answers no API can give, which guides branch on. They stay
    -- unanswered until the player says, and a guide reading an unanswered
    -- question treats it as unknown, so nothing is hidden by silence.
    { title = "About your realm", hint = "some guides branch on these", rows = {
        { path = "realm.xpRate", kind = "rate", label = "Experience rate",
            help = "Times experience: 1 for a normal realm. Leave it empty and the steps that depend on it are all shown." },
        { path = "realm.auctionHouse", kind = "toggle", label = "Auction house", caption = "I use the auction house",
            help = "Some steps buy a component rather than farm it. Off leaves those steps out." },
        { path = "realm.selfFound", kind = "toggle", label = "Self found", caption = "I am playing self found",
            help = "Steps that assume trading or the auction house are left out, and the long way round is shown instead." },
    } },
    -- Recording is its own block rather than an NPC convenience: it changes
    -- nothing in the world and acts on nothing, it only writes down what the
    -- player did so a session can be turned into a guide afterwards.
    { title = "Recording", rows = {
        { path = "recording.enabled", kind = "toggle", label = "Session log", caption = "Record what I do",
            help = "Logs quests, loot, NPCs, flights and zones with where you stood, for turning into a guide." },
        { path = "recording.keepDays", kind = "number", label = "Keep records", min = 1, max = 365, prune = true,
            help = "Days a record stays in the log. Older ones are dropped at every login, or now with Clean up." },
    }, foot = "Menu, Authoring, Session log shows what has been recorded so far. Nothing is sent anywhere." },
    { title = "Authoring", rows = {
        { path = "debug", kind = "toggle", label = "Debug log", caption = "Keep a debug log",
            help = "Reports guide data the game contradicts, shows IDs in tooltips, and lists the fixture guides."
                .. " Findings are kept in the saved variables; /nuuroad log lists every one." },
        { path = "placeRecorder.outdoors", kind = "toggle", label = "Place recorder", caption = "Keep outdoor samples",
            help = "The place recorder's walk keeps samples taken outdoors too, not only inside." },
    } },
}

-- A row's default in words, for its reset's tooltip.
local function defaultText(spec)
    local value = Options:DefaultValue(spec.path)
    if spec.path:match("^realm%.") then return "unanswered" end
    if spec.kind == "toggle" then return value and "on" or "off" end
    if spec.kind == "slider" and spec.format then return string.format(spec.format, value or 0) end
    if spec.kind == "number" then return tostring(value) .. " days" end
    return tostring(value)
end

-- Committed only as a positive number, or empty for no answer.
local function validateRate(text)
    if text:match("^%s*$") then return nil end
    local value = tonumber(text)
    if value and value > 0 then return nil end
    return "A number above 0, such as 1 or 1.5; empty for no answer."
end

function Options:Status(text, tone)
    if self.win then self.win:Status(text, tone and { tone = tone } or nil) end
end

-- Old records out of the log now, as the login does.
function Options:Prune()
    local recorder = ns.recorder
    if not recorder then return 0 end
    local dropped = recorder:Prune()
    self:Status("Session log: dropped " .. dropped .. " record" .. (dropped == 1 and "" or "s") .. " older than "
        .. recorder:KeepDays() .. " days.", "text")
    local panel = ns.modules.RecordingPanel
    if panel and panel.Refresh then panel:Refresh() end
    return dropped
end

local function buildRow(self, box, spec)
    local row = { spec = spec }
    local setting = box:Setting{ spec.label, help = spec.help, labelWidth = LABEL_WIDTH, default = defaultText(spec) }
    local bind, default = self:Bind(spec.path), self:DefaultValue(spec.path)
    local control
    if spec.kind == "toggle" then
        control = setting:Toggle{ spec.caption, bind = bind, default = default }
    elseif spec.kind == "slider" then
        control = setting:Slider{ min = spec.min, max = spec.max, step = spec.step, format = spec.format, width = 200,
            bind = bind, default = default }
    elseif spec.kind == "number" then
        control = setting:NumberInput{ min = spec.min, max = spec.max, bind = bind, default = default }
    elseif spec.kind == "rate" then
        control = setting:Input{ width = 80, placeholder = "1", validate = validateRate, bind = bind }
    end
    if spec.prune then
        setting:Button{ "Clean up", tooltip = "Drop every record older than that now. It also happens at every login.",
            onClick = function() self:Prune() end }
    end
    row.setting, row.control = setting, control
    return row
end

function Options:Build()
    if self.win then return self.win end
    local UI = ns:GetUI()
    local win = UI:Window({
        key = "options", title = "NuuRoad options", width = 660, height = 700, place = ns.db and ns.db.windows,
        resizable = true, minWidth = 560, minHeight = 360, hidden = true,
        status = "A setting is saved once you change it; the reset beside it goes back to the default.",
    })
    self.win = win
    local body = win:Column{ gap = 10, padding = 12 }
    local area = body:ScrollArea{ grow = true, gap = 16, padding = 4 }
    self.area = area
    self.rows = {}
    for _, section in ipairs(SECTIONS) do
        local box = area:Section{ section.title, hint = section.hint, gap = 0 }
        for _, spec in ipairs(section.rows) do table.insert(self.rows, buildRow(self, box, spec)) end
        if section.foot then box:Text{ section.foot, style = "label", wrap = true } end
    end

    -- Where the windows stand: set by dragging them, so a reset is the only
    -- control here.
    local windows = area:Section{ "Windows", gap = 8 }
    windows:Text{ "Where the tracker, the arrow, the strips, these windows and the minimap button stand, and how big"
        .. " they are. Drag a window by its title to move it.", style = "label", wrap = true }
    windows:Button{ "Reset window positions", tooltip = "Forgets where every window stands; each opens where it"
        .. " started the next time it is made (after /reload for the ones already open).",
        onClick = function() self:ResetWindows() end }

    -- The look is the addon's own, kept in NuuRoadDB.look.
    local looks = area:Section{ "Appearance", hint = "every NuuRoad window's theme, accent, opacity and text" }
    looks:LookPicker{ look = ns.db and ns.db.look, onChange = function(look) self:SetLook(look) end }

    local foot = body:Row{ gap = 8, align = "right" }
    foot:ConfirmButton{ "Reset all", tooltip = "Every setting on this page back to its default, window places"
        .. " included. What you chose is forgotten. Click twice to confirm.", onConfirm = function() self:ResetAll() end }
    foot:Button{ "Done", tone = "accent", onClick = function() win:Hide() end }
    return win
end

-- Every control shown again from the settings: on opening, and when a
-- setting changes while the window is open.
function Options:SyncRow(row)
    local control, path = row.control, row.spec.path
    if control then
        local value = store[path]
        if value == nil then value = self:DefaultValue(path) end
        if row.spec.kind == "rate" then
            if not control:HasFocus() then control:SetValue(value or "") end
        elseif row.spec.kind == "number" then
            if not control:HasFocus() then control:SetValue(value) end
        else
            control:SetValue(value)
        end
    end
    row.setting:Refresh()
end

function Options:Sync()
    for _, row in ipairs(self.rows or {}) do self:SyncRow(row) end
end

-- Config:Changed: the rows showing `path` (or a setting inside it, or the
-- group it is in) follow it.
function Options:OnSettingChanged(path)
    if not (self.win and self.win:IsShown()) then return end
    for _, row in ipairs(self.rows) do
        local own = row.spec.path
        if own == path or own:sub(1, #path + 1) == path .. "." or path:sub(1, #own + 1) == own .. "." then
            self:SyncRow(row)
        end
    end
end

-- Forgets where every window stands (the kit's places, NuuRoadDB.windows)
-- and the minimap button's angle.
function Options:ResetWindows()
    local places = ns.db and ns.db.windows
    if places then
        for key in pairs(places) do places[key] = nil end
    end
    Config():Reset("minimap.angle")
    self:Status("Window places forgotten. Each window opens where it started the next time it is made.", "text")
end

-- Every row back to its default, and the window places.
function Options:ResetAll()
    for _, row in ipairs(self.rows or {}) do
        if row.control then row.control:Reset() end
    end
    self:ResetWindows()
    self:Sync()
    self:Status("Every setting back to its default.", "text")
end

function Options:SetLook(look)
    if ns.db then ns.db.look = look end
    ns:GetUI():SetLook(look)
end

function Options:Show()
    local win = self:Build()
    self:Sync()
    win:Show()
end

function Options:Hide()
    if self.win then self.win:Hide() end
end

function Options:Toggle()
    if self.win and self.win:IsShown() then self.win:Hide() else self:Show() end
end

function Options:IsShown()
    return self.win ~= nil and self.win:IsShown()
end

-- OpenRoad's names for the same, kept for callers ported from there.
Options.ToggleOptions = Options.Toggle
Options.SyncOptions = Options.Sync
Options.RefreshOptionLabels = Options.Sync

-- Diagnostics ------------------------------------------------------------------------------

-- The client build and the API report, in the kit's diagnostics window: it
-- is read once and put away.
function Options:BuildDiagnostics()
    if self.diagnostics then return self.diagnostics end
    self.diagnostics = ns:GetUI():DiagnosticsWindow({ key = "diagnostics", place = ns.db and ns.db.windows,
        lines = function() return ns.modules.Client:GetDiagnosticLines() end })
    return self.diagnostics
end

function Options:ShowDiagnostics()
    self:BuildDiagnostics():Show()
end

function Options:ToggleDiagnostics()
    self:BuildDiagnostics():Toggle()
end

ns:RegisterModule("Options", Options)
