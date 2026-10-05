local _, ns = ...

-- The guide editor (docs/authoring.md): the guide's steps on the left, in
-- their sections, and the page of the selected step on the right. It edits
-- the guide as written, in format v1, through a draft (Domain/GuideDraft.lua)
-- that keeps every change as it is made: there is no Save and no Cancel, and
-- Undo goes back. What is wrong with a step is said on the step, with the
-- fix as a button where there is one.
--
-- A step's page shows only what its type is made of, in plain words, filled
-- the way a player already fills things: Use my target, Where I stand, the
-- quest log, and a shift-click on an item, quest or spell into the field in
-- focus. Typing an ID still works. Everything rare sits behind More options;
-- the tools for the whole guide (settings, places, text) behind the Guide
-- menu.
--
-- Built from NuuKit's widgets. The window is made the first time it opens;
-- the step's page is rebuilt from the kit's pools when another step or type
-- is shown, and only its title and problems are drawn again when a field is
-- typed into, so Tab keeps moving between fields.
local Editor = {}

local WIDTH, HEIGHT, MIN_WIDTH, MIN_HEIGHT = 1050, 780, 820, 520
local LABEL_WIDTH = 100

local function M(name) return ns.modules[name] end
local function Client() return M("Client") end
local function Draft() return M("GuideDraft") end
local function Steps() return M("Steps") end

local function trim(text) return (tostring(text or ""):match("^%s*(.-)%s*$")) end

-- Step types --------------------------------------------------------------------------------

-- Every type, in plain words: the caption, the mark the outline shows, its
-- colour, and one line on what it is for. `common` puts it on the Add step
-- menu's first level.
local TYPES = {
    { key = "accept", caption = "Accept", glyph = "!", color = "quest", common = true, group = "Quests",
        desc = "Take quests from an NPC, or from an item" },
    { key = "turnin", caption = "Turn in", glyph = "?", color = "quest", common = true, group = "Quests",
        desc = "Hand quests in" },
    { key = "talk", caption = "Talk", glyph = "T", color = "quest", common = true, group = "Quests",
        desc = "Turn in and accept at one NPC, or speak to them for a quest" },
    { key = "escort", caption = "Escort", glyph = "E", color = "quest", group = "Quests",
        desc = "Walk an NPC to the end of their quest" },
    { key = "kill", caption = "Kill", glyph = "K", color = "danger", common = true, group = "Out in the world",
        desc = "Kill these creatures, for a quest or because they are in the way" },
    { key = "collect", caption = "Collect", glyph = "C", color = "gain", common = true, group = "Out in the world",
        desc = "Loot an item: from creatures, from the ground, for a quest" },
    { key = "interact", caption = "Click", glyph = "I", color = "accent", group = "Out in the world",
        desc = "Use an object in the world: a campfire, a chest, a lever" },
    { key = "travel", caption = "Go to", glyph = "G", color = "accent", common = true, group = "Out in the world",
        desc = "Reach a spot, an area, a zone or a dungeon" },
    { key = "level", caption = "Level", glyph = "L", color = "accent", group = "Out in the world",
        desc = "Grind until a level; the guide waits" },
    { key = "hearth", caption = "Hearth", glyph = "H", color = "accent", group = "Getting around",
        desc = "Set the hearthstone at an inn" },
    { key = "flight", caption = "Flight", glyph = "F", color = "accent", group = "Getting around",
        desc = "Learn a flight point" },
    { key = "train", caption = "Train", glyph = "T", color = "estimate", group = "Training and professions",
        desc = "Learn a profession, or its next rank" },
    { key = "learn", caption = "Learn spells", glyph = "S", color = "estimate", group = "Training and professions",
        desc = "Class spells from a trainer" },
    { key = "gather", caption = "Gather", glyph = "P", color = "gain", group = "Training and professions",
        desc = "Mine, pick or skin a number of an item" },
    { key = "craft", caption = "Craft", glyph = "M", color = "estimate", group = "Training and professions",
        desc = "Make a number of one item" },
    { key = "skillup", caption = "Skill-up", glyph = "U", color = "estimate", group = "Training and professions",
        desc = "Make one item until a rank lands" },
    { key = "skill", caption = "Skill rank", glyph = "R", color = "estimate", group = "Training and professions",
        desc = "Raise a skill to a rank, any way" },
    { key = "cast", caption = "Cast", glyph = "X", color = "estimate", group = "Training and professions",
        desc = "Cast a spell here, once or more" },
    { key = "buy", caption = "Buy", glyph = "B", color = "warning", group = "Shopping and gear",
        desc = "A number of an item from a vendor" },
    { key = "vendor", caption = "Sell, repair", glyph = "V", color = "warning", group = "Shopping and gear",
        desc = "Visit a vendor to sell junk or repair" },
    { key = "equip", caption = "Equip", glyph = "Q", color = "warning", group = "Shopping and gear",
        desc = "Wear an item" },
    { key = "note", caption = "Note", glyph = "i", color = "muted", common = true, group = "Guide flow",
        desc = "Something to read; done when clicked" },
    { key = "choice", caption = "Choice", glyph = "Y", color = "muted", group = "Guide flow",
        desc = "The player picks a route" },
    { key = "reputation", caption = "Reputation", glyph = "N", color = "muted", group = "Guide flow",
        desc = "Reach a standing with a faction" },
    { key = "finish", caption = "Finish", glyph = ".", color = "muted", group = "Guide flow",
        desc = "The last words of the guide" },
}
local TYPE = {}
for _, info in ipairs(TYPES) do TYPE[info.key] = info end
Editor.types = TYPES

-- The client's own pictures for each type, the ones the tracker shows.
local ICONS = {
    accept = "Interface/GossipFrame/AvailableQuestIcon", turnin = "Interface/GossipFrame/ActiveQuestIcon",
    talk = "Interface/GossipFrame/ChatBubbleGossipIcon", escort = "Interface/GossipFrame/IncompleteQuestIcon",
    kill = "Interface/TargetingFrame/UI-RaidTargetingIcon_8", collect = "Interface/GroupFrame/UI-Group-MasterLooter",
    interact = "Interface/Cursor/Interact", cast = "Interface/Cursor/Interact",
    travel = "Interface/AddOns/NuuRoad/Art/WaypointArrow.tga", level = "Interface/Buttons/Arrow-Up-Up",
    hearth = "Interface/Minimap/Tracking/Innkeeper", flight = "Interface/Minimap/Tracking/FlightMaster",
    train = "Interface/Minimap/Tracking/Class", learn = "Interface/Minimap/Tracking/Class",
    gather = "Interface/Minimap/Tracking/Profession", craft = "Interface/Minimap/Tracking/Profession",
    skillup = "Interface/Minimap/Tracking/Profession", skill = "Interface/Minimap/Tracking/Profession",
    buy = "Interface/MoneyFrame/UI-GoldIcon", vendor = "Interface/MoneyFrame/UI-GoldIcon",
    note = "Interface/Buttons/UI-GuildButton-PublicNote-Up", finish = "Interface/RaidFrame/ReadyCheck-Ready",
}
local function typeIcon(kind) return ICONS[kind] end
Editor.TypeIcon = typeIcon

-- What each type's page asks for, in order. Every page ends with the note,
-- who sees the step, and More options.
local FORMS = {
    accept = { { "npc" }, { "quests", key = "quests", label = "Quests" } },
    turnin = { { "npc" }, { "quests", key = "quests", label = "Quests" } },
    talk = { { "npc" }, { "quests", key = "turnin", label = "Turn in" }, { "quests", key = "accept", label = "Accept" },
        { "quest", label = "For quest" } },
    escort = { { "npc", label = "Escort" }, { "quest", label = "Quest", whole = true }, { "where", label = "Ends at" } },
    collect = { { "item", key = "item", label = "Item" }, { "number", key = "count", label = "How many",
        hint = "empty: what the quest asks for" }, { "creatures", key = "kill", label = "Drops from" },
        { "quest", label = "For quest" }, { "where" } },
    kill = { { "creatures", key = "kill", label = "Creatures" }, { "quest", label = "For quest" }, { "where" } },
    interact = { { "text", key = "object", label = "What to click", placeholder = "Campfire" },
        { "quest", label = "For quest" }, { "where" } },
    travel = { { "text", key = "to", label = "Going to", placeholder = "Brill" }, { "where" },
        { "area", key = "area", label = "Done on entering", optional = true } },
    gather = { { "item", key = "item", label = "Item" }, { "number", key = "count", label = "How many" },
        { "skill", key = "skill", label = "Profession", optional = true } },
    craft = { { "item", key = "item", label = "Item" }, { "number", key = "count", label = "How many" },
        { "skill", key = "skill", label = "Profession", optional = true } },
    skillup = { { "item", key = "item", label = "Item" }, { "skill", key = "skill", label = "Profession" },
        { "number", key = "rank", label = "Until rank" } },
    buy = { { "item", key = "item", label = "Item" }, { "number", key = "count", label = "How many" },
        { "npc", label = "From" } },
    vendor = { { "npc", label = "Who" }, { "toggles", { "sell", "Sell junk" }, { "repair", "Repair" } } },
    equip = { { "item", key = "item", label = "Item" } },
    train = { { "skill", key = "skill", label = "Profession" }, { "number", key = "rank", label = "Rank",
        hint = "empty: learn it at all" }, { "npc", label = "Trainer" } },
    learn = { { "spells", key = "spells", label = "Spells" }, { "npc", label = "Trainer" } },
    cast = { { "spell", key = "spell", label = "Spell" }, { "number", key = "count", label = "Times" }, { "where" } },
    skill = { { "skill", key = "skill", label = "Profession" }, { "number", key = "rank", label = "Rank" } },
    reputation = { { "faction" }, { "standing" } },
    hearth = { { "area", key = "area", label = "Inn" }, { "npc", label = "Innkeeper" } },
    flight = { { "node" }, { "npc", label = "Flight master" } },
    level = { { "number", key = "level", label = "Level" }, { "number", key = "xp", label = "XP into it",
        hint = "or a step below" }, { "steppick", key = "by", label = "Needed by",
        hint = "the turn-ins before that step count" }, { "where", label = "Grind at" } },
    choice = { { "text", key = "text", label = "Question", placeholder = "Which way?" }, { "options" } },
    note = {}, finish = { { "nextguide" } },
}

-- What each kind of link a shift-click sends names.
local LINK = {
    item = "|Hitem:(%d+)", quest = "|Hquest:(%d+)", spell = "|Hspell:(%d+)",
}

-- Small helpers --------------------------------------------------------------------------------

local function list(value)
    if value == nil then return {} end
    if type(value) == "table" then return value end
    return { value }
end

local function GuideDraftCopy(value) return Draft().Copy(value) end

local function copyList(value)
    local out = {}
    for _, id in ipairs(list(value)) do out[#out + 1] = id end
    return out
end

local function parseIDs(text)
    local ids = {}
    for token in tostring(text or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(token) end
    return ids
end

local function questName(id)
    local Names = M("Names")
    local name = Names and Names:Quest(id)
    return name or ("Quest " .. id)
end

local function itemName(id)
    local client = Client()
    local name = client and client.GetItemName and client:GetItemName(id)
    if not name then
        local Names = M("Names")
        name = Names and Names.Item and Names:Item(id)
    end
    return name or ("Item " .. id)
end

local function spellName(id)
    local client = Client()
    local name = client and client.GetSpellName and client:GetSpellName(id)
    return name or ("Spell " .. id)
end

local function idNames(kind)
    return ns.idNames and ns.idNames[kind] or {}
end

local function sortedOptions(names, extra)
    local options = {}
    for id, name in pairs(names) do options[#options + 1] = { value = id, caption = name } end
    if extra then
        for _, option in ipairs(extra) do options[#options + 1] = option end
    end
    table.sort(options, function(a, b) return tostring(a.caption) < tostring(b.caption) end)
    return options
end

-- Where the player stands, as a v1 point (hundredths of a percent), and the
-- map it is on. Nil off any map.
local function whereIStand()
    local client = Client()
    local map = client and client:GetCurrentMapID()
    local x, y = nil, nil
    if map then x, y = client:GetPlayerMapPosition(map) end
    if not (map and x and y) then return nil end
    return { math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5) }, map
end

-- The player's target, when it is a creature: its ID and name.
local function myTarget()
    local client = Client()
    if not client then return nil end
    local id = client:GetUnitCreatureID("target")
    if not id then return nil end
    return id, client:GetUnitName("target")
end

Editor.WhereIStand, Editor.MyTarget, Editor.QuestName = whereIStand, myTarget, questName

-- Window ---------------------------------------------------------------------------------------

local function ui() return ns:GetUI() end

local function windowHidden()
    ui():HideTooltip()
    Editor:SyncPlaces()
end

-- Button callbacks, one per control, so no control holds a closure of its own.
local function undoClicked() Editor:Undo() end
local function redoClicked() Editor:Redo() end
local function playClicked() Editor:PlayFromStep() end
local function guideMenuClicked(button) Editor:OpenGuideMenu(button) end
local function addStepClicked(button) Editor:OpenAddMenu(button) end
local function addSectionClicked() Editor:AddSection() end
local function outlinePicked(item) Editor:OutlinePicked(item) end
local function outlineRightClick(item) Editor:OutlineMenu(item) end
local function filterChanged(value) Editor:SetFilter(value) end
local function searchTyped(text) Editor:SetSearch(text) end

local function outlineMake(row)
    row.caret = row:Text{ "", width = 10, color = "muted" }
    row.num = row:Text{ "", style = "number", width = 24, justify = "RIGHT", color = "muted" }
    row.glyph = row:Icon{ "", size = 16 }
    row.title = row:Text{ "", grow = true }
    row.tag = row:Tag{ "" }
    row.range = row:Text{ "", style = "number", color = "muted" }
    row.flag = row:Text{ "", width = 10, justify = "CENTER" }
end

local function outlineDraw(row, item)
    Editor:DrawOutlineRow(row, item)
end

local function outlineTooltip(item)
    return Editor:OutlineTooltip(item)
end

function Editor:Build()
    if self.win then return end
    local db = ns.db
    local places = db and db.windows
    if not places then
        places = {}
        if db then db.windows = places end
    end
    self.places = places
    local win = ui():Window({
        key = "editor", title = "Guide editor", width = WIDTH, height = HEIGHT,
        resizable = true, minWidth = MIN_WIDTH, minHeight = MIN_HEIGHT, place = places,
        status = true, hidden = true,
    })
    win:HookScript("OnHide", windowHidden)
    self.win, self.frame = win, win

    local header = win.header
    header:Spacer{}
    self.undoButton = header:GlyphButton{ "undo", boxed = true, bright = true, size = 26, onClick = undoClicked,
        tooltip = "Undo: take back the last change (Ctrl-Z)" }
    self.redoButton = header:GlyphButton{ "redo", boxed = true, bright = true, size = 26, onClick = redoClicked,
        tooltip = "Redo: make the change you took back again (Ctrl-Y)" }
    header:Spacer{ size = 6 }
    header:Button{ "Play from this step", glyph = "play", iconSize = 10, onClick = playClicked,
        tooltip = "Follow this guide in the tracker, from the selected step" }
    header:Button{ "Guide", chevron = true, onClick = guideMenuClicked,
        tooltip = "Settings, history, caves and tunnels, the guide as text" }

    local panes = win:SplitPanes{
        { key = "outline", width = 320, min = 240 },
        { key = "page", grow = true, min = 420 },
        place = places, key = "editor.panes",
    }

    local outline = panes.outline
    local top = outline:Row{ gap = 6 }
    self.search = top:Search{ grow = true, placeholder = "Find a step, quest or NPC", onType = searchTyped }
    local filter = outline:Row{ gap = 6, valign = "center" }
    filter:Text{ "Showing" }
    local filterOptions = { { value = "all", caption = "every class" } }
    for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
        filterOptions[#filterOptions + 1] = { value = class, caption = class:sub(1, 1) .. class:sub(2):lower() .. "s" }
    end
    self.filter = filter:Select{ boxWidth = 140, options = filterOptions, value = "all", onChange = filterChanged }
    self.outline = outline:List{ grow = true, rowHeight = 22, make = outlineMake, draw = outlineDraw,
        onPick = outlinePicked, onRightClick = outlineRightClick, tooltip = outlineTooltip, empty = "No steps match." }
    local buttons = outline:Row{ gap = 6 }
    buttons:Button{ "Add step", tone = "accent", grow = true, onClick = addStepClicked,
        tooltip = "A new step after the selected one" }
    buttons:Button{ "Add section", onClick = addSectionClicked, tooltip = "A new section at the end of the guide" }

    local page = panes.page
    self.pageArea = page:ScrollArea{ grow = true, gap = 12, padding = 4 }
    self.pageBody = self.pageArea:Column{ gap = 12 }

    self:HookLinks()
    self:HookKeys()
end

-- Ctrl-Z and Ctrl-Y while the editor is shown and no field has the keyboard.
-- Every other key goes on to the game, so the editor never stops a keybind;
-- in combat, when the client keeps that to itself, nothing is caught.
local function keyDown(frame, key)
    local editor = Editor
    local propagate = frame.SetPropagateKeyboardInput
    local control = rawget(_G, "IsControlKeyDown")
    local combat = rawget(_G, "InCombatLockdown")
    local focus = rawget(_G, "GetCurrentKeyBoardFocus")
    local mine = (key == "Z" or key == "Y") and type(control) == "function" and control()
        and not (type(focus) == "function" and focus()) and editor:IsShown()
    if type(combat) == "function" and combat() then return end
    if mine then
        if key == "Z" then editor:Undo() else editor:Redo() end
    end
    if propagate then pcall(propagate, frame, not mine) end
end

function Editor:HookKeys()
    if self.keys or not CreateFrame then return end
    local frame = CreateFrame("Frame", nil, self.win)
    if not (frame.EnableKeyboard and frame.SetPropagateKeyboardInput) then return end
    frame:EnableKeyboard(true)
    pcall(frame.SetPropagateKeyboardInput, frame, true)
    frame:SetScript("OnKeyDown", keyDown)
    self.keys = frame
end

-- Status ---------------------------------------------------------------------------------------

function Editor:SetStatus(text, isError)
    if not self.win then return end
    self.statusOpts = self.statusOpts or {}
    self.statusOpts.tone = isError and "danger" or "text"
    self.win:Status(text ~= "" and text or nil, self.statusOpts)
    -- The Places panel and the recorder report here after changing places.
    self:SyncPlaces()
end

function Editor:Problem(text)
    self:SetStatus(text, true)
end

-- Opening ----------------------------------------------------------------------------------------

function Editor:Show()
    self:Build()
    self.win:Show()
    if self.draft then self:RenderAll() end
end

function Editor:Hide()
    if self.win then self.win:Hide() end
end

function Editor:IsShown()
    return self.win ~= nil and self.win:IsShown() or false
end

function Editor:Toggle()
    if self:IsShown() then return self:Hide() end
    if self.draft then return self:Show() end
    return self:OpenNew()
end

local function draftChanged(draft, what) Editor:DraftChanged(draft, what) end

function Editor:Attach(draft, position)
    self.draft = draft
    draft.openedValue = draft.openedValue or draft:Value()
    draft.onChanged = draftChanged
    self.step = draft:StepAt(position or 1) or draft:StepAt(1)
    self.position = draft:EntryOf(self.step).position
    self.selection, self.anchor = { [self.step] = true }, self.step
    self.collapsed = {}
    local Places = M("PlacesPanel")
    if Places and Places.Reset then Places:Reset() end
    self.working = nil
end

-- Opens a guide: one of the player's as itself, a packaged or session guide
-- as a draft that becomes the player's own copy at its first change.
function Editor:OpenGuide(guide, opts)
    if not guide then return self:OpenNew() end
    opts = opts or {}
    self:Build()
    local Repository = M("GuideRepository")
    local source = Repository:Source(guide.id)
    if not source then
        self.win:Show()
        self:Problem("This guide was kept by an older version of the editor: it plays, but cannot be edited.")
        return
    end
    local mine = Repository:IsUserGuide(guide.id)
    local draft = Draft():Open(source, { copyOf = not mine and guide.id or nil })
    local Progress = M("Progress")
    local state = Progress and Progress:PeekState(guide)
    local position = state and state.currentStep or 1
    -- The tracker's step is a runtime position; the draft's first build
    -- says which step stands there.
    local step = draft.builtFrom and draft.builtFrom[position]
    self:Attach(draft, step and draft:EntryOf(step).position or 1)
    if opts.hidden then return draft end
    self.win:Show()
    self:RenderAll()
    self:SetStatus(mine and "Every change is kept as you make it. Ctrl-Z undoes; Guide, History goes further back."
        or "A packaged guide: your first change makes it a copy of your own. The original stays as it is.")
    return draft
end

-- The draft of `guide`, opened without showing the editor when it is not
-- the one already open: what the adding panel and the tracker's fixes work on.
function Editor:DraftFor(guide)
    if not guide then return nil end
    local draft = self.draft
    if draft and (draft.guide.id == guide.id or draft.copyOf == guide.id) then return draft end
    local Repository = M("GuideRepository")
    if not Repository:Source(guide.id) then return nil end
    return self:OpenGuide(guide, { hidden = not self:IsShown() })
end

-- The draft's step at a runtime position of `guide` (a tracker step).
function Editor:StepOf(guide, index)
    local draft = self:DraftFor(guide)
    if not draft then return nil end
    return draft.builtFrom and draft.builtFrom[index], draft
end

-- Opens the editor on a tracker step.
function Editor:EditStep(guide, index)
    local step, draft = self:StepOf(guide, index)
    if not draft then return self:OpenGuide(guide) end
    self:Show()
    if step then self:Select(step) end
end

-- The tracker's "The NPC is here": the player's target (or the step's own
-- NPC) stands where the player is. Answers what was done, for the tracker.
function Editor:NPCIsHere(guide, index)
    local step, draft = self:StepOf(guide, index)
    if not step then return nil, "This step cannot be changed here." end
    local at, map = whereIStand()
    if not at then return nil, "Your position cannot be read here." end
    local id, name = myTarget()
    id = id or (type(step.npc) == "table" and step.npc[1]) or step.npc
    if not id then return nil, "Target the NPC first." end
    local ok, problem = self:Hard(draft.SetNPC, draft, step, id, name, map, at)
    if ok == false then return nil, problem end
    return (draft:NPCName(id) or ("NPC " .. id)) .. " now stands where you are."
end

-- The tracker's "Move the spot to me": the step's spot (or its NPC's,
-- for a visit with no spot of its own) is where the player stands.
function Editor:SpotIsHere(guide, index)
    local step, draft = self:StepOf(guide, index)
    if not step then return nil, "This step cannot be changed here." end
    local at, map = whereIStand()
    if not at then return nil, "Your position cannot be read here." end
    local npc = type(step.npc) == "table" and step.npc[1] or step.npc
    local ok, problem
    if not step.at and not step.stand and npc then
        ok, problem = self:Hard(draft.Change, draft, "where", function() draft:KeepNPC(npc, nil, map, at) end)
    else
        local entry = draft:EntryOf(step)
        if map ~= (draft:Sections()[entry.section].map or draft.guide.data.map) then at.map = map end
        ok, problem = self:Hard(draft.SetFields, draft, step, { at = { at }, stand = false }, "where")
    end
    if ok == false then return nil, problem end
    return "The step's spot is where you stand."
end

-- A new guide, named first: kept on the account at once.
-- A new guide: named, filed under Personal, and kept on the account at
-- once. The dialog says how to write one the quick way: by playing it.
function Editor:OpenNew()
    self:Build()
    local win = self.newWin
    if not win then
        win = ui():Window({ key = "editorNew", title = "New guide", width = 500, height = 380, place = self.places, hidden = true })
        local body = win:Column{ gap = 12, padding = 16 }
        win.name = body:Input{ label = "Name", onChange = function() end }
        win.filed = body:Text{ "", style = "fine", color = "muted", wrap = true }
        body:Rule{}
        body:Text{ "The quickest way: play it once", style = "label" }
        local steps = {
            "Walk up to the first NPC and target them.",
            "Press what you do there: Accept, Turn in, Kill, Go here. The step is filled in from your target, where you stand and the quest window.",
            "Keep playing. Fix wording and order later in the full editor.",
        }
        for index, text in ipairs(steps) do
            local row = body:Row{ gap = 10, valign = "top" }
            row:Tag{ tostring(index), tone = "accent", width = 22 }
            row:Text{ text, wrap = true, grow = true }
        end
        body:Spacer{}
        local buttons = body:Row{ gap = 8 }
        buttons:Spacer{}
        buttons:Button{ "Open the full editor", onClick = function() win:Hide() self:CreateNew(trim(win.name:GetText()), false) end }
        buttons:Button{ "Start adding while I play", tone = "accent",
            onClick = function() win:Hide() self:CreateNew(trim(win.name:GetText()), true) end }
        self.newWin = win
    end
    local client = Client()
    local zone = client and client:GetZoneName()
    win.name:SetText(zone and (zone .. " guide") or "My guide")
    win.filed:SetText("Filed under Personal" .. (zone and (", for " .. zone .. ", where you are now") or "") .. ". Change either later.")
    win:Show()
    if win.name.box then win.name.box:SetFocus() end
end

function Editor:CreateNew(name, adding)
    local client = Client()
    local map = client and client:GetCurrentMapID()
    local draft = Draft():New(name ~= "" and name or "My guide", map)
    M("GuideRepository"):SaveDraft(draft)
    self:Attach(draft, 1)
    local Panel = M("AddingPanel")
    if adding and Panel then return Panel:Open(draft) end
    self.win:Show()
    self:RenderAll()
    self:SetStatus("Every change is kept as you make it. Ctrl-Z undoes; Guide, History goes further back.")
end

-- Changes ------------------------------------------------------------------------------------------

-- Every change the draft takes: kept on the account, the tracker told, and
-- the editor drawn again. A field typed into redraws only what it changed,
-- so the field the player tabs into stays.
function Editor:DraftChanged(draft, what)
    if draft ~= self.draft then return end
    local Repository = M("GuideRepository")
    local oldSteps = draft.builtSteps
    local old, new = Repository:SaveDraft(draft)
    if old and new then
        local Progress = M("Progress")
        if Progress and Progress.Rebuilt then Progress:Rebuilt(old, new, draft:Map(oldSteps)) end
        local Route = M("TravelRoute")
        if Route and Route.ForgetPlaces and what == "places" then Route:ForgetPlaces() end
    end
    draft.builtSteps = draft.builtFrom or oldSteps
    self:KeepHistory(draft, what)
    local Main = M("MainWindow")
    if Main and Main.RequestRefresh then Main:RequestRefresh() end
    if not self.win then return end
    -- A change that replaced the guide's tables (undo, text) leaves the
    -- selection on the step at the same place.
    if not draft:EntryOf(self.step) then
        self.step = draft:StepAt(math.min(self.position or 1, draft:Count())) or draft:StepAt(1)
        self.soft = false
    end
    self.position = draft:EntryOf(self.step).position
    -- Steps gone (deleted, or replaced by an undo) leave the selection.
    local kept = {}
    for step in pairs(self.selection or {}) do
        if draft:EntryOf(step) then kept[step] = true end
    end
    kept[self.step] = true
    self.selection = kept
    if self.soft then
        self:RenderOutline()
        self:RenderHeader()
        self:RenderPageState()
    else
        self:RenderAll()
    end
end

-- Runs a draft change from a field: a soft redraw.
function Editor:Soft(change, ...)
    self.soft = true
    local ok, problem = change(...)
    self.soft = false
    if ok == false and problem then self:Problem(problem) end
    return ok, problem
end

-- Runs a draft change from a button or menu: the page is built again.
function Editor:Hard(change, ...)
    self.soft = false
    local ok, problem = change(...)
    if ok == false and problem then self:Problem(problem) end
    return ok, problem
end

function Editor:Undo()
    if not self.draft then return end
    local what = self.draft:Undo()
    self:SetStatus(what and ("Undone: " .. what .. ".") or "Nothing to undo.")
end

function Editor:Redo()
    if not self.draft then return end
    local what = self.draft:Redo()
    self:SetStatus(what and ("Done again: " .. what .. ".") or "Nothing to redo.")
end

function Editor:Select(step, keepSelection)
    if not self.draft or not step or not self.draft:EntryOf(step) then return end
    if not keepSelection then self.selection, self.anchor = { [step] = true }, step end
    self.step = step
    self.position = self.draft:EntryOf(step).position
    -- A collapsed section opens to show its selected step.
    self.collapsed[self.draft:EntryOf(step).section] = nil
    self:RenderOutline()
    self:RenderPage()
end

function Editor:SelectPosition(position)
    if self.draft then self:Select(self.draft:StepAt(position)) end
end

-- Drawing ----------------------------------------------------------------------------------------

function Editor:RenderAll()
    if not (self.win and self.draft) then return end
    self:RenderHeader()
    self:RenderOutline()
    self:RenderPage()
end

function Editor:RenderHeader()
    local draft = self.draft
    local guide = draft.guide
    self.win:SetTitle(guide.title or "Guide")
    local count = draft:ProblemCount()
    local state
    if draft.copyOf then
        state = "packaged guide"
    elseif count > 0 then
        state = count == 1 and "1 problem" or (count .. " problems")
    else
        state = "saved"
    end
    self.win:SetSubtitle(state)
    self.undoButton:SetEnabled(draft:CanUndo(), "Nothing to undo")
    self.redoButton:SetEnabled(draft:CanRedo(), "Nothing to redo")
end

-- The runtime node a step was built into, and its position there, or nil
-- while it has a problem. The lookup is made once per version of the draft.
function Editor:NodeOf(step)
    local draft = self.draft
    if self.indexVersion ~= draft.version or self.indexDraft ~= draft then
        local index = {}
        for at, from in ipairs(draft.builtFrom or {}) do index[from] = at end
        self.builtIndex, self.indexVersion, self.indexDraft = index, draft.version, draft
    end
    local at = self.builtIndex[step]
    if not at then return nil end
    return draft.built.nodes[at], at
end

-- What the step says, in one line: the title the tracker shows, or for a
-- step that cannot be built yet, its type and what it names.
function Editor:TitleOf(step)
    local node = self:NodeOf(step)
    if node then
        local title = Steps():Title(node, true)
        if title and title ~= "" then
            if step.type == "note" and #title > 70 then title = title:sub(1, 67) .. "..." end
            return title
        end
    end
    local info = TYPE[step.type]
    return (info and info.caption or tostring(step.type)) .. (step.type == "note" and (step.note and (": " .. step.note) or "") or "")
end

-- Who the step is for, in a word or two, for the outline's tag.
local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

local function whoTag(step)
    local cond = step.cond
    if type(cond) ~= "table" then return step.show and "some" or "" end
    local classes = cond.class
    if type(classes) == "string" then return CLASS_NAMES[classes] or classes end
    if type(classes) == "table" then
        if #classes == 1 then return CLASS_NAMES[classes[1]] or classes[1] end
        return #classes .. " classes"
    end
    if cond.race then return type(cond.race) == "table" and (#cond.race .. " races") or tostring(cond.race) end
    return "some"
end

-- Whether a class sees the step, by what its own, its group's and its
-- section's `cond` say about classes (the outline's Showing filter).
local function classSees(cond, class)
    if type(cond) ~= "table" then return true end
    local classes = cond.class
    if classes == nil then return true end
    for _, value in ipairs(list(classes)) do
        if value == class then return true end
    end
    return false
end

function Editor:SetFilter(value)
    self.filterClass = value ~= "all" and value or nil
    self:RenderOutline()
end

function Editor:SetSearch(text)
    self.searchText = trim(text):lower()
    self:RenderOutline()
end

function Editor:Matches(entry)
    local step = entry.step
    if self.filterClass then
        local section = self.draft:Sections()[entry.section]
        if not (classSees(step.cond, self.filterClass) and classSees(entry.group and entry.group.cond, self.filterClass)
            and classSees(section and section.cond, self.filterClass)) then
            return false
        end
    end
    local text = self.searchText
    if text and text ~= "" then
        local hay = (self:TitleOf(step) .. " " .. tostring(step.note or "")):lower()
        if not hay:find(text, 1, true) then
            local found = false
            for _, key in ipairs({ "quests", "turnin", "accept", "npc", "kill", "item" }) do
                for _, id in ipairs(list(step[key])) do
                    if tostring(id) == text then found = true end
                end
            end
            if not found then return false end
        end
    end
    return true
end

function Editor:RenderOutline()
    local draft = self.draft
    if not (self.win and draft) then return end
    local items, selected = {}, nil
    local entries = draft:Entries()
    local filtering = self.filterClass or (self.searchText and self.searchText ~= "")
    local sectionItem
    for _, entry in ipairs(entries) do
        if not sectionItem or sectionItem.index ~= entry.section then
            sectionItem = { kind = "section", index = entry.section, first = entry.position, last = entry.position }
            items[#items + 1] = sectionItem
        end
        sectionItem.last = entry.position
        if (filtering or not self.collapsed[entry.section]) and self:Matches(entry) then
            local item = { kind = "step", entry = entry, step = entry.step }
            items[#items + 1] = item
            if entry.step == self.step then selected = item end
        end
    end
    self.outlineItems = items
    self.outline:SetItems(items, true)
    self.outline:Select(selected)
    if selected then self.outline:ScrollToItem(selected) end
end

function Editor:DrawOutlineRow(row, item)
    local draft = self.draft
    if item.kind == "section" then
        local section = draft:Sections()[item.index]
        row:SetTint("band")
        row.caret:SetText(self.collapsed[item.index] and ">" or "v")
        row.num:SetShown(false)
        row.glyph:SetShown(false)
        row.tag:SetShown(false)
        row.title:SetStyle("label")
        row.title:SetText(section and section.title or "")
        row.range:SetShown(true)
        row.range:SetText(item.first == item.last and tostring(item.first) or (item.first .. "-" .. item.last))
        row.flag:SetText("")
        return
    end
    local step = item.step
    local info = TYPE[step.type]
    row:SetTint(self.selection and self.selection[step] and step ~= self.step and "accentWash" or nil)
    row.caret:SetText(item.entry.group and "|" or "")
    row.num:SetShown(true)
    row.num:SetText(tostring(item.entry.position))
    row.glyph:SetShown(true)
    row.glyph:SetIcon(typeIcon(step.type), info and info.glyph or "?")
    row.glyph:SetColor(not typeIcon(step.type) and info and info.color or nil)
    row.title:SetStyle("body")
    row.title:SetText(self:TitleOf(step))
    row.range:SetShown(false)
    local who = whoTag(step)
    row.tag:SetShown(who ~= "")
    row.tag:SetText(who)
    local problems = draft:ProblemsOf(step)
    if problems then
        row.flag:SetText("o")
        row.flag:SetColor(problems[1].level == "error" and "danger" or "warning")
    else
        row.flag:SetText("")
    end
end

function Editor:OutlineTooltip(item)
    if item.kind == "section" then
        return function(tip) tip:AddLine("Click to fold or open. Right-click to rename or merge it.") end
    end
    local problems = self.draft:ProblemsOf(item.step)
    if not problems then return nil end
    return function(tip)
        for _, problem in ipairs(problems) do tip:AddLine(problem.text) end
    end
end

local function modifierDown(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn() and true or false
end

-- A click picks one step; Shift-click the steps from the last picked to
-- this one, as the outline shows them; Ctrl-click adds or takes out one.
function Editor:OutlinePicked(item)
    if item.kind == "section" then
        self.collapsed[item.index] = not self.collapsed[item.index] or nil
        self:RenderOutline()
        return
    end
    local step = item.step
    if modifierDown("IsShiftKeyDown") and self.anchor and self.draft:EntryOf(self.anchor) then
        local from, to
        for index, candidate in ipairs(self.outlineItems or {}) do
            if candidate.step == self.anchor then from = index end
            if candidate == item then to = index end
        end
        if from and to then
            if from > to then from, to = to, from end
            local selection = {}
            for index = from, to do
                local candidate = self.outlineItems[index]
                if candidate.kind == "step" then selection[candidate.step] = true end
            end
            self.selection = selection
            return self:Select(step, true)
        end
    elseif modifierDown("IsControlKeyDown") then
        local selection = self.selection or {}
        if selection[step] and step ~= self.step then
            selection[step] = nil
            self.selection = selection
            return self:Select(self.step, true)
        end
        selection[step] = true
        self.selection, self.anchor = selection, step
        return self:Select(step, true)
    end
    self:Select(step)
end

-- The selected steps, in run order.
function Editor:Selected()
    local list = {}
    for step in pairs(self.selection or {}) do list[#list + 1] = step end
    return self.draft and self.draft:Ordered(list) or list
end

-- The step's page -------------------------------------------------------------------------------

-- A row of the page: its label at the left, the controls after it.
function Editor:FieldRow(label, valign)
    local row = self.pageBody:Row{ gap = 10, valign = valign or "center" }
    row:Text{ label or "", width = LABEL_WIDTH }
    return row
end

-- A row inside More options.
function Editor:MoreRow(label)
    local row = self.moreBody:Row{ gap = 10, valign = "center" }
    row:Text{ label or "", width = LABEL_WIDTH }
    return row
end

function Editor:RenderPage()
    local draft, step = self.draft, self.step
    if not (self.win and draft and step) then return end
    local body = self.pageBody
    body:Clear()
    if #self:Selected() > 1 then return self:RenderSelectionPage() end
    self.titleText, self.problemArea, self.moreBody = nil, nil, nil
    -- The page's main controls by field, for the tests, and where a
    -- shift-click goes when no field has the keyboard.
    self.controls, self.linkTargets = {}, {}

    self.problemArea = body:Column{ gap = 6 }

    local head = body:Row{ gap = 12, valign = "center" }
    local info = TYPE[step.type]
    self.controls.type = head:Button{ info and info.caption or tostring(step.type), icon = typeIcon(step.type),
        iconSize = 16, chevron = true, height = 32, textStyle = "label",
        onClick = function(button) self:OpenTypeMenu(button) end, tooltip = "Change what kind of step this is" }
    local titles = head:Column{ gap = 2, grow = true }
    self.titleText = titles:Text{ "", style = "heading", wrap = true }
    titles:Text{ "Made from the fields below.", style = "fine", color = "muted" }

    for _, field in ipairs(FORMS[step.type] or {}) do
        local build = self.fields[field[1]]
        if build then build(self, step, field) end
    end

    self.fields.note(self, step)
    self.fields.shown(self, step)

    body:Rule{}
    local moreRow = body:Row{ gap = 10, valign = "center" }
    local more = body:Column{ gap = 10 }
    self.controls.more = moreRow:Disclosure{ "More options", open = self.moreOpen or false, onToggle = function(open)
        self.moreOpen = open
        more:SetShown(open)
    end }
    moreRow:Spacer{}
    moreRow:Text{ self:MoreSummary(step), style = "fine", color = "muted" }
    more:SetShown(self.moreOpen or false)
    self.moreBody = more
    self:BuildMore(step)

    self:RenderPageState()
end

-- Several steps picked: what can be done to all of them at once.
function Editor:RenderSelectionPage()
    local draft, body = self.draft, self.pageBody
    local steps = self:Selected()
    self.titleText, self.problemArea, self.moreBody = nil, nil, nil
    self.controls, self.linkTargets = {}, {}
    body:Text{ #steps .. " steps selected", style = "heading" }
    body:Text{ "Shift-click picks the steps between, Ctrl-click one more or one less; a plain click picks one again.",
        style = "fine", color = "muted", wrap = true }
    local shown = math.min(#steps, 8)
    for index = 1, shown do
        local step = steps[index]
        local info = TYPE[step.type]
        local row = body:Row{ gap = 8, valign = "center" }
        row:Text{ tostring(draft:EntryOf(step).position), style = "number", color = "muted", width = 28, justify = "RIGHT" }
        row:Icon{ typeIcon(step.type), fallback = info and info.glyph or "?", color = not typeIcon(step.type) and info and info.color or nil }
        row:Text{ self:TitleOf(step), grow = true }
    end
    if #steps > shown then body:Text{ "and " .. (#steps - shown) .. " more", style = "fine", color = "muted" } end
    body:Rule{}
    local function act(change, ...)
        local ok = self:Hard(change, ...)
        if ok ~= false then self:RenderAll() end
    end
    local first = body:Row{ gap = 6 }
    self.controls.group = first:Button{ "Group them", tooltip = "Quest visits and objectives done together, in any order",
        onClick = function() act(draft.GroupSteps, draft, steps) end }
    self.controls.ungroup = first:Button{ "Take out of groups", onClick = function() act(draft.UngroupMany, draft, steps) end }
    self.controls.duplicate = first:Button{ "Duplicate", onClick = function()
        local twins = self:Hard(function() return draft:DuplicateMany(steps) end)
        if twins then
            local selection = {}
            for _, twin in ipairs(twins) do selection[twin] = true end
            self.selection, self.step, self.anchor = selection, twins[1], twins[1]
            self:RenderAll()
        end
    end }
    local second = body:Row{ gap = 6 }
    self.controls.up = second:Button{ "Move up", glyph = "up", iconSize = 10, onClick = function() act(draft.MoveMany, draft, steps, -1) end }
    self.controls.down = second:Button{ "Move down", glyph = "down", iconSize = 10, onClick = function() act(draft.MoveMany, draft, steps, 1) end }
    second:Button{ "Move to section", chevron = true, onClick = function(button)
        local items = {}
        for index, section in ipairs(draft:Sections()) do
            items[#items + 1] = { caption = section.title, onClick = function() act(draft.MoveManyToSection, draft, steps, index) end }
        end
        ui():OpenMenu(items, { anchor = button })
    end }
    local third = body:Row{ gap = 6 }
    self.controls.shown = third:Button{ "Shown to", onClick = function() self:OpenShownTo(steps[1], steps) end,
        tooltip = "Who sees them: set for all of them at once" }
    third:Spacer{}
    self.controls.delete = third:ConfirmButton{ "Delete " .. #steps .. " steps", tone = "danger", style = "soft",
        onConfirm = function() act(draft.DeleteMany, draft, steps) end }
end

-- What the soft redraw touches: the title and the problems.
function Editor:RenderPageState()
    local draft, step = self.draft, self.step
    if not (self.titleText and self.problemArea) then return end
    self.titleText:SetText(self:TitleOf(step))
    local area = self.problemArea
    area:Clear()
    for _, problem in ipairs(draft:ProblemsOf(step) or {}) do
        local action
        if problem.fix then
            action = { caption = problem.fix.caption, button = true, onClick = function() self:Hard(problem.fix.apply, draft, step) end }
        elseif problem.npcPosition then
            action = { caption = "Use my target", button = true, onClick = function() self:UseTarget(step) end }
        end
        area:Notice{ problem.text, tone = problem.level == "error" and "danger" or "warning", action = action }
    end
    for _, text in ipairs(draft.guideProblems or {}) do
        area:Notice{ "The guide: " .. text, tone = "danger" }
    end
end

-- Fields ------------------------------------------------------------------------------------------

Editor.fields = {}
local F = Editor.fields

-- A chip: what a list holds, on a plate of its kind's colour, with what
-- else is worth knowing beside it and a mark to take it out.
local function initialsOf(name)
    local out = ""
    for word in tostring(name or ""):gmatch("%a+") do
        if #out < 2 then out = out .. word:sub(1, 1):upper() end
    end
    return out ~= "" and out or "?"
end

local function chip(row, caption, tooltip, onRemove, tone, hint, icon)
    return row:Chip{ caption, tone = tone or "accent", tooltip = tooltip, hint = hint, onRemove = onRemove,
        icon = icon, initials = not icon and initialsOf(caption) or nil }
end

local function itemIcon(id)
    local client = Client()
    return client and client.GetItemIcon and client:GetItemIcon(id) or nil
end

local function spellIcon(id)
    local client = Client()
    return client and client.GetSpellIcon and client:GetSpellIcon(id) or nil
end

local function without(values, index)
    local out = copyList(values)
    table.remove(out, index)
    return out
end

local function appended(values, ids)
    local out, seen = copyList(values), {}
    for _, id in ipairs(out) do seen[id] = true end
    for _, id in ipairs(ids) do
        if not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
    return out
end

-- An input that also takes a shift-clicked link of `kind`.
function Editor:LinkInput(row, kind, placeholder, onIDs, width)
    return row:Input{ width = width or 130, placeholder = placeholder or "ID, or shift-click",
        data = { link = kind, onIDs = onIDs },
        onChange = function(text)
            local ids = parseIDs(text)
            if #ids > 0 then onIDs(ids) end
        end }
end

-- The step's NPC: one, named from the guide or the client.
F.npc = function(self, step, field)
    local draft = self.draft
    local row = self:FieldRow(field.label or "Who")
    for index, id in ipairs(list(step.npc)) do
        local entry, map = draft:NPC(id)
        local hint
        if type(entry) == "table" and entry.at and type(entry.at[1]) == "number" then
            local client = Client()
            local mapName = client and client.GetMapName and client:GetMapName(map) or nil
            hint = (mapName and (mapName .. " ") or "") .. string.format("%.1f, %.1f", entry.at[1] / 100, entry.at[2] / 100)
        end
        chip(row, draft:NPCName(id) or ("NPC " .. id), "NPC " .. id, function()
            self:Hard(draft.SetField, draft, step, "npc", without(step.npc, index), "npc")
        end, "accent", hint)
    end
    self.controls.useTarget = row:Button{ "Use my target", onClick = function() self:UseTarget(step) end,
        tooltip = "The creature you have targeted, and where you stand as where it is" }
    row:Button{ "Choose", style = "ghost", onClick = function(button) self:OpenNPCMenu(button, step) end,
        tooltip = "An NPC this guide already names" }
end

function Editor:UseTarget(step)
    local id, name = myTarget()
    if not id then return self:Problem("Target the NPC first.") end
    local at, map = whereIStand()
    self:Hard(self.draft.SetNPC, self.draft, step, id, name, map, at)
    self:SetStatus((name or ("NPC " .. id)) .. " is this step's NPC" .. (at and ", standing where you are." or "."))
end

function Editor:OpenNPCMenu(anchor, step)
    local draft, items, seen = self.draft, { { header = "NPCs in this guide" } }, {}
    for _, byMap in pairs(draft.guide.data.npcs or {}) do
        for id, entry in pairs(byMap) do
            if not seen[id] then
                seen[id] = true
                local name = type(entry) == "table" and entry.name or entry
                items[#items + 1] = { caption = tostring(name), desc = "NPC " .. id,
                    onClick = function() self:Hard(draft.SetField, draft, step, "npc", { id }, "npc") end }
            end
        end
    end
    table.sort(items, function(a, b)
        if a.header or b.header then return a.header ~= nil end
        return a.caption < b.caption
    end)
    if #items == 1 then items[#items + 1] = { caption = "None yet: target one and press Use my target", disabled = true } end
    ui():OpenMenu(items, { anchor = anchor })
end

-- A list of quests (accept, turn in): chips, the quest log, or an ID.
F.quests = function(self, step, field)
    local draft, key = self.draft, field.key
    local row = self:FieldRow(field.label)
    for index, id in ipairs(list(step[key])) do
        chip(row, questName(id), "Quest " .. id, function()
            self:Hard(draft.SetField, draft, step, key, without(step[key], index), key)
        end, "quest", nil, (key == "turnin" or step.type == "turnin") and ICONS.turnin or ICONS.accept)
    end
    local function add(ids) self:Hard(draft.SetField, draft, step, key, appended(step[key], ids), key) end
    self.controls[key] = row:Button{ "Add quest", onClick = function(button) self:OpenQuestMenu(button, add) end }
    self:LinkTarget("quest", key, add)
    if key ~= "accept" then row:Text{ "or shift-click one in your quest log", style = "fine", color = "muted" } end
end

function Editor:OpenQuestMenu(anchor, add)
    local client = Client()
    local entries = client and client:GetQuestLogEntries() or {}
    local items = { { header = "Your quest log" } }
    for _, entry in ipairs(entries) do
        items[#items + 1] = { caption = tostring(entry.title or ("Quest " .. entry.questID)), desc = "Quest " .. entry.questID,
            onClick = function() add({ entry.questID }) end }
    end
    if #entries == 0 then items[#items + 1] = { caption = "Your quest log is empty", disabled = true } end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { caption = "Type its ID", onClick = function() self:AskIDs("Add quest", "Quest ID", add) end }
    ui():OpenMenu(items, { anchor = anchor })
end

-- IDs typed into a small window: "871" or "871, 872".
function Editor:AskIDs(title, label, add)
    self:Prompt(title, label, "", function(text)
        local ids = parseIDs(text)
        if #ids > 0 then add(ids) end
    end, "Add")
end

-- Where a shift-click without a field in focus goes: the page's field of
-- that kind (for a quest on a talk step, the turn-in when the quest is
-- ready to hand in, else the accept).
function Editor:LinkTarget(kind, key, add)
    self.linkTargets = self.linkTargets or {}
    self.linkTargets[kind] = self.linkTargets[kind] or {}
    self.linkTargets[kind][key] = add
end

-- The quest a step's work is for: the whole quest, or one objective.
F.quest = function(self, step, field)
    local draft = self.draft
    local row = self:FieldRow(field.label or "For quest")
    local quest = step.quest
    local id = type(quest) == "table" and quest[1] or quest
    local objective = type(quest) == "table" and quest[2] or nil
    if id then
        chip(row, questName(id), "Quest " .. id, function() self:Hard(draft.SetField, draft, step, "quest", nil, "quest") end,
            "quest", nil, ICONS.escort)
        if not field.whole then
            local options = { { value = 0, caption = "The whole quest" } }
            local client = Client()
            local lines = client and client:GetQuestObjectives(id) or {}
            for index = 1, math.max(#lines, 3) do
                local line = lines[index]
                options[#options + 1] = { value = index, caption = "Objective " .. index .. (line and line.text and (": " .. line.text) or "") }
            end
            row:Select{ boxWidth = 220, options = options, value = objective or 0, onChange = function(value)
                self:Soft(draft.SetField, draft, step, "quest", value > 0 and { id, value } or id, "quest")
            end }
        end
    else
        local function add(ids) self:Hard(draft.SetField, draft, step, "quest", ids[1], "quest") end
        row:Button{ "Add quest", onClick = function(button) self:OpenQuestMenu(button, add) end }
        self:LinkTarget("quest", "quest", add)
    end
end

-- Creatures (kill, mark): chips, the target, or IDs.
F.creatures = function(self, step, field, row)
    local draft, key = self.draft, field.key
    row = row or self:FieldRow(field.label)
    for index, id in ipairs(list(step[key])) do
        chip(row, draft:NPCName(id) or ("Creature " .. id), "Creature " .. id, function()
            self:Hard(draft.SetField, draft, step, key, without(step[key], index), key)
        end, "danger", nil, ICONS.kill)
    end
    self.controls[key .. "Target"] = row:Button{ "Add my target", onClick = function()
        local id, name = myTarget()
        if not id then return self:Problem("Target the creature first.") end
        self:Hard(draft.Change, draft, key, function()
            draft:KeepNPC(id, name)
            step[key] = appended(step[key], { id })
        end)
    end }
    row:Button{ "Type IDs", style = "ghost", onClick = function()
        self:AskIDs("Add creatures", "Creature IDs", function(ids)
            self:Hard(draft.SetField, draft, step, key, appended(step[key], ids), key)
        end)
    end }
end

-- One item, by ID or shift-click, with its name.
F.item = function(self, step, field)
    local draft, key = self.draft, field.key or "item"
    local row = self:FieldRow(field.label or "Item")
    local id = type(step[key]) == "number" and step[key] or nil
    if id then
        chip(row, itemName(id), "Item " .. id, function() self:Hard(draft.SetField, draft, step, key, nil, key) end, "warning",
            nil, itemIcon(id))
    end
    local function set(ids) self:Hard(draft.SetField, draft, step, key, ids[1], key) end
    self.controls[key] = row:Button{ id and "Change" or "Choose item", onClick = function(button) self:OpenItemMenu(button, set) end }
    self:LinkTarget("item", key, set)
    if not id then row:Text{ "or shift-click it", style = "fine", color = "muted" } end
end

-- A list of items (use, item): chips and IDs.
-- Items from the bags, or an ID typed.
function Editor:OpenItemMenu(anchor, add)
    local client = Client()
    local bag = client and client.GetBagItems and client:GetBagItems() or {}
    local items, seen = { { header = "Your bags" } }, {}
    for _, entry in ipairs(bag) do
        if entry.itemID and not seen[entry.itemID] then
            seen[entry.itemID] = true
            items[#items + 1] = { caption = tostring(entry.name or ("Item " .. entry.itemID)), desc = "Item " .. entry.itemID,
                onClick = function() add({ entry.itemID }) end }
        end
    end
    if #items == 1 then items[#items + 1] = { caption = "Nothing in your bags", disabled = true } end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { caption = "Type its ID", onClick = function() self:AskIDs("Item", "Item ID", add) end }
    ui():OpenMenu(items, { anchor = anchor })
end

F.items = function(self, step, field, row)
    local draft, key = self.draft, field.key
    row = row or self:FieldRow(field.label)
    for index, id in ipairs(list(step[key])) do
        chip(row, itemName(id), "Item " .. id, function()
            self:Hard(draft.SetField, draft, step, key, without(step[key], index), key)
        end, "warning", nil, itemIcon(id))
    end
    row:Button{ "Add item", style = "ghost", onClick = function(button)
        self:OpenItemMenu(button, function(ids) self:Hard(draft.SetField, draft, step, key, appended(step[key], ids), key) end)
    end }
end

F.spells = function(self, step, field)
    local draft, key = self.draft, field.key
    local row = self:FieldRow(field.label)
    for index, id in ipairs(list(step[key])) do
        chip(row, spellName(id), "Spell " .. id, function()
            self:Hard(draft.SetField, draft, step, key, without(step[key], index), key)
        end, "estimate", nil, spellIcon(id))
    end
    local function add(ids) self:Hard(draft.SetField, draft, step, key, appended(step[key], ids), key) end
    row:Button{ "Type IDs", onClick = function() self:AskIDs("Spells", "Spell IDs", add) end }
    self:LinkTarget("spell", key, add)
    row:Text{ "or shift-click them in your spellbook", style = "fine", color = "muted" }
end

F.spell = function(self, step, field)
    local draft, key = self.draft, field.key
    local row = self:FieldRow(field.label)
    if type(step[key]) == "number" then
        chip(row, spellName(step[key]), "Spell " .. step[key], function() self:Hard(draft.SetField, draft, step, key, nil, key) end,
            "estimate", nil, spellIcon(step[key]))
    end
    local function set(ids) self:Hard(draft.SetField, draft, step, key, ids[1], key) end
    row:Button{ "Type its ID", onClick = function() self:AskIDs("Spell", "Spell ID", set) end }
    self:LinkTarget("spell", key, set)
    row:Text{ "or shift-click it in your spellbook", style = "fine", color = "muted" }
end

F.number = function(self, step, field, row)
    local draft, key = self.draft, field.key
    row = row or self:FieldRow(field.label)
    self.controls[key] = row:Input{ width = 80, value = step[key] and tostring(step[key]) or "", placeholder = "",
        onChange = function(text)
            local value = tonumber(trim(text))
            if value then value = math.floor(value) end
            self:Soft(draft.SetField, draft, step, key, value, key)
        end }
    if field.hint then row:Text{ field.hint, style = "fine", color = "muted" } end
end

F.text = function(self, step, field)
    local draft, key = self.draft, field.key
    local row = self:FieldRow(field.label)
    self.controls[key] = row:Input{ grow = true, value = step[key] or "", placeholder = field.placeholder or "",
        onChange = function(text) self:Soft(draft.SetField, draft, step, key, trim(text), key) end }
end

F.toggles = function(self, step, field)
    local draft = self.draft
    local row = self:FieldRow("")
    for _, entry in ipairs(field) do
        if type(entry) == "table" then
            local key = entry[1]
            row:Toggle{ entry[2], value = step[key] == true, onChange = function(on)
                self:Soft(draft.SetField, draft, step, key, on and true or nil, key)
            end }
        end
    end
end

F.skill = function(self, step, field, row)
    local draft, key = self.draft, field.key or "skill"
    row = row or self:FieldRow(field.label or "Profession")
    local options = sortedOptions(idNames("skills"))
    if field.optional then table.insert(options, 1, { value = 0, caption = "Any" }) end
    row:SearchSelect{ boxWidth = 200, options = options, value = step[key] or (field.optional and 0 or nil),
        onChange = function(value) self:Soft(draft.SetField, draft, step, key, value ~= 0 and value or nil, key) end }
end

F.area = function(self, step, field)
    local draft, key = self.draft, field.key or "area"
    local row = self:FieldRow(field.label or "Area")
    local options = sortedOptions(idNames("areas"))
    if field.optional then table.insert(options, 1, { value = 0, caption = "No, on reaching the spot" }) end
    row:SearchSelect{ boxWidth = 220, options = options, value = step[key] or (field.optional and 0 or nil),
        onChange = function(value) self:Soft(draft.SetField, draft, step, key, value ~= 0 and value or nil, key) end }
    row:Button{ "Where I am", onClick = function()
        local client = Client()
        local here = client and client:GetSubzone()
        for id, name in pairs(idNames("areas")) do
            if name == here then return self:Hard(draft.SetField, draft, step, key, id, key) end
        end
        self:Problem("'" .. tostring(here) .. "' is not in NuuRoad's list of areas yet.")
    end }
end

F.node = function(self, step)
    local draft = self.draft
    local row = self:FieldRow("Flight point")
    row:SearchSelect{ boxWidth = 260, options = sortedOptions(idNames("taxiNodes")), value = step.node,
        onChange = function(value) self:Soft(draft.SetField, draft, step, "node", value, "flight point") end }
end

F.faction = function(self, step)
    local draft = self.draft
    local row = self:FieldRow("Faction")
    row:Input{ width = 80, value = step.faction and tostring(step.faction) or "", placeholder = "ID",
        onChange = function(text) self:Soft(draft.SetField, draft, step, "faction", tonumber(trim(text)), "faction") end }
    local Names = M("Names")
    if step.faction and Names then row:Text{ Names:DescribeFaction(step.faction) or "", color = "muted" } end
end

F.standing = function(self, step)
    local draft, Names = self.draft, M("Names")
    local row = self:FieldRow("Standing")
    local options = {}
    for value = 1, 8 do options[value] = { value = value, caption = Names and Names:DescribeStanding(value) or tostring(value) } end
    local current = step.standing
    if type(current) == "string" and Names then current = Names:StandingValue(current) end
    row:Select{ boxWidth = 160, options = options, value = current, onChange = function(value)
        self:Soft(draft.SetField, draft, step, "standing", value, "standing")
    end }
end

-- Steps as choices for a field that points at one: "12  Accept ...".
function Editor:StepOptions(except)
    local options = { { value = 0, caption = "None" } }
    for _, entry in ipairs(self.draft:Entries()) do
        if entry.step ~= except then
            options[#options + 1] = { value = entry.position, caption = entry.position .. "  " .. self:TitleOf(entry.step) }
        end
    end
    return options
end

F.steppick = function(self, step, field, row)
    local draft, key = self.draft, field.key
    row = row or self:FieldRow(field.label)
    local target = draft:StepLabelled(step[key])
    local entry = target and draft:EntryOf(target)
    row:SearchSelect{ boxWidth = 260, options = self:StepOptions(step), value = entry and entry.position or 0,
        onChange = function(value)
            local chosen = value ~= 0 and draft:StepAt(value) or nil
            self:Soft(draft.Point, draft, step, key, chosen, chosen and self:TitleOf(chosen))
        end }
    if field.hint then row:Text{ field.hint, style = "fine", color = "muted" } end
end

F.options = function(self, step)
    local draft = self.draft
    for index, option in ipairs(step.options or {}) do
        local row = self:FieldRow(index == 1 and "Ways to go" or "")
        row:Input{ width = 200, value = option.text or "", placeholder = "Button text",
            onChange = function(text) self:Soft(draft.SetOption, draft, step, index, trim(text), nil) end }
        row:Text{ "goes to", color = "muted" }
        local target = draft:StepLabelled(option.go)
        local entry = target and draft:EntryOf(target)
        row:SearchSelect{ boxWidth = 220, options = self:StepOptions(step), value = entry and entry.position or 0,
            onChange = function(value)
                local chosen = value ~= 0 and draft:StepAt(value) or nil
                if chosen then self:Soft(draft.SetOption, draft, step, index, option.text, chosen, self:TitleOf(chosen)) end
            end }
        row:GlyphButton{ "close", tooltip = "Take this way out", onClick = function() self:Hard(draft.RemoveOption, draft, step, index) end }
    end
    local row = self:FieldRow(#(step.options or {}) == 0 and "Ways to go" or "")
    row:Button{ "Add a way", onClick = function()
        local nextStep = draft:StepAt((draft:EntryOf(step).position or 0) + 1)
        self:Hard(draft.SetOption, draft, step, #(step.options or {}) + 1, "This way", nextStep,
            nextStep and self:TitleOf(nextStep))
    end }
end

-- Where the step is: the NPC's spot, one or more spots, or a place point.
F.where = function(self, step, field, row)
    local draft = self.draft
    row = row or self:FieldRow(field.label or "Where")
    local spots = type(step.at) == "table" and (type(step.at[1]) == "table" and #step.at or 1) or 0
    local summary
    if step.stand then summary = "stands on " .. step.stand
    elseif spots == 1 then summary = "one spot"
    elseif spots > 1 then summary = spots .. " spots; the arrow takes the nearest"
    elseif step.npc then summary = "where the NPC stands"
    else summary = "nowhere in particular" end
    row:Text{ summary, color = "muted" }
    row:Button{ "Where I stand", tooltip = "This spot, and no other", onClick = function()
        local at, map = whereIStand()
        if not at then return self:Problem("Your position cannot be read here.") end
        if map ~= (draft:Sections()[draft:EntryOf(step).section].map or draft.guide.data.map) then at.map = map end
        self:Hard(draft.SetFields, draft, step, { at = { at }, stand = false }, "where")
    end }
    row:Button{ "Add a spot here", tooltip = "Another spot the arrow may lead to", onClick = function()
        local at, map = whereIStand()
        if not at then return self:Problem("Your position cannot be read here.") end
        if map ~= (draft:Sections()[draft:EntryOf(step).section].map or draft.guide.data.map) then at.map = map end
        local spotsNow = type(step.at) == "table" and (type(step.at[1]) == "table" and step.at or { step.at }) or {}
        local out = {}
        for _, point in ipairs(spotsNow) do out[#out + 1] = point end
        out[#out + 1] = at
        self:Hard(draft.SetFields, draft, step, { at = out, stand = false }, "where")
    end }
    if spots > 0 or step.stand then
        row:Button{ "Clear", onClick = function() self:Hard(draft.SetFields, draft, step, { at = false, stand = false }, "where") end }
    end
end

-- The guide a finish step leads on to.
F.nextguide = function(self, step)
    local draft = self.draft
    local row = self:FieldRow("Next guide")
    local options = { { value = "", caption = "None" } }
    for _, guide in ipairs(M("GuideRepository"):List()) do
        if guide.id ~= draft.guide.id then options[#options + 1] = { value = guide.id, caption = tostring(guide.meta.title) } end
    end
    local current = type(step.next) == "table" and step.next[1] or step.next
    row:SearchSelect{ boxWidth = 260, options = options, value = current or "", onChange = function(value)
        self:Soft(draft.SetField, draft, step, "next", value ~= "" and value or nil, "next guide")
    end }
end

F.note = function(self, step)
    local draft = self.draft
    local row = self:FieldRow("Note", "top")
    self.controls.note = row:TextArea{ grow = true, boxHeight = 64, value = step.note or "",
        placeholder = step.type == "note" and "What the player reads" or "Shown under the step in the tracker",
        onChange = function(text) self:Soft(draft.SetField, draft, step, "note", trim(text), "note") end }
end

-- Who sees the step, in words, with the picker behind Change.
function Editor:DescribeWho(step)
    local cond, show = step.cond, step.show
    if cond == nil and show == nil then return "Everyone" end
    local parts = {}
    if type(cond) == "table" then
        local classes = list(cond.class)
        if #classes > 0 then
            local names = {}
            for _, class in ipairs(classes) do names[#names + 1] = (CLASS_NAMES[class] or class) .. "s" end
            parts[#parts + 1] = table.concat(names, ", ")
        end
        if cond.race then parts[#parts + 1] = table.concat(list(cond.race), ", ") end
        if cond.faction then parts[#parts + 1] = table.concat(list(cond.faction), ", ") end
        if cond.hardcore then parts[#parts + 1] = "hardcore" end
        if cond.season then parts[#parts + 1] = "season realms" end
        for key in pairs(cond) do
            if key ~= "class" and key ~= "race" and key ~= "faction" and key ~= "hardcore" and key ~= "season" then
                parts[#parts + 1] = "a custom rule"
                break
            end
        end
    end
    if type(show) == "table" then
        if show.skill then parts[#parts + 1] = "who know the profession" end
        if show.ah then parts[#parts + 1] = "who use the auction house" end
        if show.selffound then parts[#parts + 1] = "self found" end
        if show.none or show.any or show.is or show.all then parts[#parts + 1] = "a custom rule" end
    end
    return #parts > 0 and table.concat(parts, "; ") or "Some characters"
end

F.shown = function(self, step)
    local row = self:FieldRow("Shown to")
    row:Chip{ self:DescribeWho(step), tone = step.cond == nil and step.show == nil and "accent" or "warning" }
    self.controls.shown = row:Button{ step.cond == nil and step.show == nil and "Only some characters" or "Change",
        onClick = function() self:OpenShownTo(step) end }
end

-- More options -----------------------------------------------------------------------------------

function Editor:MoreSummary(step)
    local set = {}
    if step.at or step.stand then set[#set + 1] = "where" end
    if step.sticky or step.with or step.from then set[#set + 1] = "kept up" end
    if step.use or (type(step.item) == "table") then set[#set + 1] = "items" end
    if step.optional then set[#set + 1] = "optional" end
    if step.wait then set[#set + 1] = "wait" end
    if step.mark then set[#set + 1] = "marked creatures" end
    if step.needs then set[#set + 1] = "materials" end
    if step.say then set[#set + 1] = "dialog" end
    if step.upto then set[#set + 1] = "done at a rank" end
    return #set > 0 and table.concat(set, ", ") or "where, keep it up, items to press"
end

local HAS_WHERE = { escort = true, collect = true, kill = true, interact = true, travel = true, cast = true, level = true }

function Editor:BuildMore(step)
    local draft = self.draft
    if not HAS_WHERE[step.type] then F.where(self, step, { label = "Where" }, self:MoreRow("Where")) end

    local radius = self:MoreRow("Reached within")
    radius:Select{ boxWidth = 180, value = step.radius or 0, options = {
        { value = 0, caption = "The usual distance" }, { value = 100, caption = "Close (1% of the map)" },
        { value = 400, caption = "Wide (4%)" }, { value = 800, caption = "Very wide (8%)" },
    }, onChange = function(value) self:Soft(draft.SetField, draft, step, "radius", value ~= 0 and value or nil, "radius") end }

    local places = draft.guide.data.places
    if places and #places > 0 then
        local options = { { value = "", caption = "No" } }
        for _, place in ipairs(places) do
            for index, point in ipairs(place.points or {}) do
                local ref = place.id .. "." .. (point.id or index)
                options[#options + 1] = { value = ref, caption = ref .. (point.label and (" (" .. point.label .. ")") or "") }
            end
        end
        local stand = self:MoreRow("Stands on")
        stand:Select{ boxWidth = 240, value = step.stand or "", options = options, onChange = function(value)
            self:Hard(draft.SetFields, draft, step, { stand = value ~= "" and value or false, at = false }, "where")
        end }
    end

    local kept = self:MoreRow("Keep it up")
    kept:Toggle{ "Alongside the steps after it, until done", value = step.sticky == true, onChange = function(on)
        self:Soft(draft.SetField, draft, step, "sticky", on and true or nil, "sticky")
    end }
    F.steppick(self, step, { key = "with", hint = "done when that step is" }, self:MoreRow("Until step"))
    F.steppick(self, step, { key = "from", hint = "shown from that step on" }, self:MoreRow("From step"))

    F.items(self, step, { key = "use" }, self:MoreRow("Item to press"))
    if type(step.item) ~= "number" then F.items(self, step, { key = "item" }, self:MoreRow("Item it is about")) end
    F.creatures(self, step, { key = "mark" }, self:MoreRow("Mark creatures"))

    if step.type == "turnin" or step.type == "talk" then
        local optional = self:MoreRow("Optional")
        optional:Toggle{ "Passed unless a quest is ready to hand in", value = step.optional == true, onChange = function(on)
            self:Soft(draft.SetField, draft, step, "optional", on and true or nil, "optional")
        end }
    end
    if step.type == "accept" or step.type == "talk" then
        F.number(self, step, { key = "level", hint = "the level the quests are taken from" }, self:MoreRow("Taken at level"))
    end
    if step.type == "talk" then
        local say = self:MoreRow("Dialog options")
        say:Input{ width = 160, value = table.concat(copyList(step.say), ", "), placeholder = "gossip option IDs",
            onChange = function(text) self:Soft(draft.SetField, draft, step, "say", parseIDs(text), "dialog") end }
    end

    F.number(self, step, { key = "wait", hint = "seconds the step keeps the player" }, self:MoreRow("Wait"))
    self:BuildMaterials(step)
    if step.type == "gather" or step.type == "craft" or step.type == "buy" or step.type == "collect" then
        local upto = self:MoreRow("Done at rank")
        local current = step.upto or {}
        upto:SearchSelect{ boxWidth = 180, options = sortedOptions(idNames("skills"), { { value = 0, caption = "No" } }),
            value = current.skill or 0, onChange = function(value)
                self:Soft(draft.SetField, draft, step, "upto", value ~= 0 and { skill = value, rank = current.rank or 1 } or nil, "rank")
            end }
        upto:Input{ width = 70, value = current.rank and tostring(current.rank) or "", placeholder = "rank",
            onChange = function(text)
                local rank = tonumber(trim(text))
                if current.skill and rank then self:Soft(draft.SetField, draft, step, "upto", { skill = current.skill, rank = rank }, "rank") end
            end }
    end

    local textRow = self:MoreRow("")
    textRow:Button{ "Edit this step as text", onClick = function() self:EditStepAsText(step) end,
        tooltip = "The step as a guide file writes it" }
end

local SOURCES = { { value = "gather", caption = "Gather" }, { value = "vendor", caption = "Vendor" },
    { value = "ah", caption = "Auction house" }, { value = "drop", caption = "Drop" }, { value = "craft", caption = "Craft" } }

function Editor:BuildMaterials(step)
    local draft = self.draft
    for index, need in ipairs(step.needs or {}) do
        local row = self:MoreRow(index == 1 and "Materials" or "")
        row:Text{ itemName(need.item), width = 160 }
        row:Input{ width = 60, value = tostring(need.count or 1), onChange = function(text)
            local needs = GuideDraftCopy(step.needs)
            needs[index].count = tonumber(trim(text)) or 1
            self:Soft(draft.SetField, draft, step, "needs", needs, "materials")
        end }
        row:Select{ boxWidth = 130, options = SOURCES, value = need.source or "gather", onChange = function(value)
            local needs = GuideDraftCopy(step.needs)
            needs[index].source = value ~= "gather" and value or nil
            self:Soft(draft.SetField, draft, step, "needs", needs, "materials")
        end }
        row:GlyphButton{ "close", tooltip = "Take it out", onClick = function()
            local needs = GuideDraftCopy(step.needs)
            table.remove(needs, index)
            self:Hard(draft.SetField, draft, step, "needs", needs, "materials")
        end }
    end
    local row = self:MoreRow(step.needs and "" or "Materials")
    self:LinkInput(row, "item", "add: ID, or shift-click", function(ids)
        local needs = GuideDraftCopy(step.needs or {})
        for _, id in ipairs(ids) do needs[#needs + 1] = { item = id, count = 1 } end
        self:Hard(draft.SetField, draft, step, "needs", needs, "materials")
    end, 160)
end

-- Menus --------------------------------------------------------------------------------------------

-- The types, the common ones first and the rest one level down, by group.
-- With `current` (changing a step's type) they are a radio group with the
-- step's own type marked; without (adding a step), plain entries. Either
-- way a click calls onPick: a check item would only toggle its box.
function Editor:TypeItems(onPick, current)
    local function entry(info)
        local item = { caption = info.caption, desc = info.desc, onClick = function() onPick(info.key) end }
        if current ~= nil then item.group, item.value, item.checked = "type", info.key, current == info.key end
        return item
    end
    local items = {}
    for _, info in ipairs(TYPES) do
        if info.common then items[#items + 1] = entry(info) end
    end
    items[#items + 1] = { separator = true }
    local groups, order = {}, {}
    for _, info in ipairs(TYPES) do
        if not info.common then
            if not groups[info.group] then groups[info.group] = {}; order[#order + 1] = info.group end
            table.insert(groups[info.group], entry(info))
        end
    end
    local more = {}
    for _, group in ipairs(order) do
        more[#more + 1] = { header = group }
        for _, item in ipairs(groups[group]) do more[#more + 1] = item end
    end
    items[#items + 1] = { caption = "More types", items = more }
    return items
end

function Editor:OpenTypeMenu(anchor)
    local step = self.step
    ui():OpenMenu(self:TypeItems(function(kind) self:Hard(self.draft.SetType, self.draft, step, kind) end, step.type),
        { anchor = anchor })
end

-- A new step of the type picked, after the selected one. A step for an NPC
-- takes the player's target when there is one.
function Editor:OpenAddMenu(anchor)
    ui():OpenMenu(self:TypeItems(function(kind) self:AddStep(kind) end), { anchor = anchor })
end

function Editor:AddStep(kind)
    local draft = self.draft
    if not draft then return end
    local step = { type = kind or "note" }
    for key, value in pairs(({ vendor = { sell = true }, choice = { text = "Which way?" } })[kind] or {}) do step[key] = value end
    local added = self:Hard(function() return draft:Insert(self.step, step) end)
    if added then self:Select(step) end
end

function Editor:AddSection()
    local draft = self.draft
    if not draft then return end
    self:Prompt("New section", "Title", "", function(title)
        local step = draft:AddSection(title)
        if step then self:Select(step) end
    end, "Add")
end

function Editor:OutlineMenu(item)
    local draft = self.draft
    if item.kind == "section" then
        local index = item.index
        ui():OpenMenu({
            { header = draft:Sections()[index].title },
            { caption = "Rename", onClick = function()
                self:Prompt("Rename section", "Title", draft:Sections()[index].title, function(title)
                    self:Hard(draft.RenameSection, draft, index, title)
                end, "Rename")
            end },
            { caption = "Merge with the section above", disabled = #draft:Sections() < 2,
                onClick = function() self:Hard(draft.MergeSection, draft, index) end },
            { caption = "Add a section at the end", onClick = function() self:AddSection() end },
        }, { at = "cursor" })
        return
    end
    local step = item.step
    if self.selection and self.selection[step] and #self:Selected() > 1 then return self:SelectionMenu() end
    self:Select(step)
    local entry = draft:EntryOf(step)
    local sections = {}
    for index, section in ipairs(draft:Sections()) do
        sections[#sections + 1] = { caption = section.title, disabled = index == entry.section and not entry.group,
            onClick = function() self:Hard(draft.MoveToSection, draft, step, index) end }
    end
    ui():OpenMenu({
        { header = entry.position .. "  " .. self:TitleOf(step) },
        { caption = "Add a step after it", items = self:TypeItems(function(kind) self:AddStep(kind) end) },
        { caption = "Duplicate", onClick = function()
            local twin = self:Hard(function() return draft:Duplicate(step) end)
            if twin then self:Select(draft:StepAt(entry.position + 1)) end
        end },
        { separator = true },
        { caption = "Move up", onClick = function() self:Hard(draft.Move, draft, step, -1) end },
        { caption = "Move down", onClick = function() self:Hard(draft.Move, draft, step, 1) end },
        { caption = "Move to section", items = sections },
        { caption = "Start a new section here", onClick = function()
            self:Prompt("New section", "Title", "", function(title) self:Hard(draft.SplitSection, draft, step, title) end, "Start")
        end },
        { separator = true },
        entry.group and { caption = "Take out of its group", onClick = function() self:Hard(draft.Ungroup, draft, step) end }
            or { caption = "Group with the next step", desc = "Quest visits done together, in any order",
                onClick = function() self:Hard(draft.GroupWithNext, draft, step) end },
        { separator = true },
        { caption = "Delete", tone = "danger", onClick = function() self:Hard(draft.Delete, draft, step) end },
    }, { at = "cursor" })
end

-- The right-click menu on a selection: the selection page's actions.
function Editor:SelectionMenu()
    local draft, steps = self.draft, self:Selected()
    local function act(change, ...)
        local ok = self:Hard(change, ...)
        if ok ~= false then self:RenderAll() end
    end
    local sections = {}
    for index, section in ipairs(draft:Sections()) do
        sections[#sections + 1] = { caption = section.title, onClick = function() act(draft.MoveManyToSection, draft, steps, index) end }
    end
    ui():OpenMenu({
        { header = #steps .. " steps" },
        { caption = "Group them", onClick = function() act(draft.GroupSteps, draft, steps) end },
        { caption = "Take out of groups", onClick = function() act(draft.UngroupMany, draft, steps) end },
        { caption = "Duplicate", onClick = function() act(draft.DuplicateMany, draft, steps) end },
        { separator = true },
        { caption = "Move up", onClick = function() act(draft.MoveMany, draft, steps, -1) end },
        { caption = "Move down", onClick = function() act(draft.MoveMany, draft, steps, 1) end },
        { caption = "Move to section", items = sections },
        { caption = "Shown to", onClick = function() self:OpenShownTo(steps[1], steps) end },
        { separator = true },
        { caption = "Delete " .. #steps .. " steps", tone = "danger", onClick = function() act(draft.DeleteMany, draft, steps) end },
    }, { at = "cursor" })
end

-- The Guide menu: what is about the whole guide.
function Editor:OpenGuideMenu(anchor)
    local draft = self.draft
    if not draft then return end
    local Repository = M("GuideRepository")
    local mine = Repository:IsUserGuide(draft.guide.id)
    local items = {
        { caption = "Add steps while playing", desc = "A small panel beside the tracker",
            onClick = function() local Panel = M("AddingPanel") if Panel then Panel:Open(draft) end end },
        { caption = "Guide settings", desc = "Name, folder, levels", onClick = function() self:OpenSettings() end },
        { caption = "Quests not in the guide", desc = "From your quest log", onClick = function() self:OpenMissingQuests() end },
        { caption = "History", desc = "Earlier versions of this guide", onClick = function() self:OpenHistory() end },
        { caption = "Caves and tunnels", desc = "Places the arrow finds its way through", onClick = function() self:OpenPlaces() end },
        { separator = true },
        { caption = "Edit as text", desc = "The whole guide, as a guide file writes it", onClick = function() self:EditGuideAsText() end },
        { caption = "Copy as text", desc = "To share it, or keep it in a file", onClick = function() self:CopyAsText() end },
        { caption = "Import from text", desc = "A guide someone shared, as a new guide", onClick = function() self:ImportFromText() end },
    }
    if mine then
        items[#items + 1] = { separator = true }
        local remove = { caption = "Delete this guide", tone = "danger", keep = true }
        remove.onClick = function(entry)
            if entry.armed then
                ui():CloseMenu()
                return self:DeleteGuide()
            end
            entry.armed = true
            entry.caption = "Sure? Click again"
        end
        items[#items + 1] = remove
    end
    ui():OpenMenu(items, { anchor = anchor })
end

function Editor:DeleteGuide()
    local draft = self.draft
    local id = draft.guide.id
    local Repository, Progress = M("GuideRepository"), M("Progress")
    local guide = Repository:Get(id)
    if guide and Progress and Progress:IsOpen(guide) then Progress:Close(guide) end
    Repository:DeleteUserGuide(id)
    self.draft, self.step = nil, nil
    self:Hide()
    local Main = M("MainWindow")
    if Main and Main.RequestRefresh then Main:RequestRefresh() end
end

-- Follows the guide in the tracker from the selected step.
function Editor:PlayFromStep()
    local draft = self.draft
    if not draft then return end
    local Repository, Progress = M("GuideRepository"), M("Progress")
    local guide = Repository:Get(draft.guide.id)
    if not guide then return self:Problem("No step of this guide can be played yet.") end
    local _, index = self:NodeOf(self.step)
    if not index then return self:Problem("This step has a problem to fix before it can be played.") end
    Progress:Select(guide)
    local GuideScan = M("GuideScan")
    if GuideScan and GuideScan.Cancel then GuideScan:Cancel() end
    Progress:GoTo(guide, index)
    local Main = M("MainWindow")
    if Main then
        if Main.Show then Main:Show() end
        if Main.Refresh then Main:Refresh() end
    end
end

-- History --------------------------------------------------------------------------------------

local HISTORY_KEEP, HISTORY_EVERY = 12, 600

local function now()
    local clock = rawget(_G, "time") or (os and os.time)
    return clock and clock() or 0
end

-- Earlier versions of a guide of the player's own, newest first, in
-- NuuRoadDB.account.history[id]: the guide as it was when the editor opened
-- it, and again every ten minutes of changes.
function Editor:History(id)
    local account = ns.db and ns.db.account
    if not account then return {} end
    account.history = account.history or {}
    account.history[id] = account.history[id] or {}
    return account.history[id]
end

function Editor:KeepHistory(draft, what)
    if what == "undo" or what == "redo" or what == "history" then return end
    local id = draft.guide.id
    if not M("GuideRepository"):IsUserGuide(id) then return end
    local list = self:History(id)
    local value = draft.openedValue
    if not draft.historyStarted then
        draft.historyStarted = true
        if value and value.kind == "guide" and not draft.isNewCopy then
            value.id = id
            table.insert(list, 1, { at = now(), what = "As it was when opened", value = value })
        end
    elseif (list[1] and list[1].at or 0) < now() - HISTORY_EVERY then
        table.insert(list, 1, { at = now(), what = "While editing", value = draft:Value() })
    end
    while #list > HISTORY_KEEP do table.remove(list) end
end

local function when(at)
    local date = rawget(_G, "date") or (os and os.date)
    return date and date("%d %b, %H:%M", at) or tostring(at)
end

local function stepCount(value)
    local count = 0
    for _, section in ipairs(value.data and value.data.sections or {}) do
        for _, item in ipairs(section.steps or {}) do count = count + (item.group and #item.group or 1) end
    end
    return count
end

function Editor:OpenHistory()
    local draft = self.draft
    local list = self:History(draft.guide.id)
    local win = self.historyWin
    if win then win:Hide() end
    win = ui():Window({ key = "editorHistory", title = "History", width = 440, height = 380, place = self.places, hidden = true })
    self.historyWin = win
    local body = win:Column{ gap = 8, padding = 12 }
    body:Text{ "Earlier versions of " .. tostring(draft.guide.title) .. ". Restoring one is a change of its own: Undo brings back what you had.",
        style = "fine", color = "muted", wrap = true }
    if #list == 0 then body:Text{ "No earlier versions yet: one is kept when you open the guide and make a change, and every ten minutes after.", wrap = true } end
    for _, entry in ipairs(list) do
        local row = body:Row{ gap = 8, valign = "center" }
        row:Text{ when(entry.at), style = "number", width = 110 }
        row:Text{ entry.what .. ", " .. stepCount(entry.value) .. " steps", grow = true }
        row:Button{ "Restore", onClick = function()
            local value = GuideDraftCopy(entry.value)
            self:Hard(draft.Change, draft, "history", function()
                value.id = draft.guide.id
                draft.guide = value
            end)
            win:Hide()
            self:SetStatus("Restored the version of " .. when(entry.at) .. ". Ctrl-Z takes it back.")
        end }
    end
    win:Show()
end

-- Quests in the player's log that the guide does not take yet, each a
-- click from an accept step after the selected one.
function Editor:OpenMissingQuests()
    local draft, client = self.draft, Client()
    local taken = {}
    for _, entry in ipairs(draft:Entries()) do
        local step = entry.step
        for _, key in ipairs({ "quests", "accept", "turnin" }) do
            for _, id in ipairs(list(step[key])) do taken[id] = true end
        end
        local quest = type(step.quest) == "table" and step.quest[1] or step.quest
        if quest then taken[quest] = true end
    end
    local items = { { header = "In your quest log, not in this guide" } }
    for _, entry in ipairs(client and client:GetQuestLogEntries() or {}) do
        if not taken[entry.questID] then
            items[#items + 1] = { caption = tostring(entry.title or ("Quest " .. entry.questID)), desc = "Add an accept step for it",
                onClick = function()
                    local step = { type = "accept", quests = { entry.questID } }
                    local added = self:Hard(function() return draft:Insert(self.step, step) end)
                    if added then self:Select(step) end
                end }
        end
    end
    if #items == 1 then items[#items + 1] = { caption = "Every quest in your log is in the guide", disabled = true } end
    ui():OpenMenu(items, { anchor = self.undoButton })
end

-- Small windows ----------------------------------------------------------------------------------

-- One line of text asked for, in a small window of its own.
function Editor:Prompt(title, label, value, onDone, action, alternative)
    local prompt = self.prompt
    if not prompt then
        prompt = ui():Window({ key = "editorPrompt", title = title, width = 380, height = 150, place = self.places, hidden = true })
        local body = prompt:Column{ gap = 10, padding = 14 }
        prompt.input = body:Input{ label = label, onChange = function() end }
        local buttons = body:Row{ gap = 6, align = "right" }
        buttons:Spacer{}
        buttons:Button{ "Cancel", onClick = function() prompt:Hide() end }
        prompt.alt = buttons:Button{ "", onClick = function()
            prompt:Hide()
            if prompt.onAlt then prompt.onAlt(trim(prompt.input:GetText())) end
        end }
        prompt.ok = buttons:Button{ "OK", tone = "accent", onClick = function()
            prompt:Hide()
            if prompt.onDone then prompt.onDone(trim(prompt.input:GetText())) end
        end }
        self.prompt = prompt
    end
    prompt:SetTitle(title)
    prompt.input:SetLabel(label)
    prompt.input:SetText(value or "")
    prompt.ok:SetText(action or "OK")
    prompt.onDone = onDone
    prompt.onAlt = alternative and alternative.onDone or nil
    prompt.alt:SetText(alternative and alternative.caption or "")
    prompt.alt:SetShown(alternative ~= nil)
    prompt:Show()
    if prompt.input.box then prompt.input.box:SetFocus() end
end

function Editor:OpenSettings()
    local draft = self.draft
    local settings = self.settings
    if not settings then
        settings = ui():Window({ key = "editorSettings", title = "Guide settings", width = 460, height = 300,
            place = self.places, hidden = true })
        local body = settings:Column{ gap = 10, padding = 14 }
        settings.title = body:Input{ label = "Title", onChange = function(text)
            self:Soft(self.draft.SetGuideField, self.draft, "title", trim(text))
        end }
        settings.category = body:Input{ label = "Folder", placeholder = "Leveling/The Barrens", onChange = function(text)
            self:Soft(self.draft.SetGuideField, self.draft, "category", trim(text) ~= "" and trim(text) or "Personal")
        end }
        local levels = body:Row{ gap = 8, valign = "bottom" }
        local function setLevels()
            local from, to = tonumber(trim(settings.from:GetText())), tonumber(trim(settings.to:GetText()))
            self:Soft(self.draft.SetGuideField, self.draft, "levels", from and to and { from = from, to = to } or nil)
        end
        settings.from = levels:Input{ label = "Levels from", width = 90, onChange = setLevels }
        settings.to = levels:Input{ label = "to", width = 90, onChange = setLevels }
        settings.author = body:Input{ label = "Author", onChange = function(text)
            self:Soft(self.draft.SetGuideField, self.draft, "author", trim(text))
        end }
        self.settings = settings
    end
    local guide = draft.guide
    settings.title:SetText(guide.title or "")
    settings.category:SetText(guide.category or "")
    settings.from:SetText(guide.levels and tostring(guide.levels.from) or "")
    settings.to:SetText(guide.levels and tostring(guide.levels.to) or "")
    settings.author:SetText(guide.author or "")
    settings:Show()
end

-- A window of text to edit and apply: the guide or a step as text, or an import.
function Editor:TextWindow(title, text, hint, onApply, action)
    local win = self.textWin
    if not win then
        win = ui():Window({ key = "editorText", title = title, width = 640, height = 520, resizable = true,
            minWidth = 420, minHeight = 300, place = self.places, hidden = true })
        local body = win:Column{ gap = 8, padding = 12 }
        win.hint = body:Text{ "", style = "fine", color = "muted", wrap = true }
        win.area = body:TextArea{ grow = true, boxHeight = 360 }
        win.problem = body:Text{ "", color = "danger", wrap = true }
        local buttons = body:Row{ gap = 6 }
        buttons:Spacer{}
        buttons:Button{ "Cancel", onClick = function() win:Hide() end }
        win.apply = buttons:Button{ "Apply", tone = "accent", onClick = function()
            local ok, problem = win.onApply(win.area:GetText())
            if ok == false or ok == nil and problem then
                win.problem:SetText(problem or "That text cannot be used.")
            else
                win:Hide()
            end
        end }
        self.textWin = win
    end
    win:SetTitle(title)
    win.hint:SetText(hint or "")
    win.area:SetText(text or "")
    win.problem:SetText("")
    win.apply:SetText(action or "Apply")
    win.onApply = onApply
    win:Show()
end

function Editor:EditGuideAsText()
    local draft = self.draft
    self:TextWindow("Edit as text", draft:Text(),
        "The guide as a guide file writes it (docs/examples/guide-v1.lua). Apply replaces it; Undo brings it back.",
        function(text)
            local ok, problem = self:Hard(draft.ReplaceFromText, draft, text)
            return ok, problem
        end)
end

function Editor:EditStepAsText(step)
    local draft = self.draft
    self:TextWindow("Step as text", M("GuideText"):WriteStep(step),
        "This step as a guide file writes it. Apply replaces it; Undo brings it back.",
        function(text) return self:Hard(draft.ReplaceStepFromText, draft, step, text) end)
end

function Editor:CopyAsText()
    local copy = self.copyWin
    if not copy then
        copy = ui():CopyWindow{ key = "editorCopy", place = self.places, title = "Copy as text" }
        self.copyWin = copy
    end
    copy:Show(self.draft:Text(), "Copy as text")
end

function Editor:ImportFromText()
    self:TextWindow("Import from text", "",
        "Paste a guide someone shared (format v1). It becomes a new guide of your own; nothing you have is changed.",
        function(text)
            local value, problem = M("GuideText"):Read(text)
            if not value then return false, problem end
            if value.kind ~= "guide" then return false, "That is not a whole guide: it needs kind = \"guide\"." end
            local built, why, draft = M("GuideRepository"):Import(value)
            if not built then return false, why end
            self:Attach(draft, 1)
            self:RenderAll()
            self:SetStatus("Imported as a guide of your own.")
            return true
        end, "Import")
end

-- Who sees a step: classes, race, faction, and what the player chose.
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RACES = { "orc", "tauren", "troll", "scourge", "human", "dwarf", "gnome", "nightelf" }
local RACE_NAMES = { orc = "Orc", tauren = "Tauren", troll = "Troll", scourge = "Undead", human = "Human", dwarf = "Dwarf",
    gnome = "Gnome", nightelf = "Night elf" }

local function simpleCond(cond)
    if cond == nil then return true end
    if type(cond) ~= "table" then return false end
    for key in pairs(cond) do
        if key ~= "class" and key ~= "race" and key ~= "faction" and key ~= "hardcore" and key ~= "season" then return false end
    end
    return true
end

local function simpleShow(show)
    if show == nil then return true end
    if type(show) ~= "table" then return false end
    for key in pairs(show) do
        if key ~= "skill" and key ~= "ah" and key ~= "selffound" then return false end
    end
    return true
end

function Editor:OpenShownTo(step, steps)
    local draft = self.draft
    steps = steps and #steps > 1 and steps or nil
    if not (simpleCond(step.cond) and simpleShow(step.show)) then
        self:EditStepAsText(step)
        self:SetStatus("This step's rule is more than the choices can show: edit it as text.")
        return
    end
    local win = self.shownWin
    if win then win:Hide() end
    win = ui():Window({ key = "editorShown", title = "Shown to", width = 440, height = 420, place = self.places, hidden = true })
    self.shownWin = win
    local cond = GuideDraftCopy(step.cond or {})
    local show = GuideDraftCopy(step.show or {})
    local body = win:Column{ gap = 10, padding = 14 }
    win:SetTitle(steps and ("Shown to: " .. #steps .. " steps") or "Shown to")
    local function apply()
        if next(cond) == nil then cond = nil end
        if next(show) == nil then show = nil end
        if steps then
            self:Hard(draft.SetFieldsMany, draft, steps, { cond = cond or false, show = show or false }, "who")
        else
            self:Hard(draft.SetFields, draft, step, { cond = cond or false, show = show or false }, "who")
        end
        cond, show = cond or {}, show or {}
    end
    body:Text{ "Class", style = "label" }
    local chosen = {}
    for _, class in ipairs(list(cond.class)) do chosen[class] = true end
    local grid = body:Row{ gap = 4 }
    local count = 0
    for _, class in ipairs(CLASSES) do
        if count == 5 then grid = body:Row{ gap = 4 } count = 0 end
        count = count + 1
        grid:Toggle{ CLASS_NAMES[class], value = chosen[class] == true, onChange = function(on)
            chosen[class] = on or nil
            local out = {}
            for _, name in ipairs(CLASSES) do if chosen[name] then out[#out + 1] = name end end
            cond.class = #out == 1 and out[1] or (#out > 1 and out or nil)
            apply()
        end }
    end
    body:Text{ "Race", style = "label" }
    local raceOptions = { { value = "", caption = "Any" } }
    for _, race in ipairs(RACES) do raceOptions[#raceOptions + 1] = { value = race, caption = RACE_NAMES[race] } end
    body:Select{ boxWidth = 180, options = raceOptions, value = type(cond.race) == "string" and cond.race or "", onChange = function(value)
        cond.race = value ~= "" and value or nil
        apply()
    end }
    body:Text{ "What they chose", style = "label" }
    local professions = sortedOptions(idNames("skills"), { { value = 0, caption = "Any" } })
    local skillRow = body:Row{ gap = 8, valign = "center" }
    skillRow:Text{ "Knows the profession", width = 150 }
    skillRow:SearchSelect{ boxWidth = 180, options = professions, value = type(show.skill) == "number" and show.skill or 0,
        onChange = function(value) show.skill = value ~= 0 and value or nil; apply() end }
    local yesNo = { { value = 0, caption = "Any" }, { value = 1, caption = "Yes" } }
    local ahRow = body:Row{ gap = 8, valign = "center" }
    ahRow:Text{ "Uses the auction house", width = 150 }
    ahRow:Select{ boxWidth = 120, options = yesNo, value = show.ah and 1 or 0, onChange = function(value)
        show.ah = value == 1 or nil; apply()
    end }
    local sfRow = body:Row{ gap = 8, valign = "center" }
    sfRow:Text{ "Plays self found", width = 150 }
    sfRow:Select{ boxWidth = 120, options = yesNo, value = show.selffound and 1 or 0, onChange = function(value)
        show.selffound = value == 1 or nil; apply()
    end }
    local buttons = body:Row{ gap = 6 }
    buttons:Button{ "Everyone", onClick = function()
        cond, show = {}, {}
        apply()
        win:Hide()
    end }
    buttons:Spacer{}
    buttons:Button{ "Done", tone = "accent", onClick = function() win:Hide() end }
    win:Show()
end

-- Caves and tunnels: the Places panel, in a window of its own, on the
-- guide's places in the shape it edits. What it changes is kept when it
-- reports, and when the window closes.
function Editor:OpenPlaces()
    local Places = M("PlacesPanel")
    if not Places then return self:Problem("The places panel is not available.") end
    if not self.placesWin then
        local win = ui():Window({ key = "editorPlaces", title = "Caves and tunnels", width = 520, height = 560,
            resizable = true, minWidth = 440, minHeight = 420, place = self.places, hidden = true })
        win:HookScript("OnHide", function()
            Editor:SyncPlaces()
            -- Synced: an undo after this must not be overwritten by a stale
            -- copy. Put away for the recorder, the copy is what it walks.
            if not Editor.recording then Editor.working = nil end
            Editor.recording = nil
            Places:DrawMap()
        end)
        self.placesWin = win
        local page = win:Column{ gap = 8, padding = 12 }
        self.placesHost = { win = win, editor = self }
        -- The panel calls back into its editor: these answer for this one.
        local host = setmetatable(self.placesHost, { __index = function(_, key)
            if key == "working" then return Editor.working end
            if key == "activeTab" then return win:IsShown() and "places" or nil end
            return nil
        end })
        function host:SetStatus(text, isError) Editor:SetStatus(text, isError) end
        function host:Hide()
            Editor.recording = true
            win:Hide()
        end
        Places:Build(host, page)
    end
    if not self.working then
        self.working = { id = self.draft.guide.id, places = self.draft:RuntimePlaces(), nodes = {} }
        if Places.Reset then Places:Reset() end
    end
    self.placesWin:Show()
    Places:Render()
end

-- The places the recorder adds a walk to: the guide in the editor, or the
-- one followed opened in it, with the places window shown.
function Editor:PlacesGuide()
    if not self.draft then
        local Progress = M("Progress")
        self:OpenGuide(Progress and Progress:GetActiveGuide())
    end
    if not self.draft then return nil end
    self:OpenPlaces()
    return self.working
end

-- Kept: what the Places panel or the recorder made of the places.
function Editor:SyncPlaces()
    if self.syncing or not (self.draft and self.working and self.working.places) then return end
    self.syncing = true
    self:Hard(self.draft.SetPlaces, self.draft, self.working.places)
    self.syncing = false
end

-- What the place recorder calls: the places window, shown.
function Editor:SelectTab(tab)
    if tab == "places" then
        if not self.draft then
            local Progress = M("Progress")
            self:OpenGuide(Progress and Progress:GetActiveGuide())
        end
        if self.draft then self:OpenPlaces() end
    end
end

-- Shift-click ----------------------------------------------------------------------------------------

-- A link with no field in focus: the page's field of its kind takes it.
function Editor:LinkToPage(link)
    for kind, pattern in pairs(LINK) do
        local id = tonumber(link:match(pattern))
        local targets = id and self.linkTargets and self.linkTargets[kind]
        if targets then
            local add = targets.quests or targets.quest or targets.item or targets.spells or targets.spell
            if kind == "quest" and (targets.turnin or targets.accept) then
                local client = Client()
                local ready = client and (client:IsQuestReadyToTurnIn(id) or client:IsQuestComplete(id))
                add = ready and targets.turnin or targets.accept or targets.turnin
            end
            if add then return add({ id }) end
        end
    end
end

-- A shift-clicked item, quest or spell goes into the editor's field that
-- has the keyboard, as it would into chat. The client's own handling is
-- left as it is; with one of these fields in focus, chat is not open.
function Editor:HookLinks()
    if self.linksHooked then return end
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) ~= "function" or type(rawget(_G, "ChatEdit_InsertLink")) ~= "function" then return end
    self.linksHooked = true
    hook("ChatEdit_InsertLink", function(link) Editor:InsertLink(link) end)
end

function Editor:InsertLink(link)
    if not self:IsShown() or type(link) ~= "string" then return end
    local focus = rawget(_G, "GetCurrentKeyBoardFocus")
    local box = type(focus) == "function" and focus() or nil
    local field = box and box.kitOwner
    local data = field and field.data
    if not (data and data.onIDs) then
        if box then return end
        return self:LinkToPage(link)
    end
    local id
    if data.link then
        id = tonumber(link:match(LINK[data.link] or "^$"))
    else
        for _, pattern in pairs(LINK) do id = id or tonumber(link:match(pattern)) end
    end
    if not id then
        self:Problem("That link is not " .. (data.link and ("a" .. (data.link == "item" and "n " or " ") .. data.link) or "one this field takes") .. ".")
        return
    end
    box:ClearFocus()
    data.onIDs({ id })
end

ns:RegisterModule("Editor", Editor)
