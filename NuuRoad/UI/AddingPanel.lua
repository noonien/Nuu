local _, ns = ...

-- Adding steps while playing (docs/authoring.md): a small panel beside the
-- tracker with a button for each thing the player does. Each button adds a
-- step after the last one added, filled from what is in front of the
-- player: the NPC they speak to or target, where they stand, the quest
-- window that is open. Pressing Accept twice at one NPC puts both quests on
-- one step. Nothing is recorded: a step is added only by a press.
--
-- While the panel is open, the quest window and the gossip window carry a
-- button of their own (Add the accept, Add the turn-in, Add one step for all
-- of them), and once an accepted quest is in the log the panel offers the
-- rest of it: a step per objective and the turn-in, as one press.
--
-- It works on the editor's draft (UI/Editor.lua, Domain/GuideDraft.lua), so
-- every step it adds is kept at once, undone with Undo, and finished in the
-- full editor. Built from NuuKit's widgets.
local Panel = {}

local function M(name) return ns.modules[name] end
local function ui() return ns:GetUI() end
local function Editor() return M("Editor") end
local function Client() return M("Client") end

local function trim(text) return (tostring(text or ""):match("^%s*(.-)%s*$")) end

-- The buttons, two rows of four.
local BUTTONS = {
    { "accept", "Accept" }, { "turnin", "Turn in" }, { "kill", "Kill" }, { "collect", "Collect" },
    { "talk", "Talk" }, { "travel", "Go here" }, { "note", "Note" }, { "more", "More" },
}

-- What a quest objective's kind makes of its step.
local OBJECTIVE_TYPES = { monster = "kill", item = "collect", object = "interact" }

-- The NPC in front of the player: the one a quest or gossip window is open
-- with, else the target. Its ID and name.
local function npcHere()
    local client = Client()
    if not client then return nil end
    for _, unit in ipairs({ "npc", "target" }) do
        local id = client:GetUnitCreatureID(unit)
        if id then return id, client:GetUnitName(unit) end
    end
    return nil
end

local function contains(values, id)
    for _, value in ipairs(type(values) == "table" and values or { values }) do
        if value == id then return true end
    end
    return false
end

-- Window -----------------------------------------------------------------------------------------

local function buttonClicked(button) Panel:Press(button.data.kind, button) end
local function undoClicked() Panel:Undo() end
local function editorClicked() Panel:OpenEditor() end
local function onEvent(_, event, ...) Panel:OnEvent(event, ...) end

function Panel:Build()
    if self.win then return end
    local db = ns.db
    local places = db and db.windows or {}
    local win = ui():Window({
        key = "addingPanel", title = "Adding steps", width = 360, height = 360, resizable = "height",
        minHeight = 260, place = places, status = true, hidden = true,
    })
    self.win = win
    local header = win.header
    header:Spacer{}
    self.undoButton = header:GlyphButton{ "undo", boxed = true, bright = true, size = 24, onClick = undoClicked,
        tooltip = "Undo: take back the last step added" }
    header:Button{ "Full editor", onClick = editorClicked, tooltip = "The whole guide, to fix wording and order" }

    local body = win:Column{ gap = 10, padding = 10 }
    self.buttons = {}
    for row = 0, 1 do
        local line = body:Row{ gap = 6 }
        for column = 1, 4 do
            local entry = BUTTONS[row * 4 + column]
            local kind = entry[1]
            self.buttons[kind] = line:Button{ entry[2], grow = true, height = 50, iconAbove = true, iconSize = 18,
                icon = Editor().TypeIcon(kind), glyph = kind == "more" and "plus" or nil,
                data = { kind = kind }, onClick = buttonClicked }
        end
    end
    self.context = body:Text{ "", style = "fine", color = "muted", wrap = true }
    self.added = body:Column{ gap = 6 }
    self.offer = body:Column{ gap = 6 }

    if CreateFrame then
        local frame = CreateFrame("Frame")
        for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_ACCEPTED",
            "GOSSIP_SHOW", "GOSSIP_CLOSED", "PLAYER_TARGET_CHANGED" }) do
            pcall(frame.RegisterEvent, frame, event)
        end
        frame:SetScript("OnEvent", onEvent)
        self.events = frame
    end
end

-- Opens the panel on a draft (or the guide followed, or the one in the
-- editor), adding after its last step.
function Panel:Open(draftOrGuide)
    self:Build()
    local editor = Editor()
    local draft
    if type(draftOrGuide) == "table" and draftOrGuide.guide and draftOrGuide.Entries then
        draft = draftOrGuide
    else
        local guide = draftOrGuide
        if not guide and not editor.draft then
            local Progress = M("Progress")
            guide = Progress and Progress:GetActiveGuide()
        end
        draft = guide and editor:DraftFor(guide) or editor.draft
    end
    if not draft then
        ns:Print("Open a guide first: New guide in the guide browser starts one.")
        return
    end
    self.draft = draft
    self.after = draft:StepAt(draft:Count())
    self.lastAdded = nil
    self.pending = nil
    self.win:Show()
    self:Render()
    return true
end

function Panel:Hide()
    if self.win then self.win:Hide() end
    self:HideAttachments()
end

function Panel:IsShown() return self.win ~= nil and self.win:IsShown() or false end

function Panel:Toggle(guide)
    if self:IsShown() then return self:Hide() end
    return self:Open(guide)
end

function Panel:OpenEditor()
    local editor = Editor()
    if not self.draft then return end
    if editor.draft ~= self.draft then editor:Attach(self.draft, 1) end
    editor:Show()
    if self.lastAdded then editor:Select(self.lastAdded) end
end

function Panel:SetStatus(text, isError)
    if not self.win then return end
    self.statusOpts = self.statusOpts or {}
    self.statusOpts.tone = isError and "danger" or "text"
    self.win:Status(text ~= "" and text or nil, self.statusOpts)
end

-- Adding -------------------------------------------------------------------------------------------

-- The draft still the editor's? A guide opened elsewhere since takes over.
function Panel:Draft()
    local editor = Editor()
    if self.draft and editor.draft ~= self.draft then self.draft = editor.draft end
    return self.draft
end

-- Adds `step` after the last one added and makes it the last.
function Panel:Add(step, what)
    local draft = self:Draft()
    if not draft then return nil end
    local after = self.after and draft:EntryOf(self.after) and self.after or draft:StepAt(draft:Count())
    local added = draft:Insert(after, step)
    if not added then return nil end
    self.after, self.lastAdded = added, added
    self:SetStatus(what or "Added.")
    self:Render()
    return added
end

-- Keeps the NPC in front of the player in the guide, with where they stand
-- (or, for a creature that roams, its name alone).
local function keepNPC(draft, id, name, roams)
    if roams then
        if name and not draft:NPC(id) then draft:KeepNPC(id, name) end
        return
    end
    local at, map = Editor().WhereIStand()
    draft:KeepNPC(id, name, map, at)
end

-- A quest step (accept or turn in) for the open quest window's quest, or
-- one picked from the log. A second press at the same NPC joins the step
-- just added.
function Panel:QuestStep(kind, questID, anchor)
    local draft = self:Draft()
    if not questID then
        local client = Client()
        questID = client and self.questMode == kind and client:GetOpenQuestID() or nil
    end
    if not questID then
        return Editor():OpenQuestMenu(anchor or self.win, function(ids) self:QuestStep(kind, ids[1]) end)
    end
    local id, name = npcHere()
    local last = self.lastAdded
    if last and last.type == kind and draft:EntryOf(last) and id and contains(last.npc, id) then
        if contains(last.quests, questID) then return self:SetStatus("Already on this step.") end
        local quests = {}
        for _, value in ipairs(type(last.quests) == "table" and last.quests or { last.quests }) do quests[#quests + 1] = value end
        quests[#quests + 1] = questID
        draft:SetField(last, "quests", quests, kind)
        self:SetStatus(Editor().QuestName(questID) .. " joins the step.")
        self:Render()
        if kind == "accept" then self:Expect(questID, last) end
        return last
    end
    local step = { type = kind, quests = { questID } }
    if id then step.npc = { id } end
    local added = self:AddWithNPC(step, id, name, (kind == "accept" and "Accept " or "Turn in ") .. Editor().QuestName(questID) .. ".")
    if added and kind == "accept" then self:Expect(questID, added) end
    return added
end

-- Adds a step that names an NPC, keeping the NPC in the guide in the same change.
function Panel:AddWithNPC(step, id, name, what, roams)
    local draft = self:Draft()
    if not draft then return nil end
    local after = self.after and draft:EntryOf(self.after) and self.after or draft:StepAt(draft:Count())
    local ok = draft:Change("add", function()
        if id then keepNPC(draft, id, name, roams) end
        local entry = draft:EntryOf(after)
        if entry and entry.group then
            table.insert(draft.guide.data.sections[entry.section].steps, entry.groupAt + 1, step)
        elseif entry then
            table.insert(entry.container, entry.at + 1, step)
        else
            table.insert(draft.guide.data.sections[1].steps, 1, step)
        end
    end)
    if not ok then return nil end
    self.after, self.lastAdded = step, step
    self:SetStatus(what or "Added.")
    self:Render()
    return step
end

function Panel:Press(kind, anchor)
    local draft = self:Draft()
    if not draft then return end
    if kind == "accept" or kind == "turnin" then return self:QuestStep(kind, nil, anchor) end
    if kind == "more" then
        return ui():OpenMenu(Editor():TypeItems(function(picked) self:AddKind(picked) end), { anchor = anchor })
    end
    return self:AddKind(kind)
end

-- A step of `kind`, filled from the player's surroundings where the type uses them.
function Panel:AddKind(kind)
    local id, name = npcHere()
    if kind == "kill" then
        if not id then return self:SetStatus("Target the creature first.", true) end
        return self:AddWithNPC({ type = "kill", kill = { id } }, id, name, "Kill " .. (name or ("creature " .. id)) .. ".", true)
    end
    if kind == "collect" then
        local step = { type = "collect" }
        if id then step.kill = { id } end
        return self:AddWithNPC(step, id, name, "Collect: shift-click the item into the field below.", true)
    end
    if kind == "travel" then
        local at, map = Editor().WhereIStand()
        if not at then return self:SetStatus("Your position cannot be read here.", true) end
        local draft = self:Draft()
        if map ~= draft.guide.data.map then at.map = map end
        local client = Client()
        local to = client and client:GetSubzone() or nil
        return self:AddWithNPC({ type = "travel", to = to, at = { at } }, nil, nil, "Go to " .. (to or "here") .. ".")
    end
    if kind == "note" then
        local added = self:Add({ type = "note" }, "A note: write it below.")
        if added and self.noteField and self.noteField.box then self.noteField.box:SetFocus() end
        return added
    end
    local step = { type = kind }
    if kind == "vendor" then step.sell = true end
    if kind == "choice" then step.text = "Which way?" end
    local takesNPC = { talk = true, vendor = true, buy = true, train = true, learn = true, hearth = true, flight = true,
        escort = true }
    if takesNPC[kind] and id then
        step.npc = { id }
        return self:AddWithNPC(step, id, name, (name or "The NPC") .. " is this step's NPC.")
    end
    return self:Add(step)
end

function Panel:Undo()
    local draft = self:Draft()
    if not draft then return end
    local what = draft:Undo()
    if self.lastAdded and not draft:EntryOf(self.lastAdded) then self.lastAdded = nil end
    if self.after and not draft:EntryOf(self.after) then self.after = draft:StepAt(draft:Count()) end
    self.pending = nil
    self:SetStatus(what and ("Undone: " .. what .. ".") or "Nothing to undo.")
    self:Render()
end

-- The rest of a quest -------------------------------------------------------------------------------

-- An accept just added: once the quest is in the log, its objectives are
-- known, and the rest of the quest is offered.
function Panel:Expect(questID, step)
    self.pending = { questID = questID, step = step }
    local client = Client()
    if client and client:IsQuestInLog(questID) then self:Offer() end
end

function Panel:Offer()
    local pending = self.pending
    if not pending then return end
    local client = Client()
    local lines = client and client:GetQuestObjectives(pending.questID) or {}
    local steps = {}
    for index, line in ipairs(lines) do
        steps[#steps + 1] = { type = OBJECTIVE_TYPES[line.type] or "interact", quest = { pending.questID, index },
            caption = line.text }
    end
    steps[#steps + 1] = { type = "turnin", quests = { pending.questID }, caption = "Turn in " .. Editor().QuestName(pending.questID) }
    pending.steps = steps
    self:Render()
end

function Panel:TakeOffer()
    local pending, draft = self.pending, self:Draft()
    if not (pending and pending.steps and draft) then return end
    local after = draft:EntryOf(pending.step) and pending.step or self.after
    local made = {}
    draft:Change("add", function()
        local anchor = after
        for _, template in ipairs(pending.steps) do
            local step = {}
            for key, value in pairs(template) do if key ~= "caption" then step[key] = value end end
            local entry = draft:EntryOf(anchor)
            if entry and entry.group then
                table.insert(draft.guide.data.sections[entry.section].steps, entry.groupAt + 1, step)
            elseif entry then
                table.insert(entry.container, entry.at + 1, step)
            end
            draft.entries = nil
            anchor = step
            made[#made + 1] = step
        end
    end)
    self.pending = nil
    self:SetStatus(#made .. " steps added after the accept. Move them where you do them in the full editor.")
    self:Render()
end

function Panel:DropOffer()
    self.pending = nil
    self:Render()
end

-- Drawing ------------------------------------------------------------------------------------------

function Panel:Render()
    if not (self.win and self.win:IsShown()) then return end
    local draft = self:Draft()
    if not draft then return end
    local entry = self.after and draft:EntryOf(self.after)
    self.win:SetTitle("Adding after step " .. (entry and entry.position or draft:Count()))
    self.win:SetSubtitle(draft.guide.title)
    self.undoButton:SetEnabled(draft:CanUndo(), "Nothing to undo")
    -- The quest window open: the press it asks for stands out.
    self.buttons.accept:SetActive(self.questMode == "accept")
    self.buttons.turnin:SetActive(self.questMode == "turnin")

    local id, name = npcHere()
    local parts = {}
    if id then parts[#parts + 1] = "Target: " .. (name or ("NPC " .. id)) end
    local client = Client()
    local questID = client and self.questMode and client:GetOpenQuestID()
    if questID then parts[#parts + 1] = "Quest window: " .. Editor().QuestName(questID) end
    -- Said only until the first step is added; after that the card speaks.
    self.context:SetShown(self.lastAdded == nil)
    self.context:SetText(#parts > 0 and table.concat(parts, ". ") .. "." or "Target an NPC, or open a quest, then press what you do.")

    local added = self.added
    added:Clear()
    self.noteField = nil
    local step = self.lastAdded
    if step and draft:EntryOf(step) then
        local card = added:Card{ tone = "accent", padding = 8, gap = 6 }
        local head = card:Row{ gap = 8, valign = "center" }
        head:Text{ tostring(draft:EntryOf(step).position), style = "number", color = "muted" }
        local info
        for _, entry in ipairs(Editor().types) do if entry.key == step.type then info = entry end end
        head:Tag{ info and info.glyph or "?", tone = info and info.color ~= "muted" and info.color or nil, width = 18 }
        head:Text{ Editor():TitleOf(step), style = "label", grow = true, wrap = true }
        head:Text{ "just added", style = "fine", color = "muted" }
        local npc = type(step.npc) == "table" and step.npc[1] or nil
        if npc then
            local who = card:Row{ gap = 8, valign = "center" }
            who:Text{ "Who", width = 50 }
            who:Tag{ draft:NPCName(npc) or ("NPC " .. npc), tone = "accent" }
        end
        local problems = draft:ProblemsOf(step)
        if problems then card:Text{ problems[1].text, style = "fine", color = problems[1].level == "error" and "danger" or "warning", wrap = true } end
        if step.type == "collect" and not step.item then
            Editor():LinkInput(card:Row{ gap = 6 }, "item", "Item: ID, or shift-click", function(ids)
                draft:SetField(step, "item", ids[1], "item")
                self:Render()
            end, 200)
        end
        self.noteField = card:Input{ value = step.note or "", placeholder = "Note, shown under the step (optional)",
            onChange = function(text)
                draft:SetField(step, "note", trim(text), "note")
                self:Render()
            end }
    end

    local offer = self.offer
    offer:Clear()
    local pending = self.pending
    if pending and pending.steps then
        local card = offer:Card{ tone = "gain", padding = 8, gap = 6 }
        card:Text{ "Add the rest of " .. Editor().QuestName(pending.questID) .. "?", style = "label", wrap = true }
        local names = {}
        for _, template in ipairs(pending.steps) do names[#names + 1] = template.caption or template.type end
        card:Text{ table.concat(names, "; ") .. ". You can move them after.", style = "fine", color = "muted", wrap = true }
        local row = card:Row{ gap = 6 }
        row:Button{ "Add " .. #pending.steps .. " steps", tone = "accent", onClick = function() self:TakeOffer() end }
        row:Button{ "No thanks", onClick = function() self:DropOffer() end }
    end
    self:SyncAttachments()
end

-- The quest and gossip windows ------------------------------------------------------------------

function Panel:OnEvent(event, ...)
    if event == "QUEST_DETAIL" then self.questMode = "accept"
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then self.questMode = "turnin"
    elseif event == "QUEST_FINISHED" then self.questMode = nil
    elseif event == "GOSSIP_SHOW" then self.gossipOpen = true
    elseif event == "GOSSIP_CLOSED" then self.gossipOpen = nil
    elseif event == "QUEST_ACCEPTED" then
        local first, second = ...
        local questID = type(second) == "number" and second or first
        if self.pending and self.pending.questID == questID then self:Offer() end
    end
    if self:IsShown() then self:Render() end
end

-- A button under a client window, made once and moved to it.
local function attachment(self, key, parent)
    local button = self[key]
    if not button then
        button = ui():Button(parent, { "", tone = "accent", onClick = function(clicked) Panel:AttachmentClicked(clicked) end })
        self[key] = button
    end
    button:ClearAllPoints()
    button:SetPoint("TOP", parent, "BOTTOM", 0, -6)
    return button
end

function Panel:HideAttachments()
    if self.questButton then self.questButton:Hide() end
    if self.questUndo then self.questUndo:Hide() end
    if self.gossipButton then self.gossipButton:Hide() end
end

-- What the quest window's button would do, and the gossip window's.
function Panel:SyncAttachments()
    if not self:IsShown() then return self:HideAttachments() end
    local draft, client = self:Draft(), Client()
    local questFrame = rawget(_G, "QuestFrame")
    local questID = client and self.questMode and client:GetOpenQuestID()
    if questID and type(questFrame) == "table" and questFrame.IsShown and questFrame:IsShown() then
        local button = attachment(self, "questButton", questFrame)
        local found = self:StepWithQuest(questID, self.questMode)
        if found then
            local justAdded = found == self.lastAdded
            button:SetText((justAdded and "Added as step " or "In your guide: step ") .. draft:EntryOf(found).position)
            button.data = nil
            if justAdded then
                local undo = self.questUndo
                if not undo then
                    undo = ui():Button(questFrame, { "Undo", onClick = function() Panel:Undo() end })
                    self.questUndo = undo
                end
                undo:ClearAllPoints()
                undo:SetPoint("LEFT", button, "RIGHT", 6, 0)
                undo:Show()
            elseif self.questUndo then
                self.questUndo:Hide()
            end
        else
            if self.questUndo then self.questUndo:Hide() end
            button:SetText(self.questMode == "accept" and "Add the accept" or "Add the turn-in")
            button.data = { kind = self.questMode, questID = questID }
        end
        button:Show()
    elseif self.questButton then
        self.questButton:Hide()
        if self.questUndo then self.questUndo:Hide() end
    end
    local gossipFrame = rawget(_G, "GossipFrame")
    if self.gossipOpen and type(gossipFrame) == "table" and gossipFrame.IsShown and gossipFrame:IsShown() and client then
        local quests = client:GetGossipQuests()
        local accept, turnin = {}, {}
        for _, entry in ipairs(quests.available) do
            if entry.questID and not self:StepWithQuest(entry.questID, "accept") then accept[#accept + 1] = entry.questID end
        end
        for _, entry in ipairs(quests.active) do
            if entry.questID and entry.isComplete and not self:StepWithQuest(entry.questID, "turnin") then turnin[#turnin + 1] = entry.questID end
        end
        if #accept + #turnin > 0 then
            local button = attachment(self, "gossipButton", gossipFrame)
            local words = {}
            if #turnin > 0 then words[#words + 1] = "turn in " .. #turnin end
            if #accept > 0 then words[#words + 1] = "accept " .. #accept end
            button:SetText("Add one step: " .. table.concat(words, ", "))
            button.data = { kind = "gossip", accept = accept, turnin = turnin }
            button:Show()
        elseif self.gossipButton then
            self.gossipButton:Hide()
        end
    elseif self.gossipButton then
        self.gossipButton:Hide()
    end
end

-- The guide's step that already takes or hands in `questID`, if any.
function Panel:StepWithQuest(questID, kind)
    local draft = self:Draft()
    for _, entry in ipairs(draft and draft:Entries() or {}) do
        local step = entry.step
        if kind == "accept" and ((step.type == "accept" and contains(step.quests, questID)) or (step.type == "talk" and contains(step.accept, questID))) then
            return step
        end
        if kind == "turnin" and ((step.type == "turnin" and contains(step.quests, questID)) or (step.type == "talk" and contains(step.turnin, questID))) then
            return step
        end
    end
    return nil
end

function Panel:AttachmentClicked(button)
    local data = button.data
    if not data then return end
    if data.kind == "accept" or data.kind == "turnin" then
        self:QuestStep(data.kind, data.questID)
    elseif data.kind == "gossip" then
        local id, name = npcHere()
        local step = { type = "talk", turnin = #data.turnin > 0 and data.turnin or nil, accept = #data.accept > 0 and data.accept or nil }
        if id then step.npc = { id } end
        local added = self:AddWithNPC(step, id, name, "One step for everything at " .. (name or "this NPC") .. ".")
        if added and #data.accept == 1 then self:Expect(data.accept[1], added) end
    end
    self:SyncAttachments()
end

ns:RegisterModule("AddingPanel", Panel)
