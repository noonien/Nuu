local _, ns = ...

-- Where the game marks the quests in the log, kept when the guides do not
-- have the place or have it somewhere else, so they can be filled in and
-- corrected afterwards. The game marks each quest in the log at one point
-- (C_QuestLog.GetQuestsOnMap): the objective area while objectives are left,
-- the turn-in NPC once the quest is ready (docs/api-compatibility.md, "Quest
-- points on the map"). Each mark is judged against every place any packaged
-- or saved guide puts that quest, for the same role:
--
--   unguided  no guide names the quest at all
--   missing   guides name it, but none places this role (no objective step
--             with a spot, no turn-in step with one)
--   differs   the nearest place a guide gives for this role is further than
--             the role's limit, or on another continent
--
-- A mark that agrees is not written. A row goes on the session log's `marks`
-- channel once per quest and role a session, and again when the mark moves;
-- `Tools/SessionLog/sessions.py --marks` gathers them across sessions, with
-- the point in the guides' own units to paste.
--
-- It reads the log, never acts, and writes only the session log.
local QuestMarks = { written = {} }

-- An objective mark is the middle of an area the guides may split into
-- several spots, so a guide spot within this distance is the same area.
QuestMarks.objectiveYards = 300
-- A turn-in mark is the NPC, to within a few yards; the same limit as
-- GuideCorrections, past which the arrow would be visibly wrong.
QuestMarks.turninYards = 60
-- A mark written this session is written again only once it has moved this far.
QuestMarks.movedYards = 50
-- Seconds between two looks at the log; quest log updates come in bursts.
QuestMarks.interval = 10

-- The guide roles a mark of each kind stands for.
local rolesFor = {
    objective = { objective = true, collect = true, step = true },
    turnin = { turnin = true },
}

local function now() return GetTime and GetTime() or 0 end

local function rounded(value) return math.floor(value * 10000 + 0.5) end

-- What the guides say about one mark: its status and the nearest guide place
-- of the role, or nil when they agree.
function QuestMarks:Judge(questID, role, mapID, x, y)
    local POILog, QuestIndex = ns.modules.POILog, ns.modules.QuestIndex
    if not POILog or not QuestIndex then return nil end
    if #QuestIndex:GuidesFor(questID) == 0 then return "unguided" end
    local spots = {}
    for _, spot in ipairs(POILog:AuthoredSpots(questID)) do
        if rolesFor[role][spot.role] then spots[#spots + 1] = spot end
    end
    if #spots == 0 then return "missing" end
    local gap, nearest = POILog:NearestSpot(spots, mapID, x, y)
    local limit = role == "turnin" and self.turninYards or self.objectiveYards
    if gap and gap <= limit then return nil end
    return "differs", gap, nearest or spots[1]
end

-- One quest in the log: its mark, judged, written when it says something new.
function QuestMarks:Check(questID, title)
    local Client, Navigation, POILog = ns.modules.Client, ns.modules.Navigation, ns.modules.POILog
    if not Client or not Navigation or not POILog then return nil end
    local mapID, x, y = Navigation:QuestMarker(questID)
    if not mapID then return nil end
    local role = Client:IsQuestReadyToTurnIn(questID) == true and "turnin" or "objective"
    local status, gap, spot = self:Judge(questID, role, mapID, x, y)
    if not status then return nil end
    local key = questID .. "#" .. role
    local last = self.written[key]
    if last then
        local moved = POILog:GapYards(last.mapID, last.x, last.y, mapID, x, y)
        if moved and moved < self.movedYards then return nil end
    end
    self.written[key] = { mapID = mapID, x = x, y = y }
    local row = {
        event = "mark", quest = questID, role = role, status = status,
        title = title or Client:GetQuestTitle(questID),
        map = mapID, x = rounded(x), y = rounded(y),
        gap = gap and math.floor(gap + 0.5) or nil,
    }
    if spot then
        row.guide, row.step = spot.guide, spot.step
        row.guideMap, row.guideX, row.guideY = spot.mapID, rounded(spot.x), rounded(spot.y)
    end
    if ns.Record then ns:Record("marks", row) end
    return row
end

-- Every quest in the log, at most once per interval.
function QuestMarks:Scan(force)
    local Client = ns.modules.Client
    if not Client then return end
    local at = now()
    if not force and self.lastScan and at - self.lastScan < self.interval then return self:Later() end
    self.lastScan = at
    for _, entry in ipairs(Client:GetQuestLogEntries()) do self:Check(entry.questID, entry.title) end
end

-- A look scheduled for when the interval is up, so the last update of a
-- burst is not lost.
function QuestMarks:Later()
    if self.pending or type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    self.pending = true
    C_Timer.After(self.interval, function()
        self.pending = nil
        self:Scan(true)
    end)
end

function QuestMarks:Initialize()
    self.written = {}
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function() self:Scan() end)
    self.frame = frame
end

ns:RegisterModule("QuestMarks", QuestMarks)
