local _, ns = ...

-- Where a guide's coordinate disagrees with the game, and what to do about it.
--
-- The packaged guides are ports; a ported coordinate can be wrong, and the POI
-- log has caught turn-in steps two thousand yards from where the quest was
-- actually handed in. Two sources say where a place really is:
--
--   * an observation - the player's own position when the game confirmed a
--     quest accepted or handed in. Nobody's opinion, and exact.
--   * the client's own pin, which on this build names the turn-in NPC to
--     within a couple of yards once a quest is ready to hand in.
--
-- A creature that walks a route has no single position: a sighting of one is
-- a moment on its round. Sightings are gathered per creature (every dialog is
-- one, not only quest events, since plenty of NPCs give a single quest), and
-- where they are spread out the middle of them is used and the step is given
-- a radius wide enough to hold the route.
--
-- Only quest-giver positions are judged this way. An objective step is not
-- comparable: a quest's mobs spawn in several places, the client gives one
-- point for all of them, and the place the player happened to work is not
-- necessarily the place the guide should send the next one. Those
-- disagreements are reported and never acted on.
--
-- Corrections live for the session and touch nothing on disk. They are applied
-- to packaged guides only, because those are rebuilt from `Data/Guides` at
-- every login, so a corrected coordinate cannot outlive the session even by
-- accident. A user guide is copied wholesale into SavedVariables when the
-- editor saves it, so correcting one in memory could reach the disk; those are
-- reported and left alone.
local Corrections = { findings = {}, applying = false }

-- Yards a coordinate has to be out before it is worth saying anything. The
-- arrow calls the player arrived within a few dozen yards, so a smaller
-- disagreement changes nothing anyone can see.
Corrections.threshold = 60

-- The roles worth judging: both are a person standing in one place.
local judged = { accept = true, turnin = true }

function Corrections:Findings()
    return self.findings
end

function Corrections:Clear()
    self.findings = {}
end

function Corrections:SetApplying(value)
    self.applying = value and true or false
    return self.applying
end

-- The best evidence for where a quest's giver or turn-in really is, and how it
-- was arrived at. An observation outranks a pin: it is where the player stood
-- when the game itself confirmed the thing happened.
function Corrections:Evidence(questID, role)
    local POILog, Client = ns.modules.POILog, ns.modules.Client
    if not POILog or not Client or not judged[role] then return nil end
    for _, entry in ipairs(POILog:Observations(questID)) do
        if entry.kind == role and entry.map and entry.x and entry.y then
            -- Some creatures walk a route. One sighting of such a creature is
            -- a moment on that route, not its place, so where several
            -- sightings exist and they are spread out, the middle of them is
            -- the fairest single point and the spread is what the step's
            -- arrival radius has to cover.
            local sighted = entry.npc and POILog:NPCSighting(entry.npc)
            if sighted and sighted.roams and sighted.middle and #sighted.places > 1 then
                return { mapID = sighted.middle.map, x = sighted.middle.x / 100, y = sighted.middle.y / 100,
                    source = "observed", roams = sighted.spread, sightings = #sighted.places,
                    npc = entry.npc, npcName = sighted.name, at = entry.at }
            end
            return { mapID = entry.map, x = entry.x / 100, y = entry.y / 100, source = "observed", at = entry.at,
                npc = entry.npc, npcName = entry.npcName }
        end
    end
    -- The pin is only the turn-in NPC while the quest is ready to hand in;
    -- at any other time it is the objective marker, which is not this.
    if role == "turnin" and Client:IsQuestReadyToTurnIn(questID) then
        local placed = POILog:PlaceQuest(questID, {})
        if placed then return { mapID = placed.mapID, x = placed.x, y = placed.y, source = "pin" } end
    end
    return nil
end

local function distance(POILog, location, evidence)
    return POILog:GapYards(location.mapID, location.x, location.y, evidence.mapID, evidence.x, evidence.y)
end

-- Judges one step against the evidence. Returns the finding, whether or not it
-- was applied, or nil when the step and the game agree.
function Corrections:Consider(guide, node, questID, role)
    local POILog, Client = ns.modules.POILog, ns.modules.Client
    if not POILog or not Client or not guide or not node or not judged[role] then return nil end
    local location = node.location
    if not location or type(location.x) ~= "number" then return nil end
    local evidence = self:Evidence(questID, role)
    if not evidence then return nil end
    local mapID = Client:ResolveMapID(location.mapID)
    local gap = distance(POILog, { mapID = mapID, x = location.x, y = location.y }, evidence)
    local wrongMap = mapID ~= evidence.mapID
    if not wrongMap and (not gap or gap < self.threshold) then return nil end

    local key = tostring(guide.id) .. "#" .. tostring(node.index) .. "#" .. tostring(questID)
    local existing
    for _, finding in ipairs(self.findings) do
        if finding.key == key then existing = finding break end
    end
    local finding = existing or { key = key, guide = guide.id, step = node.index, quest = questID, role = role }
    finding.title = ns.modules.Steps and ns.modules.Steps:Title(node) or finding.title
    finding.from = finding.from or { mapID = mapID, x = location.x, y = location.y }
    finding.to = { mapID = evidence.mapID, x = evidence.x, y = evidence.y }
    finding.gap = gap and math.floor(gap + 0.5) or nil
    finding.wrongMap = wrongMap
    finding.source = evidence.source
    finding.roams, finding.sightings = evidence.roams, evidence.sightings
    finding.npc, finding.npcName = evidence.npc, evidence.npcName
    -- The step goes where the guide's `names.npcs` says this NPC stands, so
    -- that entry is the one to correct.
    finding.stands = location.npc
    finding.seen = (finding.seen or 0) + 1
    -- A step pointed at a creature that walks cannot be a point the player is
    -- expected to land on; the radius has to hold the route.
    if evidence.roams then
        finding.suggestedRadius = math.max(math.floor(evidence.roams / 2 + 0.5), 20)
    end
    if not existing then table.insert(self.findings, finding) end

    local builtIn = ns.modules.GuideRepository and ns.modules.GuideRepository:IsBuiltIn(guide.id)
    if not builtIn then
        -- A user guide is copied into SavedVariables when the editor saves it,
        -- so a corrected coordinate could outlive the session. Say so instead.
        finding.skipped = "user guide: editing it would persist the change"
    elseif self.applying and not finding.applied then
        location.mapID, location.x, location.y = evidence.mapID, evidence.x, evidence.y
        -- Kept so the report can show what was there and so nothing mistakes a
        -- corrected coordinate for an authored one.
        location.correctedFrom = finding.from
        location.correctedBy = evidence.source
        if finding.suggestedRadius then
            location.correctedRadiusFrom = location.arrivalYards
            location.arrivalYards = finding.suggestedRadius
        end
        finding.applied = true
        ns:Log(string.format("guide correction: %s step %s moved %s yd to the %s position (%s)",
            tostring(guide.id), tostring(node.index), tostring(finding.gap), role, evidence.source))
        local Navigation = ns.modules.Navigation
        if Navigation and Navigation.Retarget then Navigation:Retarget() end
    end
    return finding
end

-- What a quest-giver or turn-in step leaves out that the game has just shown:
-- no NPC named, an NPC other than the one the player was facing, or no spot.
-- Nothing is changed. The gap goes on the session log's `discover` channel,
-- with what the game said and the authored form to paste, so the guide can be
-- filled in afterwards (`sessions.py --channel discover`). Once per step and
-- role a session: the log outlives it, and one row says it.
function Corrections:Discover(guide, node, questID, role)
    if not guide or not node or not judged[role] then return nil end
    local evidence = self:Evidence(questID, role)
    if not evidence then return nil end
    local key = tostring(guide.id) .. "#" .. tostring(node.index) .. "#" .. tostring(questID) .. "#" .. role
    self.discovered = self.discovered or {}
    if self.discovered[key] then return nil end
    local missing, row = {}, { event = "gap", guide = guide.id, step = node.index, quest = questID, role = role }
    local named = node.refs and node.refs.npcs or {}
    if evidence.npc then
        local found = false
        for _, id in ipairs(named) do if id == evidence.npc then found = true end end
        if #named == 0 then
            table.insert(missing, "npc")
        elseif not found then
            table.insert(missing, "other npc")
            row.authoredNPCs = named
        end
        row.npc, row.npcName = evidence.npc, evidence.npcName
    end
    local location = node.location
    local placed = location and type(location.x) == "number"
    if not placed then table.insert(missing, "at") end
    if #missing == 0 then return nil end
    self.discovered[key] = true
    row.missing = table.concat(missing, ", ")
    row.map = evidence.mapID
    row.x, row.y = math.floor(evidence.x * 10000 + 0.5) / 100, math.floor(evidence.y * 10000 + 0.5) / 100
    row.source = evidence.source
    row.title = ns.modules.Steps and ns.modules.Steps:Title(node) or nil
    local parts = {}
    if evidence.npc then table.insert(parts, "npc = " .. evidence.npc) end
    if not placed then table.insert(parts, string.format("at = { %.2f, %.2f }, map = %s", row.x, row.y, tostring(row.map))) end
    row.authored = table.concat(parts, ", ")
    ns:Record("discover", row)
    ns:Log(string.format("discover: %s step %s (%s quest %d) is missing %s", tostring(guide.id),
        tostring(node.index), role, questID, row.missing))
    return row
end

-- Every step of every guide that names a quest, judged at once. Called when the
-- game confirms something about that quest, so a correction lands on the step
-- ahead of the player as well as the one under them.
function Corrections:ConsiderQuest(questID)
    local QuestIndex = ns.modules.QuestIndex
    if not QuestIndex or type(questID) ~= "number" then return end
    for _, entry in ipairs(QuestIndex:GuidesFor(questID)) do
        for _, step in ipairs(entry.steps or {}) do
            if judged[step.role] then
                local node = entry.guide.nodes and entry.guide.nodes[step.index]
                if node then
                    self:Discover(entry.guide, node, questID, step.role)
                    self:Consider(entry.guide, node, questID, step.role)
                end
            end
        end
    end
end

-- What disagreed, what was done about it, and what the corrected coordinate
-- would be - in a form that can be pasted back into a guide file.
function Corrections:ReportLines()
    local lines = {
        "Guide coordinates that disagree with the game, for quest-giver and turn-in steps only.",
        "Evidence is the player's own position when the game confirmed the thing (observed), or the client's",
        "pin while the quest was ready to hand in (pin). Objective steps are never judged this way: a quest's",
        "mobs spawn in several places and one point cannot stand for the route.",
        "",
        "Applying corrections is " .. (self.applying and "ON" or "OFF") .. " (/nuuroad poi correct toggles it).",
        "Corrections live for this session only. They are applied to packaged guides, which are rebuilt from",
        "Data/Guides at every login; a user guide is left alone because the editor would write it to disk.",
        "",
        "Disagreements: " .. #self.findings,
    }
    for _, finding in ipairs(self.findings) do
        table.insert(lines, "")
        table.insert(lines, string.format("%s step %s (%s) quest %d: %s", tostring(finding.guide), tostring(finding.step),
            tostring(finding.role), finding.quest, tostring(finding.title)))
        table.insert(lines, string.format("  guide says  map %s %.1f, %.1f", tostring(finding.from.mapID),
            finding.from.x * 100, finding.from.y * 100))
        table.insert(lines, string.format("  game says   map %s %.1f, %.1f  (%s)", tostring(finding.to.mapID),
            finding.to.x * 100, finding.to.y * 100, tostring(finding.source)))
        if finding.roams then
            table.insert(lines, string.format("  %s walks a route: %d sighting(s) spread over %s yd, so this is their middle",
                tostring(finding.npcName or ("creature " .. tostring(finding.npc))), finding.sightings or 0, tostring(finding.roams)))
            table.insert(lines, string.format("  a step pointed at them wants radius = %d rather than a spot", finding.suggestedRadius))
        end
        table.insert(lines, string.format("  out by %s%s; seen %d time(s); %s",
            finding.wrongMap and "another map" or ((tostring(finding.gap)) .. " yd"),
            finding.wrongMap and "" or "", finding.seen or 1,
            finding.applied and "APPLIED for this session" or (finding.skipped or "not applied")))
        -- The authored form, ready to paste: coordinates are map percentages.
        -- A step that takes its point from the NPC is corrected in names.npcs;
        -- a radius still belongs on the step.
        if finding.stands then
            table.insert(lines, string.format("  authored form: names.npcs[%d] at = { %.1f, %.1f%s }%s", finding.stands,
                finding.to.x * 100, finding.to.y * 100,
                finding.wrongMap and string.format(", map = %s", tostring(finding.to.mapID)) or "",
                finding.suggestedRadius and string.format("; on the step, radius = %d", finding.suggestedRadius) or ""))
        else
            table.insert(lines, string.format("  authored form: at = { %.1f, %.1f }%s%s", finding.to.x * 100, finding.to.y * 100,
                finding.wrongMap and string.format(", map = %s", tostring(finding.to.mapID)) or "",
                finding.suggestedRadius and string.format(", radius = %d", finding.suggestedRadius) or ""))
        end
    end
    return lines
end

function Corrections:Initialize()
    -- Session only, like the POI log it draws on.
    self:Clear()
    self.applying = false
    self.discovered = {}
end

ns:RegisterModule("GuideCorrections", Corrections)
