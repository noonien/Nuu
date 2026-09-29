local _, ns = ...

-- Follows the creatures of the current quest group: the current step and the
-- remaining members of its authored group (Progress:QuestGroup). Kill
-- targets and quest NPCs get a raid marker when the player targets them,
-- mouses over them, or sees their nameplate (skull, cross, and so on for
-- targets to fight, then the star and the rest for NPCs to talk to). No two
-- creatures of one group share an icon, so a hub of quest givers can be told
-- apart at a glance. Kills of the step's targets
-- are counted from the combat log, and a dialog with one of its NPCs is
-- recorded, so the tracker can show both.
--
-- A turn-in whose quest the player does not have and never finished is not
-- a member of the group at all (Progress:QuestGroup), so its NPC only joins
-- once the quest is in the log. The step the guide is on can still be such a
-- turn-in for a moment; its NPC is then not live, gets no marker, and the
-- panel leaves it out.
--
-- It never selects a target, attacks, or moves. Marks are only put on
-- unmarked units and only cleared again when this module set them.
local NPCTracking = { marked = {}, markedCount = 0, recentKills = {}, targets = {}, order = {}, nodes = {},
    -- The last marker the client let us read off each of the step's
    -- creatures, id -> icon, so a marker outlives the creature leaving
    -- view. A marker the player put on or took off by hand lands here
    -- like any other: what is reported is what is on the mob, never
    -- what the addon wanted to put there.
    observed = {}, hidden = {}, carries = {}, combatLeftAt = -math.huge }

local killMarkers = { 8, 7, 6, 5, 4, 3, 2 } -- skull first, then cross, square, moon, triangle, diamond, circle
-- Quest givers take the star first, then whatever the kill targets have not
-- taken. A hub can put five givers in front of the player at once, and five
-- stars tell them apart no better than none would; the star still goes to
-- the first, so a lone giver is marked the way it always was.
local talkMarkers = { 1, 2, 3, 4, 5, 6, 7, 8 } -- star, circle, diamond, triangle, moon, square, cross, skull
local markerNames = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }
local dialogEvents = {
    GOSSIP_SHOW = true, QUEST_GREETING = true, QUEST_DETAIL = true, QUEST_PROGRESS = true, QUEST_COMPLETE = true,
    MERCHANT_SHOW = true, TAXIMAP_OPENED = true, TRAINER_SHOW = true, BANKFRAME_OPENED = true,
}
local KILL_MEMORY = 30 -- seconds a kill's GUID is remembered so one death is never counted twice
local COMBAT_GRACE = 3 -- seconds after leaving combat during which a target's death still counts
local MARK_MEMORY = 200 -- marked GUIDs kept before the memory is emptied

local function now() return GetTime and GetTime() or 0 end

function NPCTracking:Enabled(key)
    return ns.modules.Config:Get("automation." .. key) == true
end

local function prepareMarkKey()
    local TargetMarking = ns.modules.TargetMarking
    if TargetMarking and TargetMarking.Prepare then TargetMarking:Prepare() end
end

-- Which creature IDs matter for the group `nodes`, with the marker each one
-- gets and the steps that name it. `order` keeps them in guide order, kill
-- targets first, for the NPC panel. `node` stays the first step. A kill
-- counts for every member naming the creature, so a group of kill steps in
-- one camp keeps a count per step.
function NPCTracking:Refresh(nodes)
    if nodes and nodes.kind then nodes = { nodes } end
    nodes = nodes or {}
    self.nodes = nodes
    self.node = nodes[1]
    self.targets = {}
    self.order = {}
    local killOrder, talkOrder = {}, {}
    for _, node in ipairs(nodes) do
        local kill, talk = ns.modules.Steps:NPCs(node)
        for _, id in ipairs(kill) do
            if not self.targets[id] then
                self.targets[id] = { kind = "kill", nodes = { node } }
                table.insert(self.order, id)
                table.insert(killOrder, id)
            elseif self.targets[id].kind == "kill" then
                table.insert(self.targets[id].nodes, node)
            end
        end
        for _, id in ipairs(talk) do
            local target = self.targets[id]
            if not target then
                self.targets[id] = { kind = "talk", nodes = { node } }
                table.insert(self.order, id)
                table.insert(talkOrder, id)
            elseif target.kind == "talk" then
                table.insert(target.nodes, node)
            end
        end
    end
    -- Markers are handed out across the whole group, not per step: the
    -- second creature of the second step is the group's second creature, not
    -- another first one, so no two of them wear the same icon.
    --
    -- A creature that stays in the group keeps the marker it already had.
    -- Handing them out afresh moved every icon up one when a member
    -- finished: the cross target became the skull one while still wearing
    -- the cross, and the strip and the next press disagreed with the mob.
    -- Only creatures new to the group take a marker, the first one free.
    local previous, taken = self.assigned or {}, {}
    self.assigned = {}
    for _, id in ipairs(self.order) do
        local marker = previous[id]
        if marker and not taken[marker] then
            self.targets[id].marker = marker
            self.assigned[id] = marker
            taken[marker] = true
        end
    end
    local function hand(ids, markers)
        for _, id in ipairs(ids) do
            if not self.targets[id].marker then
                local marker = markers[#markers]
                for _, candidate in ipairs(markers) do
                    if not taken[candidate] then marker = candidate; break end
                end
                self.targets[id].marker = marker
                self.assigned[id] = marker
                taken[marker] = true
            end
        end
    end
    hand(killOrder, killMarkers)
    hand(talkOrder, talkMarkers)
    local TargetMarking = ns.modules.TargetMarking
    if TargetMarking and TargetMarking.ForgetAssumedExcept then TargetMarking:ForgetAssumedExcept(self.targets) end
    self:ConsiderVisibleUnits()
    local NPCPanel = ns.modules.NPCPanel
    if NPCPanel and NPCPanel.OnStepChanged then NPCPanel:OnStepChanged() end
end

-- A step of the group is done when the player's progress says so or the
-- game still reports it done (GuideScan, where loaded).
function NPCTracking:NodeDone(node)
    local Progress, GuideScan = ns.modules.Progress, ns.modules.GuideScan
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    if not guide then return false end
    local state = Progress:PeekState(guide)
    if state and Progress:IsDone(state.statuses[node.index]) then return true end
    return GuideScan ~= nil and GuideScan.NodeCompleted ~= nil and GuideScan:NodeCompleted(node) == true
end

-- A talk step is live once there is something to do at its NPC: an accept
-- always is, a turn-in only when one of its quests is in the log. A step
-- already done is not. Returns whether the step is live and, when it is not
-- because the quest is missing, that quest's ID.
function NPCTracking:NodeLive(node)
    if self:NodeDone(node) then return false end
    local auto = node.auto
    if not auto or auto.verb ~= "turnin" then return true end
    local Client = ns.modules.Client
    if not Client or not Client.IsQuestInLog then return true end
    for _, id in ipairs(auto.quests or {}) do
        if Client:IsQuestInLog(id) then return true end
    end
    return false, (auto.quests or {})[1]
end

-- A creature is live while any step naming it is; a kill target while any
-- of its steps is still to do. The second value is the quest a turn-in NPC
-- is waiting on, when that is the only reason it is not live.
function NPCTracking:IsLive(id)
    local target = self.targets[id]
    if not target then return false end
    if target.kind == "kill" then return not self:KillTargetDone(target) end
    local waiting
    for _, node in ipairs(target.nodes) do
        local live, quest = self:NodeLive(node)
        if live then return true end
        waiting = waiting or quest
    end
    return false, waiting
end

-- A kill target is done once every step naming it is, the same test the
-- tracker card uses to drop a member: a group of kill steps in one camp is
-- worked in any order, and a finished kind leaves the strip when its line
-- leaves the card. A plain kill step also counts its own kills.
function NPCTracking:KillTargetDone(target)
    for _, node in ipairs(target.nodes) do
        local observed = node.completion and node.completion.observed
        local needed = observed and observed.type == "kills" and observed.count or nil
        local counted = needed ~= nil and ns.modules.Steps:KillCount(node) >= needed
        if not counted and not self:NodeDone(node) then return false end
    end
    return true
end

-- The group's creatures for display, in order: { id, kind, marker, name,
-- done, live, waiting }. A talk entry is done once every step naming it is
-- (a quest NPC by its quests, any other by its dialog having been opened);
-- a kill entry carries the kill count of the first step naming it, as
-- `kills` and `killsNeeded`. A talk entry that is not live carries no marker.
function NPCTracking:Entries()
    local entries = {}
    if not self.node then return entries end
    local Steps, Names, Progress = ns.modules.Steps, ns.modules.Names, ns.modules.Progress
    for _, id in ipairs(self.order) do
        local target = self.targets[id]
        local entry = { id = id, kind = target.kind, marker = target.marker, markerName = markerNames[target.marker], name = Names:DescribeNPC(id), live = true }
        if target.kind == "kill" then
            local node = target.nodes[1]
            local observed = node.completion and node.completion.observed
            local needed = observed and observed.type == "kills" and observed.count or nil
            local kills = Steps:KillCount(node)
            entry.kills, entry.killsNeeded = kills, needed
            entry.done = self:KillTargetDone(target)
            if entry.done then entry.live, entry.marker, entry.markerName = false, nil, nil end
        else
            entry.done = true
            for _, member in ipairs(target.nodes) do
                local done
                if Progress and Progress.IsQuestVisit and Progress:IsQuestVisit(member) then
                    done = self:NodeDone(member)
                else
                    done = Steps:HasTalkedTo(member, { id })
                end
                if not done then entry.done = false end
            end
            entry.live, entry.waiting = self:IsLive(id)
            if not entry.live then entry.marker, entry.markerName = nil, nil end
        end
        table.insert(entries, entry)
    end
    return entries
end

-- A unit of the current step is in view (targeted, moused over, on a
-- nameplate, or in a dialog): the panel can take its portrait from it.
function NPCTracking:Seen(id, unit)
    local NPCPanel = ns.modules.NPCPanel
    if NPCPanel and NPCPanel.OnUnitSeen then NPCPanel:OnUnitSeen(id, unit) end
end

-- Re-reads the current quest group and refreshes the target set when its
-- membership changed.
function NPCTracking:Sync()
    local Progress = ns.modules.Progress
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    local group = guide and Progress:QuestGroup(guide) or {}
    local changed = #group ~= #self.nodes
    for index, node in ipairs(group) do
        if self.nodes[index] ~= node then changed = true end
    end
    if changed then self:Refresh(group) end
    return group[1], guide
end

-- The marker a creature gets, or nil when it gets none, which includes a
-- quest NPC that is not live yet.
function NPCTracking:MarkerFor(npcID)
    local target = self.targets[npcID]
    if not target or not self:IsLive(npcID) then return nil, target and target.kind or nil end
    return target.marker, target.kind
end

-- The markers this module set itself on creatures of the current step and
-- has not taken off again, as id -> marker, read from the GUIDs it
-- remembers. A mark stays on a creature after it walks out of view, so this
-- keeps its icon on the step line and in the strip instead of flickering
-- with the nameplates. Empty on a client that refuses SetRaidTarget, where
-- every marker comes from the player's own press instead.
function NPCTracking:MarkersWeSet()
    local Client = ns.modules.Client
    local ours = {}
    if not Client or not Client.CreatureIDFromGUID then return ours end
    for guid, marker in pairs(self.marked) do
        local id = Client:CreatureIDFromGUID(guid)
        if id and self.targets[id] then ours[id] = marker end
    end
    return ours
end

-- Everything known to be wearing a marker of a known value: the ones set
-- above, plus any the client let us read off a unit, whoever put them
-- there. For deciding whether a press would toggle a marker off, not for
-- deciding what to draw -- see TargetMarking:MarkersToDraw for that.
function NPCTracking:WornMarkers()
    local worn = self:MarkersWeSet()
    -- A reading off the unit is the better answer where there is one, and on
    -- a client that will not let the addon mark at all it is the only one.
    for id, marker in pairs(self.observed) do
        if self.targets[id] then worn[id] = marker end
    end
    return worn
end

-- The marker the step gave a creature, whether or not it is live. What a
-- press put on stays on, so an icon already recorded must not vanish
-- because the creature's step stopped being live in the meantime.
function NPCTracking:AssignedMarker(npcID)
    local target = self.targets[npcID]
    return target and target.marker or nil
end

-- "skull", "star", ... for the marker an NPC gets, or nil when it gets none.
function NPCTracking:DescribeMarker(npcID)
    local marker = self:MarkerFor(npcID)
    return marker and markerNames[marker] or nil
end

function NPCTracking:Remember(guid, marker)
    if self.markedCount >= MARK_MEMORY then self.marked = {}; self.markedCount = 0 end
    if not self.marked[guid] then self.markedCount = self.markedCount + 1 end
    self.marked[guid] = marker
end

-- Marks a relevant unit that carries no marker yet, and clears a marker this
-- module put on a unit that the current step no longer cares about.
-- `trusted` says the look came from the game announcing a marker change, so
-- a unit reading as bare really is bare.
function NPCTracking:Consider(unit, trusted)
    local Client = ns.modules.Client
    if not Client:UnitExists(unit) then return end
    local guid = Client:GetUnitGUID(unit)
    local id = Client:CreatureIDFromGUID(guid)
    if not id then return end
    local target = self.targets[id]
    if target then self:Seen(id, unit) end
    local existing, known = Client:GetRaidTargetIndex(unit)
    -- Where the number is guarded, the icon the client draws may still be
    -- readable: the marker is one cell of an atlas and the texture
    -- coordinates say which. Not on 1.60.1, where the coordinates are
    -- guarded too -- but this costs one look and works where it works.
    if not known and Client.GetRaidTargetIconFromFrame then
        local drawn = Client:GetRaidTargetIconFromFrame(unit)
        if drawn then existing, known = drawn, true end
    end
    if not known then
        -- A guarded value is itself an answer. An absent marker reads as a
        -- plain nil on this client, so one the client refuses to show means
        -- the creature is wearing something. Naming it is out of reach;
        -- knowing it is there is not, and that is what stops the row
        -- offering "/tm" and toggling the marker straight back off.
        if target then self:Carries(id, true) end
        -- Neither the number nor a frame drawing it: the creature carries
        -- something we cannot name.
        if target and not self.hidden[id] then
            self.hidden[id] = true
            ns:Log("marker on " .. ns.modules.Names:DescribeNPC(id) .. " is hidden by the client (" .. unit .. ")")
        end
        -- What this does NOT do is drop the claim. RAID_TARGET_UPDATE says a
        -- marker somewhere changed, never whose, so marking the second
        -- creature of a hub would unsay the first one's icon and a press on
        -- Mark all would end with nothing claimed at all. An unreadable
        -- value is no evidence against what we know; reading the icon off
        -- the frame is what tells us when the player changed one.
        return
    end
    if target and self.hidden[id] then
        self.hidden[id] = nil
        ns:Log("marker on " .. ns.modules.Names:DescribeNPC(id) .. " is readable again")
    end
    if target then
        self:Carries(id, existing ~= nil)
        self:Observed(id, existing, trusted)
    end
    -- The game says this unit carries nothing, so whatever we remember
    -- putting on it is out of date: the player took it off.
    if trusted and existing == nil and self.marked[guid] then self.marked[guid] = nil end
    if target and self:IsLive(id) and self:Enabled("markTargets") then
        if existing == nil and not Client:UnitIsDead(unit) and Client:CanMarkTargets() and Client:SetRaidTarget(unit, target.marker) then
            self:Remember(guid, target.marker)
            self:MarkChanged()
        end
    elseif self.marked[guid] and existing == self.marked[guid] then
        if Client:CanMarkTargets() then Client:SetRaidTarget(unit, 0) end
        self.marked[guid] = nil
        self:MarkChanged()
    end
end

-- Whether one of the step's creatures is wearing a marker at all, which is
-- knowable even where the marker itself is not. Kept for the session like a
-- reading, since the marker stays on the creature.
function NPCTracking:Carries(id, carrying)
    carrying = carrying and true or nil
    if self.carries[id] == carrying then return end
    self.carries[id] = carrying
    self:MarkChanged()
end

-- The step's creatures known to be wearing a marker, as id -> true, whether
-- or not anything could read which one.
function NPCTracking:CarriedMarkers()
    local carried = {}
    for id in pairs(self.carries) do
        if self.targets[id] then carried[id] = true end
    end
    return carried
end

-- What the client says one of the step's creatures is wearing right now,
-- from a look at a unit of it. Kept so the reading survives the creature
-- leaving view, and believed over what a click of ours assumed: a marker the
-- player changed or took off by hand is the marker that counts. A bare unit
-- is only believed once our own macro has had time to settle, because the
-- client reports the unit unmarked for a moment after driving the targeting.
function NPCTracking:Observed(id, marker, trusted)
    local before = self.observed[id]
    if marker ~= nil then
        if before == marker then return end
        self.observed[id] = marker
    else
        -- A bare reading unsays a marker only when the game said a marker
        -- changed, or when we had read one off this creature before.
        -- Otherwise it is the client's ordinary silence about a mark one of
        -- our own macros set, which the click's own record covers.
        if not trusted and before == nil then return end
        local believed, dropped = true, false
        local TargetMarking = ns.modules.TargetMarking
        if TargetMarking and TargetMarking.NoteBare then believed, dropped = TargetMarking:NoteBare(id) end
        if not believed then return end
        if before == nil and not dropped then return end
        self.observed[id] = nil
    end
    ns:Log("marker read on " .. ns.modules.Names:DescribeNPC(id) .. ": "
        .. tostring(before) .. " -> " .. tostring(marker) .. (trusted and " (marker change)" or ""))
    self:MarkChanged()
end

-- A marker went on or came off one of the step's creatures. The tracker
-- draws it in front of the name and the target strip draws it in the corner
-- of the portrait, so both are asked to repaint; the request is coalesced,
-- so a sweep of nameplates costs one.
function NPCTracking:MarkChanged()
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.RequestRefresh then MainWindow:RequestRefresh() end
end

-- Every unit the client will let us look at right now: what the player has
-- targeted or moused over, and everything wearing a nameplate.
function NPCTracking:UnitsInView()
    local Client = ns.modules.Client
    local units = { "target", "mouseover" }
    for _, unit in ipairs(Client:GetNamePlateUnits()) do table.insert(units, unit) end
    return units
end

-- The markers the step's creatures in view already carry, as id -> marker.
-- The marking macros leave those creatures out: "/tm" toggles, so marking a
-- unit that already carries its marker would take the marker off again.
-- The second table holds the creatures whose marker the client hid from us
-- (see Client:GetRaidTargetIndex); TargetMarking decides what to make of them.
-- The third holds every step creature that is in view at all, marked or not.
function NPCTracking:MarkersInView()
    local Client = ns.modules.Client
    local seen, unknown, visible = {}, {}, {}
    for _, unit in ipairs(self:UnitsInView()) do
        if Client:UnitExists(unit) and not Client:UnitIsDead(unit) then
            local id = Client:GetUnitCreatureID(unit)
            if id and self.targets[id] then
                visible[id] = true
                local existing, known = Client:GetRaidTargetIndex(unit)
                if not known then
                    unknown[id] = true
                elseif existing ~= nil then
                    seen[id] = existing
                end
            end
        end
    end
    return seen, unknown, visible
end

-- The step's creatures that are in view, as id -> true. "Mark all" only
-- offers these: "/targetexact" finds nobody for a creature that is not
-- around, so anything else would claim a marker that was never set.
function NPCTracking:VisibleTargets()
    local _, _, visible = self:MarkersInView()
    return visible
end

function NPCTracking:ConsiderVisibleUnits(trusted)
    self:Consider("target", trusted)
    self:Consider("mouseover", trusted)
    for _, unit in ipairs(ns.modules.Client:GetNamePlateUnits()) do self:Consider(unit, trusted) end
end

-- Config tells every module of a setting changed (Config:Changed); the
-- automation switches are this module's. Turning marking off takes this
-- module's marks off everything in view.
function NPCTracking:OnSettingChanged(path)
    if type(path) ~= "string" or path:sub(1, #"automation.") ~= "automation." then return end
    self:OnSettingsChanged()
end

function NPCTracking:OnSettingsChanged()
    prepareMarkKey()
    if self:Enabled("markTargets") then self:ConsiderVisibleUnits(); return end
    local Client = ns.modules.Client
    for _, unit in ipairs(self:UnitsInView()) do
        local guid = Client:GetUnitGUID(unit)
        local existing, known = Client:GetRaidTargetIndex(unit)
        if guid and known and self.marked[guid] and existing == self.marked[guid] and Client:CanMarkTargets() then
            Client:SetRaidTarget(unit, 0)
            self.marked[guid] = nil
        end
    end
end

-- Something the tracker shows has changed: let observed progress advance the
-- step if it can, otherwise repaint the counts.
function NPCTracking:Changed()
    prepareMarkKey()
    local ObservedProgress = ns.modules.ObservedProgress
    if ObservedProgress and ObservedProgress:Refresh("npc") then return end
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.frame and MainWindow.frame:IsShown() then MainWindow:Refresh() end
    local NPCPanel = ns.modules.NPCPanel
    if NPCPanel and NPCPanel.Refresh then NPCPanel:Refresh() end
end

-- A kill of one of the step's targets. Only killing blows credited to the
-- player, their pet, or their party count (the combat log's PARTY_KILL).
function NPCTracking:OnCombatLog(...)
    local Client = ns.modules.Client
    local entry = Client:GetCombatLogEvent(...)
    if not entry or type(entry.destGUID) ~= "string" then return end
    if entry.subevent == "UNIT_DIED" then self.marked[entry.destGUID] = nil; return end
    if entry.subevent ~= "PARTY_KILL" then return end
    self.marked[entry.destGUID] = nil
    local id = Client:CreatureIDFromGUID(entry.destGUID)
    local target = id and self.targets[id]
    if not target or target.kind ~= "kill" then return end
    if not Client:IsPlayerOrGroupGUID(entry.sourceGUID) then return end
    self:RecordKill(entry.destGUID, id)
end

-- Without the combat log (clients with the restricted API forbid it), the
-- death of the player's own target counts while the player is fighting or
-- has just left combat, unless someone else had the creature tagged.
function NPCTracking:OnTargetChanged()
    local Client = ns.modules.Client
    local guid = Client:GetUnitGUID("target")
    self.targetGUID = guid
    self.targetWasAlive = guid ~= nil and not Client:UnitIsDead("target")
    self.targetTapDenied = guid ~= nil and Client:UnitIsTapDenied("target")
end

function NPCTracking:OnTargetHealth()
    local Client = ns.modules.Client
    local guid = Client:GetUnitGUID("target")
    if not guid or guid ~= self.targetGUID or not self.targetWasAlive then return end
    if Client:UnitIsTapDenied("target") then self.targetTapDenied = true end
    if not Client:UnitIsDead("target") then return end
    self.targetWasAlive = false
    if self.targetTapDenied then return end
    if not Client:UnitInCombat("player") and now() - self.combatLeftAt > COMBAT_GRACE then return end
    local id = Client:CreatureIDFromGUID(guid)
    -- The play recorder wants every kill, not only the ones a step counts:
    -- which creature died is the part the quest log's objective line cannot
    -- say, and the guide being written may not exist yet.
    local Recording = ns.modules.Recording
    if Recording and id then Recording:OnTargetDied(guid, id, Client:GetUnitName("target")) end
    local target = id and self.targets[id]
    if not target or target.kind ~= "kill" then return end
    self:RecordKill(guid, id)
end

function NPCTracking:RecordKill(guid, npcID)
    local time = now()
    for known, seen in pairs(self.recentKills) do
        if time - seen > KILL_MEMORY then self.recentKills[known] = nil end
    end
    if self.recentKills[guid] then return false end
    self.recentKills[guid] = time
    local TargetMarking = ns.modules.TargetMarking
    if TargetMarking and TargetMarking.ForgetAssumed then TargetMarking:ForgetAssumed(npcID) end
    self.observed[npcID], self.carries[npcID] = nil, nil
    local current, guide = self:Sync()
    local target = self.targets[npcID]
    if not current or not guide or not target then return false end
    for _, node in ipairs(target.nodes) do
        local count = ns.modules.Progress:RecordKill(guide, node.index)
        ns:Log("kill " .. count .. " of " .. ns.modules.Names:DescribeNPC(npcID) .. " for step '" .. ns.modules.Steps:Title(node) .. "'")
    end
    self:Changed()
    return true
end

-- A dialog opened with one of the group's NPCs: the "Talk to" line of every
-- step naming it turns green.
function NPCTracking:OnDialog()
    local node, guide = self:Sync()
    if not node or not guide then return end
    local id = ns.modules.Client:GetUnitCreatureID("npc")
    local target = id and self.targets[id]
    if not target then return end
    self:Seen(id, "npc")
    if target.kind ~= "talk" then return end
    local recorded = false
    for _, member in ipairs(target.nodes) do
        if ns.modules.Progress:RecordTalk(guide, member.index, id) then recorded = true end
    end
    if recorded then self:Changed() end
end

function NPCTracking:Initialize()
    local Client = ns.modules.Client
    local frame = CreateFrame("Frame")
    local events = { "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
        "RAID_TARGET_UPDATE", "PLAYER_REGEN_ENABLED", "ADDON_ACTION_FORBIDDEN" }
    for event in pairs(dialogEvents) do table.insert(events, event) end
    for _, event in ipairs(events) do pcall(frame.RegisterEvent, frame, event) end
    Client:RegisterUnitEvent(frame, "UNIT_HEALTH", "target")
    Client:RegisterUnitEvent(frame, "UNIT_FLAGS", "target")
    if Client:Has("combatLog") then pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED") end
    ns:Log("kill counting: " .. (Client:Has("combatLog") and "combat log" or "target deaths (combat log unavailable)"))
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            self:OnCombatLog(...)
        elseif event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
            if (...) == "target" then self:OnTargetHealth() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            self.combatLeftAt = now()
            local NPCPanel = ns.modules.NPCPanel
            if NPCPanel and NPCPanel.OnCombatEnded then NPCPanel:OnCombatEnded() end
        elseif event == "PLAYER_TARGET_CHANGED" then
            self:Sync(); self:OnTargetChanged(); self:Consider("target")
            -- The tracker copies a marker off the frame of a unit in view,
            -- so which unit that is changing is reason enough to repaint.
            self:MarkChanged()
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            self:Sync(); self:Consider("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            self:Sync(); self:Consider((...))
        elseif event == "RAID_TARGET_UPDATE" then
            -- Somebody's marker changed, ours or the player's own. Re-read
            -- every step creature in view; Observed sorts out what it means.
            self:ConsiderVisibleUnits(true)
        elseif dialogEvents[event] then
            self:OnDialog()
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:Sync()
        elseif event == "ADDON_ACTION_FORBIDDEN" then
            if Client.OnActionForbidden and Client:OnActionForbidden(...) then self:Changed() end
        end
    end)
    self.frame = frame
    self:Sync()
end

ns:RegisterModule("NPCTracking", NPCTracking)
