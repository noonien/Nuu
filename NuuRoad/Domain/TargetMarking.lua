local _, ns = ...

-- Marking on clients that protect SetRaidTarget (12.0 and later, including
-- this Classic client). Addons may no longer mark on their own; the player's
-- keypress or click must do it. So this module writes the macro text that
-- does the marking, as the "macrotext" of secure buttons, and lets the
-- player supply the press:
--
--   * a hidden button holding "/tm N" for the creature that is targeted
--     right now, fired by a key binding,
--   * a hidden button that walks the whole step NPC list, targeting each
--     creature by name and marking it, fired by a second key binding; the
--     NPC panel's "Mark all" carries the same text,
--   * the text behind each NPC panel row, so a click targets that creature
--     and marks it.
--
-- No character macro is involved: the text lives on the buttons only, takes
-- no macro slot, and is rebuilt every session.
--
-- The addon still decides which icon each NPC gets; the player only supplies
-- the press. "/tm" toggles, so a unit that already carries its marker is
-- always left out, otherwise a second press would take the marker off again.
local TargetMarking = {
    buttonName = "NuuRoadMarkButton",
    allButtonName = "NuuRoadMarkAllButton",
    body = nil,      -- the text last written to the mark button, nil when unknown
    allBody = nil,   -- the same for the mark-all button
    pending = false, -- a write was refused (combat); retried when combat ends
    assumed = {},    -- creature ID -> when a click of the player's marked it
}

_G.BINDING_HEADER_NUUROAD = "NuuRoad"
_G["BINDING_NAME_CLICK " .. TargetMarking.buttonName .. ":LeftButton"] = "Mark the targeted step NPC"
_G["BINDING_NAME_CLICK " .. TargetMarking.allButtonName .. ":LeftButton"] = "Mark every step NPC in view"

local NOTHING = "/stopmacro" -- a body that does nothing when the key is pressed
local MACROTEXT_LIMIT = 1023 -- what a secure button's "macrotext" holds
local ASSUMED_SETTLE = 2     -- seconds before the client's "unmarked" is believed over a click of ours

local function now() return GetTime and GetTime() or 0 end

-- The client does not give us a truthful reading of a unit's marker right
-- after one of our own macros drove the targeting: it either hides the value
-- or still reports the unit as unmarked. So a click records what it marked
-- and that record wins over what the client says, which is what keeps a
-- second click on the same row from toggling the marker straight off again.
-- It is forgotten when the step moves on, when the creature is killed, and
-- when the client says the creature is bare, which is the one thing it will
-- say plainly. It used to expire after a few minutes as well; that only
-- took the icon off a creature still standing there wearing the marker, and
-- put the toggle back into the next press on its row.
function TargetMarking:NoteMarked(ids)
    if type(ids) ~= "table" then ids = { ids } end
    for _, id in ipairs(ids) do self.assumed[id] = now() end
    self:Drew()
end

-- A marker went on: the tracker draws it in front of the creature's name and
-- the strip in the corner of the portrait, so both are asked to repaint. On
-- a client that will not let the addon call SetRaidTarget itself, a click of
-- the player's is the only way a marker ever appears, so without this the
-- icon waits for whatever repaint happens next.
function TargetMarking:Drew()
    local MainWindow = ns.modules.MainWindow
    if MainWindow and MainWindow.RequestRefresh then MainWindow:RequestRefresh() end
end

-- The same for a "Mark all" press, which tries every creature the step still
-- wants marked and cannot tell us which of its blocks found one.
--
-- Every creature the press tried is credited. It used to credit only the
-- ones the client called visible, to avoid claiming a marker that was never
-- set -- but "visible" means a nameplate, and a player with nameplates off
-- marks three givers standing in front of them and is told one. The claim is
-- safe to make because being wrong corrects itself: a marker's absence is
-- the one thing this client reports plainly, so the first look at a creature
-- that was not really marked drops the claim and offers it again.
function TargetMarking:NoteMarkedInView(ids)
    self:NoteMarked(ids)
end

-- The client says a creature we believe we marked is wearing nothing. Right
-- after one of our macros drove the targeting that reading is not to be
-- trusted, so it counts only once the click has had a moment to settle;
-- after that the creature really is bare -- the player took the marker off
-- by hand -- and the record goes with it. Returns whether the reading was
-- believed, and whether believing it dropped an assumption.
function TargetMarking:NoteBare(npcID)
    local at = self.assumed[npcID]
    if at and now() - at < ASSUMED_SETTLE then return false, false end
    self.assumed[npcID] = nil
    return true, at ~= nil
end

-- What the target strip draws, as id -> marker. A creature gets an icon
-- once it is known to be carrying a marker -- a press of ours set one,
-- or the client says one is there -- and loses it the moment the client
-- says it carries nothing, so taking a marker off by hand takes the icon
-- off too. The marker drawn is the one that was read where the client gives
-- a number, and the one the step asked for otherwise, which is the best
-- available here: this client reports that a marker is present but never
-- which (docs/api-compatibility.md).
-- What the tracker's step lines draw, as id -> marker: only the markers a
-- press through NuuRoad put on. The step lines say what the guide asked
-- for and what came of it, so an icon there means "this press of yours
-- landed"; a marker the player put on by hand is their own business and is
-- not reported as the step's doing. The target strip uses MarkersToDraw
-- instead and shows any marker really on the creature, so the two can
-- disagree about a hand-marked creature. That is deliberate: the strip is
-- about the creatures in front of the player, the step line about the step.
function TargetMarking:MarkedByUs()
    local NPCTracking = ns.modules.NPCTracking
    local ours = {}
    if not NPCTracking then return ours end
    local read = NPCTracking.WornMarkers and NPCTracking:WornMarkers() or {}
    local assigned = NPCTracking.AssignedMarker or NPCTracking.MarkerFor
    for id in pairs(self.assumed) do ours[id] = read[id] or assigned(NPCTracking, id) end
    for id, marker in pairs(NPCTracking.MarkersWeSet and NPCTracking:MarkersWeSet() or {}) do ours[id] = marker end
    return ours
end

function TargetMarking:MarkersToDraw()
    local NPCTracking = ns.modules.NPCTracking
    local draw = {}
    if not NPCTracking then return draw end
    for id, seen in pairs(self:MarkersInView()) do
        draw[id] = (type(seen) == "number" and seen) or NPCTracking:MarkerFor(id)
    end
    return draw
end

-- Forgets one creature's assumed marker, or all of them when `npcID` is nil.
function TargetMarking:ForgetAssumed(npcID)
    if npcID == nil then self.assumed = {}; return end
    self.assumed[npcID] = nil
end

-- Forgets the assumed markers of creatures the step no longer names, and
-- only those. A step moving on inside a hub leaves the givers the player has
-- not reached yet exactly as they were: they are still standing there wearing
-- the marker, so dropping the record would take their icon away and put the
-- toggle back into the next press on their row.
function TargetMarking:ForgetAssumedExcept(keep)
    for id in pairs(self.assumed) do
        if not keep or keep[id] == nil then self.assumed[id] = nil end
    end
end

-- Whether the step's markers may be applied at all right now. The second
-- value says why not, for diagnostics.
function TargetMarking:Allowed()
    local Client, NPCTracking = ns.modules.Client, ns.modules.NPCTracking
    if not NPCTracking or not NPCTracking:Enabled("markTargets") then return false, "the markTargets setting is off" end
    if Client.MayMarkInGroup and not Client:MayMarkInGroup() then return false, "only the raid leader or an assistant may mark" end
    return true
end

-- One "target this creature by name, then mark it" block. "/cleartarget"
-- comes first so that a "/targetexact" which finds nobody cannot leave the
-- marker on whatever the player had targeted before, and "/cleartarget
-- [dead]" follows so that a corpse "/targetexact" happens to pick is dropped
-- rather than targeted and marked.
function TargetMarking:TargetBlock(name, marker)
    local block = "/cleartarget\n/targetexact " .. name .. "\n/cleartarget [dead]"
    -- "/tm N" toggles: on a creature already wearing N it takes the marker
    -- off. Since nothing here can know what a creature is wearing -- this
    -- client reports that a marker is present but never which, and one the
    -- player set by hand is invisible to us -- a press built on that guess
    -- is unsound: it can unmark, and then a record saying "marked" stops
    -- the button offering it again. "/tm 0" clears whatever is there first,
    -- so "/tm 0" then "/tm N" always ends with N, whatever it started as,
    -- and pressing twice is the same as pressing once.
    if marker then block = block .. "\n/tm 0\n/tm " .. marker end
    return block
end

-- The markers the step's creatures already carry, asked of NPCTracking once
-- per rebuild and passed down so the rows and the mark-all macro agree.
-- What a click of ours set counts as carried whatever the client reports,
-- both where it hid the marker and where it still calls the unit unmarked.
function TargetMarking:MarkersInView()
    local NPCTracking = ns.modules.NPCTracking
    if not NPCTracking or not NPCTracking.MarkersInView then return {} end
    local seen = NPCTracking:MarkersInView()
    -- A creature out of view still carries the mark we put on it.
    if NPCTracking.WornMarkers then
        for id, marker in pairs(NPCTracking:WornMarkers()) do
            if seen[id] == nil then seen[id] = marker end
        end
    end
    -- And one the client would not name is still marked: it must not be
    -- offered a marker again, because "/tm" would toggle off the one it has.
    if NPCTracking.CarriedMarkers then
        for id in pairs(NPCTracking:CarriedMarkers()) do
            if seen[id] == nil then seen[id] = "unknown" end
        end
    end
    for id in pairs(self.assumed) do
        if seen[id] == nil then seen[id] = "assumed" end
    end
    return seen
end

-- What the key should do for the current target: mark it with the step's
-- icon when it is an unmarked, living step NPC, otherwise nothing.
-- The second value says why the body is a no-op, for diagnostics.
function TargetMarking:DesiredBody()
    local Client = ns.modules.Client
    local allowed, reason = self:Allowed()
    if not allowed then return NOTHING, reason end
    if not Client:UnitExists("target") then return NOTHING, "nothing is targeted" end
    if Client:UnitIsDead("target") then return NOTHING, "the target is dead" end
    local id = Client:GetUnitCreatureID("target")
    if not id then return NOTHING, "the target's creature ID is unknown (GUID " .. tostring(Client:GetUnitGUID("target")) .. ")" end
    local marker = ns.modules.NPCTracking:MarkerFor(id)
    if not marker then return NOTHING, "creature " .. id .. " is not one of the step's NPCs" end
    -- Clear then set, for the reason in TargetBlock: pressing the key on a
    -- creature already wearing its marker leaves it wearing it.
    return string.format("/tm 0\n/tm %d", marker)
end

-- The macro text behind one NPC panel row: target that creature and give it
-- the step's marker. Nothing is left out for being marked already, since
-- the block sets the marker rather than toggling it, so a second press is
-- the same as the first.
function TargetMarking:RowBody(entry)
    local marker = entry.marker
    if not self:Allowed() then marker = nil end
    return self:TargetBlock(entry.name, marker)
end

-- One body that targets and marks every step NPC that still has work to do,
-- in guide order, whether or not it is in view: "/targetexact" reaches
-- further than we can see, and a press that finds nobody costs nothing.
--
-- Creatures believed to be marked already are kept in, not left out. What
-- we believe is a guess (see TargetBlock), and a press built on a guess can
-- unmark; each block sets its marker outright instead, so including them
-- costs a moment of targeting and guarantees that after a press every
-- creature the press reached wears the marker the step gave it. Blocks that
-- no longer fit in `limit` characters are dropped and counted as the third
-- value; pressing again picks them up once the earlier ones are done.
function TargetMarking:MarkAllBody(limit)
    local NPCTracking = ns.modules.NPCTracking
    local allowed, reason = self:Allowed()
    if not allowed then return NOTHING, reason, 0 end
    if not NPCTracking.Entries then return NOTHING, "the step's NPCs are unknown", 0 end
    local body, skipped, ids = "", 0, {}
    for _, entry in ipairs(NPCTracking:Entries()) do
        if entry.marker and not entry.done then
            local block = self:TargetBlock(entry.name, entry.marker)
            local candidate = body == "" and block or (body .. "\n" .. block)
            if limit and #candidate > limit then
                skipped = skipped + 1
            else
                body = candidate
                table.insert(ids, entry.id)
            end
        end
    end
    if body == "" then return NOTHING, "the step has no creature to mark", 0, ids end
    return body, nil, skipped, ids
end

-- The text for the panel's "Mark all" button, and the creatures it would
-- mark.
function TargetMarking:MarkAllMacroText()
    local body, _, _, ids = self:MarkAllBody(MACROTEXT_LIMIT)
    if body == NOTHING then return nil, nil end
    return body, ids
end

-- True when the key would mark the current target.
function TargetMarking:IsArmed()
    return self.available == true and self.body ~= nil and self.body ~= NOTHING
end

function TargetMarking:Key(buttonName)
    return ns.modules.Client:GetBindingKeyForButton(buttonName or self.buttonName)
end

-- Rewrites one of the two buttons when its text changed. True when it was
-- written just now; a refusal (combat locks the attribute) leaves the
-- remembered text alone, so the next Prepare retries it.
function TargetMarking:WriteBody(field, button, body)
    if body == self[field] then return false end
    local Client = ns.modules.Client
    -- A refused write leaves the button holding its previous text, so the
    -- next press does whatever that said -- nothing, or a creature list one
    -- step out of date. That is what a press that "sometimes" works looks
    -- like from the player's side, so every refusal is logged.
    if Client:InCombatLockdown() then
        self.pending = true
        ns:Log("marking macro not written (in combat); the button still holds its previous text")
        return false
    end
    if Client:SetSecureMacroText(button, body) then
        self[field] = body
        ns:Log("marking macro written to " .. tostring(field) .. ": " .. body:gsub("\n", " | "))
        return true
    end
    self.pending = true
    ns:Log("marking macro refused by the client for " .. tostring(field))
    return false
end

function TargetMarking:Prepare()
    if not self.available then return end
    self.pending = false
    local body = self:DesiredBody()
    self:WriteBody("body", self.button, body)
    -- The creatures the mark-all text was built for are kept, because a key
    -- press tells us nothing about what it did: the record has to come from
    -- what the text was asked to mark.
    local allBody, _, _, allIDs = self:MarkAllBody(MACROTEXT_LIMIT)
    self.allIDs = allIDs
    self:WriteBody("allBody", self.allButton, allBody)
    local NPCPanel = ns.modules.NPCPanel
    if NPCPanel and NPCPanel.RefreshMacros then NPCPanel:RefreshMacros() end
end

-- "/nuuroad markkey F8" binds, "markkey none" unbinds, "markkey" reports.
-- `buttonName` picks the mark-all button instead of the mark-target one.
function TargetMarking:SetKey(text, buttonName)
    local Client = ns.modules.Client
    buttonName = buttonName or self.buttonName
    local key = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
    if not self.available then ns:Print("This client cannot mark targets through a macro."); return end
    if key == "" then
        local current = self:Key(buttonName)
        ns:Print(current and ("Mark key: " .. current .. ".") or "No mark key bound. Use /nuuroad markkey F8 (or any key).")
        return
    end
    if Client:InCombatLockdown() then ns:Print("Keys cannot be bound in combat."); return end
    if key == "NONE" or key == "OFF" or key == "CLEAR" then
        Client:BindKeyToButton(nil, buttonName)
        ns:Print("Mark key removed.")
        return
    end
    if Client:BindKeyToButton(key, buttonName) then
        ns:Print("Mark key bound to " .. key .. ". Target a step NPC and press it to apply the step's marker.")
    else
        ns:Print("Could not bind '" .. key .. "'. Use a key name such as F8, CTRL-F, or MOUSEBUTTON4.")
    end
end

-- The creature IDs whose marker we are believing on a click's word.
function TargetMarking:AssumedList()
    local ids = {}
    for id in pairs(self.assumed) do table.insert(ids, tostring(id)) end
    table.sort(ids)
    return #ids > 0 and table.concat(ids, ", ") or "none"
end

function TargetMarking:DiagnosticLines()
    local NPCTracking = ns.modules.NPCTracking
    local body, reason = self:DesiredBody()
    local allBody, allReason, skipped = self:MarkAllBody(MACROTEXT_LIMIT)
    local stepNPCs = {}
    for id, target in pairs(NPCTracking and NPCTracking.targets or {}) do
        table.insert(stepNPCs, id .. "=" .. tostring(target.marker) .. "(" .. tostring(target.kind) .. ")")
    end
    table.sort(stepNPCs)
    return {
        "step NPCs and markers: " .. (#stepNPCs > 0 and table.concat(stepNPCs, ", ") or "none"),
        "desired body now: " .. body .. (reason and (" because " .. reason) or ""),
        "secure marking available: " .. tostring(self.available == true),
        "mark key: " .. tostring(self:Key()),
        "mark-all key: " .. tostring(self:Key(self.allButtonName)),
        "mark button text last written: " .. tostring(self.body),
        "mark-all button text: " .. (allBody:gsub("\n", " | ")) .. (allReason and (" because " .. allReason) or ""),
        "mark-all NPCs left out for length: " .. tostring(skipped),
        "markers assumed from our own clicks: " .. self:AssumedList(),
        "write pending (combat): " .. tostring(self.pending),
        "armed for current target: " .. tostring(self:IsArmed()),
    }
end

-- Runs `handler` after a press of one of the secure buttons. The press
-- itself is the client's business; this is the only chance to record what
-- it did, and without it a key press marks a creature and the tracker never
-- hears about it.
local function afterPress(button, handler)
    if type(button) ~= "table" or type(button.SetScript) ~= "function" then return end
    pcall(button.SetScript, button, "PostClick", handler)
end

function TargetMarking:Initialize()
    local Client = ns.modules.Client
    self.available = Client:Has("secureMarking")
    if not self.available then ns:Log("secure marking: unavailable on this client"); return end
    self.button = Client:CreateSecureMacroButton(self.buttonName, NOTHING)
    self.allButton = Client:CreateSecureMacroButton(self.allButtonName, NOTHING)
    if not self.button or not self.allButton then self.available = false; ns:Log("secure marking: could not create the buttons"); return end
    self.body, self.allBody = NOTHING, NOTHING
    afterPress(self.button, function()
        -- Whatever the key marked, it marked the current target, and the
        -- text only carries a "/tm" when that target is a step creature.
        local id = Client.GetUnitCreatureID and Client:GetUnitCreatureID("target")
        local NPCTracking = ns.modules.NPCTracking
        if id and NPCTracking and (NPCTracking.targets or {})[id] then self:NoteMarked(id) end
        self:Prepare()
    end)
    afterPress(self.allButton, function()
        if self.allIDs then self:NoteMarkedInView(self.allIDs) end
        self:Prepare()
    end)
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "RAID_TARGET_UPDATE", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    Client:RegisterUnitEvent(frame, "UNIT_FLAGS", "target")
    frame:SetScript("OnEvent", function() self:Prepare() end)
    self.frame = frame
    ns:Log("secure marking: via " .. self.buttonName .. ", key " .. tostring(self:Key()))
end

ns:RegisterModule("TargetMarking", TargetMarking)
