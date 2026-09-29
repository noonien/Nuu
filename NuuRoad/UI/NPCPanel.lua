local _, ns = ...

-- A grid of portraits for the current step's creatures, on the kit's strip
-- (UI:StripPanel): the picture is the whole control, and the name, the
-- marker, and the progress live in the tooltip, so the strip stays small
-- enough to sit under the minimap and be read at a glance. Five to a row,
-- wrapping onto as many rows as the step needs. Kill targets come first,
-- then the NPCs to speak to. A creature whose work is done leaves the grid;
-- the header still counts it.
--
-- Each slot is a secure button: clicking it targets that creature by name and
-- marks it, and the strip's title is itself the "mark all" control, so the
-- header carries no second button to crowd it. This client refuses marking by
-- an addon, so the panel never targets or marks anything itself - the
-- player's click or bound key does. The first ten slots are bindable (Key
-- Bindings > AddOns > NuuRoad, NuuRoadTargetButton1 to 10), which is what
-- makes the grid usable without the mouse. Slots cannot change during
-- combat; a refresh that lands then is applied when combat ends.
--
-- The slots are the kit's secure slots, never pooled: each is made once, the
-- first time a step needs that many, and kept for the session (shown,
-- hidden, repainted), so its global name and its binding stay with it. The
-- strip is made once too and never cleared.
local NPCPanel = { slots = {}, rows = {}, pending = false,
    -- Creatures a slot has drawn as a live head this session, id -> true.
    -- The client keeps a creature it has shown, so any slot can put the
    -- head back by ID; the strip changing, and a creature moving to another
    -- slot, no longer sends it back to the placeholder until it is seen again.
    heads = {} }

-- OpenRoad's 32: five fit under the minimap.
local COLUMNS, BOUND_SLOTS, SIZE = 5, 10, 32
local placeholders = {
    kill = "Interface/TargetingFrame/UI-RaidTargetingIcon_8",
    talk = "Interface/GossipFrame/ChatBubbleGossipIcon",
}
-- The ring and the name in the tooltip: a kill target in the danger colour,
-- an NPC to speak to in the accent (the tracker mockup's targets strip).
local kindTones = { kill = "danger", talk = "accent" }
local kindWords = { kill = "Kill target", talk = "NPC to talk to" }

-- Only the first ten slots are named and bindable; a step with more
-- creatures than that still shows them, they just have no key of their own.
NPCPanel.buttonNames = {}
for index = 1, BOUND_SLOTS do
    NPCPanel.buttonNames[index] = "NuuRoadTargetButton" .. index
    _G["BINDING_NAME_CLICK " .. NPCPanel.buttonNames[index] .. ":LeftButton"] = "Target step NPC " .. index
end


local function Config() return ns.modules.Config end
local function Client() return ns.modules.Client end
local function UI() return ns:GetUI() end

function NPCPanel:Enabled()
    return Config():Get("npcPanel.shown") == true and Config():Get("tracker.shown") == true
end

function NPCPanel:InViewOnly()
    return Config():Get("npcPanel.inViewOnly") == true
end

local function fillSlotTooltip(tip, slot)
    local data = slot.data
    local entry = data and data.entry
    if not entry then return end
    local t = slot.ui.tokens
    local color = t[kindTones[entry.kind]] or t.text
    tip:SetText(entry.name, color[1], color[2], color[3])
    local id = Config():Get("debug") and ("  (ID " .. entry.id .. ")") or ""
    tip:AddLine((kindWords[entry.kind] or "") .. id, t.muted[1], t.muted[2], t.muted[3])
    if entry.kind == "kill" and entry.killsNeeded then
        tip:AddLine("Kills: " .. (entry.kills or 0) .. " of " .. entry.killsNeeded, t.text[1], t.text[2], t.text[3])
    elseif entry.kind == "talk" then
        tip:AddLine("Still something to do here", t.text[1], t.text[2], t.text[3])
    end
    tip:AddLine(entry.inView and "In view" or "Not in view from here", t.muted[1], t.muted[2], t.muted[3])
    -- Only a marker the creature is really wearing is named. Which one it
    -- would get is our guess, and the client can hand out a different one or
    -- none at all, so saying it in advance would be telling the player
    -- something we do not know.
    if data.markerShown and entry.markerName then
        tip:AddLine("Carries its " .. entry.markerName, t.muted[1], t.muted[2], t.muted[3])
    end
    if slot:IsSecure() then
        tip:AddLine(data.marksOnClick and "Click to target it and mark it" or "Click to target by name", t.accent[1], t.accent[2], t.accent[3])
        local key = data.buttonName and Client():GetBindingKeyForButton(data.buttonName)
        if key then tip:AddLine("Bound to " .. key, t.accent[1], t.accent[2], t.accent[3]) end
    end
end

-- After the macro ran. Only believe the mark landed when the macro's
-- "/targetexact" really found that creature; otherwise nothing was marked
-- and the slot must stay armed. Whether the slot was armed is not part of
-- that test: the flag is only rewritten out of combat, and a press made
-- while it was stale still marked the creature.
local function slotClicked(slot)
    local entry = slot.data and slot.data.entry
    if not entry then return end
    if Client():GetUnitCreatureID("target") == entry.id then
        ns.modules.TargetMarking:NoteMarked(entry.id)
    end
    NPCPanel:RefreshMacros()
end

-- A creature in view is drawn as a live 3D head rather than the flat
-- portrait, which the game paints on a black disc. The slot holds the model
-- as its picture (slot:HoldModel), over its ring and under its key, count
-- and marker. It sat on the strip under the slot before, where the slot's
-- ring and backing covered it. The flat texture (the slot's icon) stays as
-- the stand-in until a creature is seen, and as the whole picture on a
-- client with no models.
local function modelShown(model)
    local slot = model.nuuSlot
    local id = slot and slot.data.portraitID
    if id then Client():SetModelCreature(model, id) end
end

local function createSlot(index)
    local ui = UI()
    local rowIndex = math.floor((index - 1) / COLUMNS) + 1
    local row = NPCPanel.rows[rowIndex]
    if not row then
        row = NPCPanel.grid:Row{ gap = 4 }
        NPCPanel.rows[rowIndex] = row
    end
    local name = NPCPanel.buttonNames[index] -- nil past the bindable ten
    local slot = row:Slot({ name = name, onClick = slotClicked, size = SIZE,
        secure = { type = "macro", macrotext = "/stopmacro" },
        data = { index = index, buttonName = name } })
    -- Only the key-down click is registered, so one click cannot run it
    -- twice, which for "/tm" would set the marker and take it off again.
    slot:Customize(ui.Custom.frame)
    if slot:IsSecure() and slot.RegisterForClicks then slot:RegisterForClicks("AnyDown") end
    slot:SetTooltip(function(tip) fillSlotTooltip(tip, slot) end)
    -- Not an item icon, so none of its border is cropped: the chat bubble
    -- and a flat portrait fill the picture whole.
    slot.icon:SetTexCoord(0, 1, 0, 1)
    local model = Client():CreatePortraitModel(slot)
    if model then
        slot:HoldModel(model)
        model.nuuSlot = slot
        model:Hide()
        -- The client can drop a hidden model's creature, so one shown again
        -- is given it back by ID.
        model:SetScript("OnShow", modelShown)
        slot.data.model = model
    end
    return slot
end

-- Puts a creature's head back on a slot that did not show it before, from
-- the creature ID alone. Only a creature drawn by unit before can be: the
-- flat portrait needs a unit to paint, so on a client with no models a
-- creature that changes slot waits to be seen again.
local function restoreHead(slot, id)
    local data = slot.data
    if not data.model or not NPCPanel.heads[id] then return false end
    data.portraitID = id
    slot:SetIcon(nil)
    -- A hidden model is given its creature by its own OnShow.
    if data.model:IsShown() then
        Client():SetModelCreature(data.model, id)
    else
        data.model:Show()
    end
    return true
end

-- The placeholder is greyed, as OpenRoad drew it, so it reads as a stand-in
-- beside a creature's own head.
local function setPlaceholder(slot, kind)
    slot:SetIcon(placeholders[kind])
    slot.icon:SetVertexColor(0.75, 0.75, 0.75, 1)
    if slot.data.model then slot.data.model:Hide() end
    slot.data.portraitID = nil
end

-- The marker icon stands for a marker the creature is carrying now: it
-- appears once one is really on it, and goes when the client says the
-- creature is bare, so taking a marker off by hand clears the portrait.
local function applyMarker(slot, entry, ours)
    local number = ours[entry.id]
    local shown = number ~= nil and ns.modules.NPCTracking:Enabled("markTargets")
    slot.data.markerShown = shown
    slot:SetMarker(shown and number or nil)
end

local function applyMacro(slot, entry)
    if not slot:IsSecure() then return end
    local TargetMarking = ns.modules.TargetMarking
    slot:SetSecure({ macrotext = TargetMarking:RowBody(entry) })
    slot.data.marksOnClick = entry.marker ~= nil and TargetMarking:Allowed()
end

-- The mark-all control -------------------------------------------------------------------

-- The strip's title is the "mark all" control: a secure button over the
-- title whose macro targets each step NPC that still needs its marker and
-- marks it. Like the slots, it only ever runs from the player's own click.
-- When there is nothing to mark it stays as a plain title and says why in
-- its tooltip; while there is, the title is underlined in the accent.
local function markAllClicked()
    local ids = NPCPanel.markIDs
    local names = {}
    for _, id in ipairs(ids or {}) do table.insert(names, ns.modules.Names:DescribeNPC(id)) end
    ns:Log("mark all pressed; the text on the button tried: " .. (#names > 0 and table.concat(names, ", ") or "nothing"))
    if ids then ns.modules.TargetMarking:NoteMarkedInView(ids) end
    NPCPanel:RefreshMacros()
end

local function paintUnderline(button, t)
    ns.Kit.UI.TexColor(button.underline, t.accent, NPCPanel.markHover and 1 or 0.6)
end

local function markAllEnter(button)
    NPCPanel.markHover = true
    paintUnderline(button, UI().tokens)
    UI():Tooltip(button, function(tip)
        local t = UI().tokens
        tip:SetText("Mark all", t.text[1], t.text[2], t.text[3])
        local ids = NPCPanel.markIDs
        if ids then
            tip:AddLine("Marks each creature in view. Press again for any out of reach.", t.text[1], t.text[2], t.text[3], true)
            tip:AddLine("Waiting for a marker: " .. #ids, t.muted[1], t.muted[2], t.muted[3])
            local key = Client():GetBindingKeyForButton(ns.modules.TargetMarking.allButtonName)
            if key then tip:AddLine("The same key: " .. key, t.accent[1], t.accent[2], t.accent[3]) end
        else
            tip:AddLine("Nothing here is waiting for a marker.", t.muted[1], t.muted[2], t.muted[3], true)
        end
    end, { anchor = "ANCHOR_RIGHT" })
end

local function markAllLeave(button)
    NPCPanel.markHover = false
    paintUnderline(button, UI().tokens)
    UI():HideTooltip()
end

function NPCPanel:CreateTitle(strip)
    local ok, button = pcall(strip.AddFrame, strip, "Button", "SecureActionButtonTemplate")
    if not ok or not button or not button.SetAttribute then
        button = strip:AddFrame("Button")
        self.markPlain = true
    else
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", "/stopmacro")
        if button.RegisterForClicks then button:RegisterForClicks("AnyDown") end
    end
    -- Over the title only, sized to its text (see Refresh), so the rest of
    -- the header stays a drag handle and the count on the right is never
    -- crowded.
    button:SetFrameLevel(strip.header:GetFrameLevel() + 2)
    button:SetPoint("LEFT", strip.header, "LEFT", 5, 0)
    button:SetSize(60, 16)
    button:EnableMouse(true)
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetHeight(1)
    button.underline:SetPoint("BOTTOMLEFT", 3, 1)
    button.underline:SetPoint("BOTTOMRIGHT", -3, 1)
    button.underline:Hide()
    button:SetScript("PostClick", markAllClicked)
    button:SetScript("OnEnter", markAllEnter)
    button:SetScript("OnLeave", markAllLeave)
    UI():Paint(button, function(t) paintUnderline(button, t) end)
    return button
end

-- The strip ----------------------------------------------------------------------------

function NPCPanel:Create()
    local ui = UI()
    local strip = ui:StripPanel({ key = "npcPanel", place = ns.db.windows, title = "Targets", rail = "danger", size = SIZE,
        point = { "CENTER", UIParent, "CENTER", 300, 160 } })
    self.frame = strip
    -- Rows of five, in a column, so a long step wraps onto a second row.
    self.grid = strip:Column{ gap = 4 }
    self.markAll = self:CreateTitle(strip)
    strip:Hide()
end

-- The creatures to put in the slots: everything still to do, in guide order.
-- The order never answers to what is in view. It used to put the creatures
-- the client could see in front, which sounded helpful and was not: every
-- change of target reshuffled the strip, so a slot's key binding pointed at
-- a different creature each time, a portrait captured for one slot was
-- thrown away when another entry landed in it, and the marking order moved
-- under the player's hands. A slot stays where it is; being in view is said
-- by the slot's own look, and the in-view option drops the rest of the rows
-- entirely rather than sorting them.
function NPCPanel:Candidates()
    local all = self:Enabled() and ns.modules.NPCTracking:Entries() or {}
    local visible = ns.modules.NPCTracking:VisibleTargets()
    local entries, done, total, inViewOnly = {}, 0, 0, self:InViewOnly()
    for _, entry in ipairs(all) do
        if entry.done then
            done, total = done + 1, total + 1
        elseif entry.live ~= false then
            -- An NPC with nothing to do yet, such as a turn-in for a quest
            -- not in the log, is not a target: it is neither shown nor counted.
            total = total + 1
            entry.inView = visible[entry.id] == true
            if entry.inView or not inViewOnly then table.insert(entries, entry) end
        end
    end
    return entries, done, total
end

-- Repaints the strip. Outside a step, with the setting off, with the tracker
-- hidden, or with everything done, the strip is hidden.
function NPCPanel:Refresh()
    if not self.frame then return end
    local Client = Client()
    if Client:InCombatLockdown() then self.pending = true; return end
    self.pending = false
    local entries, done, total = self:Candidates()
    local ours = ns.modules.TargetMarking:MarkersToDraw()
    local shown = #entries
    local kills, needed
    for index = 1, shown do
        local entry = entries[index]
        local slot = self.slots[index]
        if not slot then slot = createSlot(index); self.slots[index] = slot end
        local data = slot.data
        if data.portraitID ~= entry.id and not restoreHead(slot, entry.id) then setPlaceholder(slot, entry.kind) end
        data.entry = entry
        applyMarker(slot, entry, ours)
        if entry.kind == "kill" then kills, needed = entry.kills, entry.killsNeeded end
        slot:SetEdge(kindTones[entry.kind])
        slot:SetKey(data.buttonName and Client:GetBindingKeyForButton(data.buttonName))
        -- A kill target says what is left of its count; an NPC to speak to
        -- says so, where a stack count would be, in the kind's colour.
        local tone = kindTones[entry.kind]
        if entry.kind == "kill" and entry.killsNeeded then
            slot:SetCount(math.max(0, entry.killsNeeded - (entry.kills or 0)) .. "x", tone)
        else
            slot:SetCount(entry.kind == "talk" and "talk" or nil, tone)
        end
        -- What the sorting used to say, said without moving anything: a
        -- creature somewhere else is held back, and one the client can see
        -- is at full strength. Only the picture fades, not the ring.
        slot:FadePicture(entry.inView and 1 or 0.75)
        applyMacro(slot, entry)
        slot:Show()
        if data.portraitID and data.model then data.model:Show() end
    end
    for index = shown + 1, #self.slots do
        local slot = self.slots[index]
        slot:Hide()
        slot.data.entry = nil
        setPlaceholder(slot, "kill")
    end
    -- A row with nothing in it takes no room.
    for rowIndex, row in ipairs(self.rows) do row:SetShown((rowIndex - 1) * COLUMNS < shown) end
    if shown == 0 then self.frame:Hide(); return end
    if needed then
        self.frame:SetSummary("kills " .. (kills or 0) .. "/" .. needed)
    else
        self.frame:SetSummary(done .. "/" .. total)
    end
    self:RefreshMarkAll()
    self.frame:SetScale(Config():Get("tracker.scale") or 1)
    self.frame:Show()
end

-- Repoints the title at the creatures still waiting for a marker. With none
-- waiting, with marking off, or on a client that cannot run the macro, it
-- goes back to being a plain title: still there, no longer underlined, and
-- its tooltip says so.
function NPCPanel:RefreshMarkAll()
    local button = self.markAll
    if not button then return end
    local header = self.frame.header
    button:SetWidth(math.max(10, math.ceil(ns.Kit.UI.StringWidth(header.title)) + 6))
    local TargetMarking = ns.modules.TargetMarking
    local text, ids = nil, nil
    if TargetMarking and TargetMarking.MarkAllMacroText then text, ids = TargetMarking:MarkAllMacroText() end
    if not text or self.markPlain then
        self.markIDs = nil
        button.underline:Hide()
        -- Nothing left to mark, so the button must be made to do nothing.
        -- Leaving the text of the last press on it meant the next press ran
        -- that again.
        if not self.markPlain then button:SetAttribute("macrotext", "/stopmacro") end
        return
    end
    button:SetAttribute("macrotext", text)
    self.markIDs = ids
    button.underline:Show()
end

-- Target and marker changes move no slot, so they only repoint the macros
-- behind the slots and "Mark all". Nothing drops out of them for being
-- marked: each block clears the marker before setting it, so a press is
-- safe to repeat and never depends on a guess about what a creature is
-- already wearing.
function NPCPanel:RefreshMacros()
    if not self.frame or not self.frame:IsShown() then return end
    local TargetMarking = ns.modules.TargetMarking
    if not TargetMarking or Client():InCombatLockdown() then return end
    local ours = TargetMarking:MarkersToDraw()
    for _, slot in ipairs(self.slots) do
        local entry = slot.data.entry
        if entry and slot:IsShown() then
            applyMarker(slot, entry, ours)
            applyMacro(slot, entry)
        end
    end
    self:RefreshMarkAll()
end

-- A creature of the step is in view: its slot takes the unit's head as a
-- model, or its flat portrait where there are no models, once. With the
-- in-view option a creature that was not in the strip belongs in it now,
-- so the strip is rebuilt when it is missing.
function NPCPanel:OnUnitSeen(id, unit)
    if not self.frame or not self.frame:IsShown() then return end
    local Client = Client()
    for _, slot in ipairs(self.slots) do
        local data = slot.data
        if data.entry and data.entry.id == id and slot:IsShown() then
            if data.portraitID ~= id then
                -- Shown before it is given the unit: a model loads nothing
                -- while hidden, and with no ID on the slot yet its OnShow
                -- leaves it alone.
                data.portraitID = nil
                if data.model then data.model:Show() end
                if data.model and Client:SetModelUnit(data.model, unit) then
                    data.portraitID = id
                    self.heads[id] = true
                    slot:SetIcon(nil)
                elseif Client:SetUnitPortrait(slot.icon, unit) then
                    if data.model then data.model:Hide() end
                    slot.icon:SetVertexColor(1, 1, 1, 1)
                    data.portraitID = id
                elseif data.model then
                    data.model:Hide()
                end
            end
            if data.entry.inView then return end
            break
        end
    end
    -- Units come into view in bursts, so this waits a moment rather than
    -- rebuilding once per nameplate.
    local time = GetTime and GetTime() or 0
    if self.lastReorder and time - self.lastReorder < 0.5 then return end
    self.lastReorder = time
    self:Refresh()
end

-- A slot keeps its picture across a change of step: one that goes on
-- showing the same creature is left alone, and one that takes another
-- creature gets its head back when it has been seen.
function NPCPanel:OnStepChanged()
    self:Refresh()
end

function NPCPanel:OnCombatEnded()
    if self.pending then self:Refresh() end
end

-- What OpenRoad's Config:Changed refreshed for these settings, and the
-- tracker's own: the strip follows the tracker's visibility and scale.
function NPCPanel:OnSettingChanged(path)
    if path:sub(1, 9) == "npcPanel." or path == "tracker.shown" or path == "tracker.scale"
        or path == "automation.markTargets" then
        self:Refresh()
    end
end

function NPCPanel:Initialize()
    self:Create()
    self:Refresh()
end

ns:RegisterModule("NPCPanel", NPCPanel)
