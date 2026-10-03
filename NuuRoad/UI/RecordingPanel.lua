local _, ns = ...

-- What this session recorded: the kit's session log window
-- (ui:SessionLogWindow, NuuKit/UI/Screens/SessionLog.lua) on ns.recorder's
-- `rec` channel. What is NuuRoad's own is here: how a row reads
-- (Domain/Recording:Describe), the mark each kind wears, and the two
-- settings the window changes, recording on or off (through
-- Domain/Recording, so the log says when it started or stopped) and the days
-- the log keeps, bound through the options like the options' own rows.
local RecordingPanel = {}

-- A mark for each recorded kind, and what it means at a glance: something
-- gained green, something lost red, a quest picked up in the accent, and the
-- everyday rest muted so the few that matter stand out of a long list.
local GLYPHS = {
    accept = "!", turnin = "?", abandon = "-", objective = "x", talk = "?!", kill = "x", loot = "o",
    craft = "C", train = "T", buy = "$", sell = "$", repair = "$", flightpath = "F", flight = "F",
    flightend = "F", hearthset = "H", hearth = "H", use = "*", equip = "E",
    level = "L", death = "X", alive = "v", recording = "~", door = ">", questlog = "Q",
}
local TONES = {
    accept = "accent", turnin = "done", level = "done", alive = "done",
    abandon = "danger", death = "danger", recording = "warning",
}
local MARKS = {}
for kind, glyph in pairs(GLYPHS) do MARKS[kind] = { glyph = glyph, tone = TONES[kind] or "muted" } end

local RECORDED = "Quests taken, moved on and handed in, quest loot, kills, NPCs you talk to, vendors, trainers,"
    .. " flights, hearths, levels and deaths, each with where you stood. Nothing is sent anywhere."

local function recording() return ns.modules.Recording end

function RecordingPanel:Enabled()
    local Recording = recording()
    return Recording ~= nil and Recording:Enabled() == true
end

function RecordingPanel:Build()
    if self.log then return self.log end
    local Options, Config = ns.modules.Options, ns.modules.Config
    self.log = ns:GetUI():SessionLogWindow({
        key = "sessionLog", place = ns.db and ns.db.windows, recorder = ns.recorder, channel = "rec",
        describe = function(row)
            local Recording = recording()
            return Recording and Recording:Describe(row) or nil
        end,
        marks = MARKS,
        switch = { "Record what I do", bind = Options and Options:Bind("recording.enabled"),
            default = Config and Config:Default("recording.enabled"),
            tooltip = "Logs what you do this session as material for a guide. Nothing here is sent anywhere." },
        enabled = function() return self:Enabled() end,
        keepDays = { bind = Options and Options:Bind("recording.keepDays"),
            default = Config and Config:Default("recording.keepDays") },
        recorded = RECORDED,
        offHint = "Recording is off. Turn it on to log quests, loot, and where you were.",
        empty = "Nothing recorded this session.",
    })
    self.win = self.log.win
    -- A new row repaints the list while it is open.
    local Recording = recording()
    if Recording and type(Recording.OnChange) == "function" then
        Recording:OnChange(function() self:Refresh() end)
    end
    return self.log
end

function RecordingPanel:Entries()
    return self:Build():Entries()
end

function RecordingPanel:Refresh()
    if self.log then self.log:Refresh() end
end

function RecordingPanel:Prune()
    return self:Build():Prune()
end

function RecordingPanel:Clear()
    return self:Build():Clear()
end

-- The switch and the days follow a change made in the options.
function RecordingPanel:OnSettingChanged(path)
    if path == "recording" or path:sub(1, 10) == "recording." then self:Refresh() end
end

function RecordingPanel:Show()
    self:Build():Show()
end

function RecordingPanel:Hide()
    if self.log then self.log:Hide() end
end

function RecordingPanel:Toggle()
    self:Build():Toggle()
end

ns:RegisterModule("RecordingPanel", RecordingPanel)
