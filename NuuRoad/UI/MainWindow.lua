local _, ns = ...

-- The tracker, ported from OpenRoad's UI/MainWindow.lua onto NuuKit, and
-- stacked the way an established guide addon stacks it: carried work on
-- top, then the current step as a card -- one line per goal, each with an
-- icon for its kind, a status wash behind the icon (amber in progress,
-- green done, red a goal the player has no quest for), names coloured by
-- role, and a tooltip -- and under both, the guide itself as a list of
-- single-line steps. The list scrolls a whole step at a time, so a row is
-- never cut in half, and clicking a row moves the guide there.
--
-- Built from kit parts: an in-play Panel (placed and sized by width through
-- the kit's window placement, NuuRoadDB.windows.tracker), its band holding
-- the guide's name and every control the tracker has (back, the step
-- counter that doubles as a jump box, skip, the menu, close), a strip of
-- Tabs for the guides open (shown while there are two or more), a SegmentBar
-- for the progress bar (a scrubber too), Cards for the step and the carried
-- work, and a List for the steps. The tracker's height follows what the
-- step asks for; only its width is the player's.
--
-- The options window and the Diagnostics window are UI/Options.lua's; the
-- menu reaches them, and ToggleOptions / ShowDiagnostics forward there.
local MainWindow = {}

-- The tracker's width is the player's, dragged from the corner grip and kept
-- in the kit's placement; MIN and MAX are how far the grip goes.
local WIDTH, MIN_WIDTH, MAX_WIDTH = 360, 300, 640
-- The body's padding and the room between its parts (bar, cards, list).
local PAD, GAP = 10, 6
-- A card's padding, and the width of its rail (the kit's Card).
local CARD_PAD, RAIL = 5, 3
-- A goal line: the icon, the room between the line's parts, the smallest
-- height, the gap between two lines, the indent of a detail line.
-- OpenRoad's measure: a 12 icon, text at 10 (the "fine" size, in the text
-- colour), 15 the shortest line.
local ICON, SPACING, LINE, LINE_GAP = 12, 6, 15, 1
local LINE_STYLE = "fine"
local INDENT = ICON + SPACING
-- The distance column on a goal line. The width is fixed and reserved
-- whether or not the number is short, so the text beside it keeps its wrap
-- while the player walks and only the digits change.
local AWAY_WIDTH = 42
-- The guide list under the cards: one step per row, every row the same
-- height, which is what lets the wheel move it a whole step at a time.
-- The number column fits three digits, and the row starts just clear of
-- the selection rail, so the list has no margin of its own at the left.
local LIST_ROW, LIST_NUMBER, LIST_PAD, LIST_ICON = 19, 22, 5, 13
-- The progress bar's strip.
local BAR_HEIGHT = 6
-- A guide's tab: the widest and narrowest it is cut to. Below the narrowest
-- the tabs that do not fit go into the "+N" menu at the end of the strip,
-- which takes about MORE_WIDTH.
local TAB_MAX, TAB_MIN, TAB_GAP, MORE_WIDTH = 170, 90, 2, 34
-- The height the tracker never goes under.
local MIN_HEIGHT = 95
local ACTION_DEBOUNCE, REFRESH_THROTTLE, AWAY_THROTTLE = 0.3, 0.2, 0.25

local NO_OPTS = {}

local function M(name) return ns.modules[name] end
local function now() return GetTime and GetTime() or 0 end

-- The report of an error in a hook (another module's code): to the error
-- handler, without stopping the tracker.
local function report(err)
    local handler = rawget(_G, "geterrorhandler")
    if type(handler) == "function" then pcall(handler(), err) end
end

-- Calls module `name`'s `method` when both exist; true when it ran.
local function call(name, method, ...)
    local module = ns.modules[name]
    local fn = module and module[method]
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, module, ...)
    if not ok then report(err) end
    return ok
end

-- NuuProfessions' optional API, looked up when used (never at load): nil
-- when the addon is not installed or speaks another version.
local function professionsAPI()
    local addon = rawget(_G, "NuuProfessions")
    local api = type(addon) == "table" and addon.API or nil
    if type(api) == "table" and api.apiVersion == 1 then return api end
    return nil
end

function MainWindow:UI() return ns:GetUI() end
local function tokens() return ns:GetUI().tokens end
local function color(name)
    local t = tokens()
    if type(name) == "table" then return name end
    return ns.Kit.UI.Colour(t, name) or t.text
end
local function rgb(name)
    local c = color(name)
    return c[1], c[2], c[3]
end

-- Icons -------------------------------------------------------------------------------

-- Blizzard textures present in both the classic-era and modern clients. When
-- the client cannot load one, the ASCII glyph takes its place.
--
-- Every path here is UI art with an alpha channel, never `Interface/Icons`:
-- an inventory icon is an opaque square with its own dark background, which
-- over the tracker's translucent panel reads as a black tile next to the
-- cut-out gossip marks. A verb with no fitting alpha texture wears its glyph.
-- The minimap's tracking art says what a service is (the binder icon came
-- out as the gossip cog in this client).
local goalIcons = {
    accept = "Interface/GossipFrame/AvailableQuestIcon",
    turnin = "Interface/GossipFrame/ActiveQuestIcon",
    objective = "Interface/GossipFrame/IncompleteQuestIcon",
    escort = "Interface/GossipFrame/IncompleteQuestIcon",
    talk = "Interface/GossipFrame/ChatBubbleGossipIcon",
    kill = "Interface/TargetingFrame/UI-RaidTargetingIcon_8",
    collect = "Interface/GroupFrame/UI-Group-MasterLooter",
    interact = "Interface/Cursor/Interact",
    use = "Interface/Cursor/Interact",
    travel = "Interface/AddOns/NuuRoad/Art/WaypointArrow.tga",
    hearth = "Interface/Minimap/Tracking/Innkeeper",
    flight = "Interface/Minimap/Tracking/FlightMaster",
    level = "Interface/Buttons/Arrow-Up-Up",
    done = "Interface/RaidFrame/ReadyCheck-Ready",
    note = "Interface/Buttons/UI-GuildButton-PublicNote-Up",
    train = "Interface/Minimap/Tracking/Class",
    skill = "Interface/Minimap/Tracking/Profession",
    craft = "Interface/Minimap/Tracking/Profession",
    buy = "Interface/MoneyFrame/UI-GoldIcon",
    gather = "Interface/Minimap/Tracking/Profession",
}
local goalGlyphs = {
    accept = "!", turnin = "?", objective = "x", escort = "&", talk = "?!", kill = "x", collect = "o", interact = "*", use = "*", travel = "->",
    hearth = "H", flight = "F", level = "L", done = "v", skipped = ">>", note = "-", choice = "Y", ["end"] = ".", reminder = "~",
    train = "T", skill = "S", craft = "C", buy = "$", equip = "E", reputation = "R", gather = "g",
}
-- Icon for a whole step, on the single-line rows.
local kindIcon = {
    acceptQuest = "accept", turnInQuest = "turnin", talk = "turnin", questObjective = "objective", objectiveGroup = "objective", escort = "escort",
    kill = "kill", collect = "collect", loot = "collect", interact = "interact", travel = "travel", hearth = "hearth",
    flight = "flight", levelTarget = "level", note = "note", action = "note", choice = "choice", ["end"] = "end", reminder = "reminder",
    train = "train", cast = "use", skillTarget = "skill", craft = "craft", skillUp = "craft", gather = "gather", buy = "buy", equip = "equip", reputationTarget = "reputation",
}
-- A material's icon says where it comes from, the same way the step verbs do.
local materialIcons = { gather = "gather", vendor = "buy", ah = "buy", craft = "craft", drop = "kill" }

-- Shows `key`'s icon (or `path`, an item's own texture) on `texture`, else
-- its glyph on `glyph`. `tint` colours a flat verb icon; an item's own
-- texture is shown as the game draws it. Answers whether the texture loaded.
local function setIcon(texture, glyph, key, tint, path)
    local own = path ~= nil
    path = path or (key and goalIcons[key])
    local loaded = false
    if path then
        local set = texture:SetTexture(path)
        loaded = set ~= false and texture:GetTexture() ~= nil
    end
    if loaded then
        -- An item's icon arrives as a file ID as often as a path, and both
        -- want the border trimmed the way every icon in the game does.
        local cropped = type(path) == "number" or tostring(path):lower():gsub("\\", "/"):find("^interface/icons/") ~= nil
        if cropped then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) else texture:SetTexCoord(0, 1, 0, 1) end
        if own then texture:SetVertexColor(1, 1, 1, 1) else texture:SetVertexColor(tint[1], tint[2], tint[3], 1) end
        texture:Show()
        glyph:SetText("")
        glyph:Hide()
    else
        texture:Hide()
        glyph:SetText(key and (goalGlyphs[key] or "-") or "")
        glyph:SetTextColor(tint[1], tint[2], tint[3], 1)
        glyph:Show()
    end
    return loaded
end

-- Names in goal text --------------------------------------------------------------------

-- Names inside goal text wear the look's colours: quests in the quest
-- yellow, NPCs in the accent, creatures to kill in the danger colour. An
-- item is painted the way the game paints it everywhere else: the client's
-- own link when it has one, so the name wears its quality colour and
-- answers a hover and a click, and the quality colour alone while the item
-- is still being fetched.
local roleTokens = { quest = "quest", npc = "accent", monster = "danger", item = "text", location = "warning", count = "text" }
local roleCodes, roleCodesFor = {}, nil
local function codeOf(role)
    local t = tokens()
    if roleCodesFor ~= t then
        roleCodes, roleCodesFor = {}, t
        for key, name in pairs(roleTokens) do roleCodes[key] = ns.Kit.UI.ColorCode(color(name)) end
    end
    return roleCodes[role]
end

-- Markers to draw in front of the creatures' names, id -> raid icon, read
-- once per repaint. Only the markers a press through NuuRoad put on: an icon
-- on a step line means that press landed. A marker the player set by hand is
-- left to the target strip.
local liveMarkers = {}
local function readMarkers()
    local NPCTracking, TargetMarking = M("NPCTracking"), M("TargetMarking")
    liveMarkers = {}
    if not NPCTracking or not TargetMarking or not TargetMarking.MarkedByUs then return end
    if not NPCTracking:Enabled("markTargets") then return end
    liveMarkers = TargetMarking:MarkedByUs() or {}
end

local markerRoles = { monster = true, npc = true }
-- The marker goes inline, immediately in front of the name it belongs to,
-- as a texture escape: the only way a line naming several creatures can
-- show each one's marker against its own name.
local function markGlyph(id)
    local marker = id and liveMarkers[id]
    if not marker then return "" end
    return "|TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. marker .. ":0|t"
end

local function paint(role, text, piece)
    if role == "item" and piece and piece.id then
        local Client = M("Client")
        local link = Client and Client.GetItemLink and Client:GetItemLink(piece.id)
        if link then return link end
        if Client and Client.RequestItemData then Client:RequestItemData(piece.id) end
        local hex = Client and Client.GetItemQualityColor and Client:GetItemQualityColor(piece.id)
        if hex then return "|c" .. hex .. text .. "|r" end
    end
    local code = roleCodes and role and codeOf(role)
    if not code or role == "item" or text == nil or text == "" then return text end
    local painted = code .. text .. "|r"
    if markerRoles[role] and piece then painted = markGlyph(piece.id) .. painted end
    return painted
end

-- Statuses -------------------------------------------------------------------------------

-- Work not yet started is the normal state of a goal and carries no wash;
-- amber is work under way, green work done, and red a goal the player has
-- no quest for: the one state that needs their attention.
local statusTints = { active = "warning", done = "done", settled = "done", moot = "danger" }
local statusWords = {
    done = "Done", active = "In progress", todo = "Not done yet",
    settled = "Not needed: the work after this step is already done",
    moot = "Not yours to do: the quest is not in your log and was never finished",
    failed = "Failed: abandon the quest and take it again",
}
-- Statuses that mean there is nothing here for the player to do.
local quietStatus = { done = true, settled = true, moot = true }

-- The NPC of a "Talk to" line without the "Talk to": what a folded goal line
-- hangs its "from" or "to" on, painted the way the header would have been.
local function talkTarget(lead)
    local out = {}
    for index = 2, #(lead.parts or {}) do
        local piece = lead.parts[index]
        table.insert(out, paint(piece.role, piece.text, piece))
    end
    return table.concat(out)
end

-- A quest goal wearing the visit's NPC, so a folded line's tooltip still
-- names who hands it over.
local function withNPCs(goal, npcs)
    local copy = {}
    for key, value in pairs(goal) do copy[key] = value end
    copy.npcs = npcs
    return copy
end
local liveObjectiveKinds = { questObjective = true, objectiveGroup = true, kill = true, collect = true }

-- A quest or creature ID in a tooltip is for checking a guide, so it shows
-- only with the debug log on.
local function idText(id)
    local Config = M("Config")
    if not (Config and Config:Get("debug")) then return "" end
    return "  (ID " .. id .. ")"
end

-- Goal lines ----------------------------------------------------------------------------

-- An item name on a line is a real game link, so the line answers for it the
-- way a chat frame does: the item's own tooltip on hover, and the client's
-- own handler on click (Shift-click into chat, Ctrl-click the dressing
-- room). A client without hyperlink support simply shows the coloured name.
local function linkEnter(row, link, text)
    MainWindow:UI():Tooltip(row, function(tip)
        if not pcall(tip.SetHyperlink, tip, link) then tip:SetText(text or "", 1, 1, 1) end
    end, { anchor = "ANCHOR_RIGHT" })
end
local function linkLeave() MainWindow:UI():HideTooltip() end
local function linkClick(_, link, text, button)
    if type(SetItemRef) == "function" then pcall(SetItemRef, link, text, button) end
end

local function lineClicked(row, button)
    if button ~= "LeftButton" then return end
    local onClick = row.data
    if type(onClick) == "function" then onClick() end
end

-- The measure of a wrapped line: a hidden font string of the tracker's own,
-- in the goal text's style. A kit row measures a wrapping text on one line,
-- so a goal line's height is worked out here and given to its row.
function MainWindow:Measure(text, width)
    local probe = self.probe
    ns.Kit.UI.ApplyStyle(probe, LINE_STYLE, tokens())
    if width then
        probe:SetWidth(math.max(1, width))
        probe:SetText(text or "")
        return math.ceil(probe:GetStringHeight() or 12)
    end
    probe:SetWidth(0)
    probe:SetText(text or "")
    return math.ceil(ns.Kit.UI.StringWidth(probe)) + 1
end

-- Opens a card in `holder` (a column of the body) for the lines that follow.
function MainWindow:OpenCard(holder, tone)
    holder:Clear()
    holder:Show()
    -- A card's rail takes a tone or a colour; muted is a colour of the look.
    if tone == "muted" then tone = color("muted") end
    self.card = holder:Card{ tone = tone, padding = CARD_PAD, gap = LINE_GAP }
    self.cardButtons = false
    -- What a line in the card has to lay its text out in.
    local inner = (self.frame:GetWidth() or WIDTH) - 2 - 2 * PAD
    self.lineWidth = inner - RAIL - 2 * CARD_PAD
    return self.card
end

-- A line that already says how many ("Collect 9 ...", what is still owed)
-- does not repeat it as a figure at the right; the tooltip keeps have/need.
local function saysCount(goal)
    for _, piece in ipairs(goal.parts or NO_OPTS) do
        if piece.role == "count" and piece.text ~= "" then return true end
    end
    return false
end

-- One goal line on the open card. opts: icon (goal verb), iconPath (a
-- texture instead of the verb's own), iconColor (a token or colour), marker
-- (a glyph instead of an icon), status (todo/active/done/settled/moot),
-- color (a token), alpha, indent, tooltip, onClick, count (a figure at the
-- right, in countColor), away (a step location to measure to, printed in
-- the right-hand column and kept live while the player moves).
function MainWindow:AddLine(text, opts)
    opts = opts or NO_OPTS
    local ui = self:UI()
    local t = ui.tokens
    local card = self.card
    text = text or ""
    local indent = opts.indent and INDENT or 0
    local countWidth = opts.count and self:Measure(opts.count) or 0
    -- An indent is a part of the row of its own, so the row's gap follows it.
    local textWidth = self.lineWidth - indent - (indent > 0 and SPACING or 0) - ICON - SPACING
        - (opts.count and (countWidth + SPACING) or 0) - (opts.away and (AWAY_WIDTH + SPACING) or 0)
    local height = math.max(LINE, self:Measure(text, textWidth) + 2)
    local links = string.find(text, "|H", 1, true) ~= nil
    local row = card:Row{ gap = SPACING, padding = 1, padLeft = 0, padRight = 0, height = height,
        tooltip = opts.tooltip, data = opts.onClick }
    if indent > 0 then row:Spacer{ size = indent } end
    row:Spacer{ size = ICON }
    -- The text is held to the height measured for it: the row is that tall
    -- already, and the text is not measured again.
    row:Text{ text, style = LINE_STYLE, wrap = true, grow = true, valign = "top", color = opts.color or "text",
        height = height - 2 }
    if opts.count then
        row:Text{ opts.count, style = LINE_STYLE, valign = "top", width = countWidth, color = opts.countColor or "text" }
    end
    -- How far the step's place is, in the accent, where the eye already goes
    -- to compare one line against another (OpenRoad's).
    local away
    if opts.away then
        away = row:Text{ "", valign = "top", width = AWAY_WIDTH, justify = "RIGHT", style = "key", color = "accent" }
    end

    -- The icon, its glyph when the art is missing, and the status wash
    -- across the whole line, as OpenRoad drew it: amber under way, green
    -- done, red not yours. Decorations the kit keeps with the row.
    local tint = opts.status and statusTints[opts.status]
    if tint then
        local wash = row:AddTexture("BACKGROUND")
        wash:SetAllPoints()
        ns.Kit.UI.TexColor(wash, ns.Kit.UI.Faded(t, color(tint), tint == "done" and 0.18 or 0.16))
    end
    local icon = row:AddTexture("ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", indent, -1)
    local glyph = row:AddText("fine")
    glyph:SetWidth(ICON + 4)
    glyph:SetJustifyH("CENTER")
    glyph:SetPoint("TOP", icon, "TOP", 0, 0)
    if opts.marker then
        icon:Hide()
        glyph:SetText(opts.marker)
        local c = color(opts.iconColor or "accent")
        glyph:SetTextColor(c[1], c[2], c[3], 1)
    elseif opts.icon or opts.iconPath then
        setIcon(icon, glyph, opts.icon, color(opts.iconColor or "text"), opts.iconPath)
    else
        icon:Hide()
        glyph:SetText("")
    end
    if opts.alpha then row:SetAlpha(opts.alpha) end

    -- Only a line with something to say on hover, a click, or a link takes
    -- the mouse; the frame is changed for it, and marked.
    if opts.tooltip ~= nil or opts.onClick or links then
        row:Customize(ui.Custom.frame)
        row:EnableMouse(true)
        if opts.onClick then row:SetScript("OnMouseUp", lineClicked) end
        if links and type(row.SetHyperlinksEnabled) == "function" and pcall(row.SetHyperlinksEnabled, row, true) then
            row:SetScript("OnHyperlinkEnter", linkEnter)
            row:SetScript("OnHyperlinkLeave", linkLeave)
            row:SetScript("OnHyperlinkClick", linkClick)
        end
    end
    if away then
        local entry = { text = away, location = opts.away }
        table.insert(self.awayLines, entry)
        self:UpdateDistance(entry)
    end
    return row
end

-- One line's distance column, re-read from the client. Nothing here relays
-- out the tracker: the column's width is reserved, so the number changing
-- costs only the text.
function MainWindow:UpdateDistance(entry)
    local Navigation = M("Navigation")
    local away = Navigation and Navigation.ShortAway and Navigation:ShortAway(entry.location)
    entry.text:SetText(away or "")
end

-- Walking changes no game event, so the distances would sit still between
-- repaints; this is the only thing the tracker polls for.
function MainWindow:UpdateDistances()
    for _, entry in ipairs(self.awayLines or {}) do self:UpdateDistance(entry) end
end

-- A full-width button on the card: a choice, Done, or Make on a craft step.
-- A disabled one says why in its tooltip.
function MainWindow:AddCardButton(text, onClick, enabled, tooltip, tone)
    local card = self.card
    if not self.cardButtons then
        card:Spacer{ size = 3 }
        self.cardButtons = true
    end
    local disabled = enabled == false
    local button = card:Button{ text, stretch = true, tone = tone, onClick = onClick,
        tooltip = (not disabled) and tooltip or nil }
    if disabled then button:SetEnabled(false, tooltip) end
    return button
end

function MainWindow:AddChoiceButton(guide, choice, index)
    self:AddCardButton(choice.title or ("Choice " .. index), function()
        if not self:AcceptAction() then return end
        M("Progress"):Complete(guide, nil, "complete", choice["next"])
        self:Refresh()
    end)
end

-- The Make button ---------------------------------------------------------------------------

-- What a craft or skill-up step's Make button asks the profession window
-- for (Kit.Crafting): { profession, spell, item, count, untilSkill }, or nil
-- when the step makes nothing more. A skill-up step makes what the skill
-- still needs and stops there; a craft step makes what is short of its
-- count, and stops at its `upto` skill in the same profession. The recipe
-- data is NuuProfessions' (its API); without it, a skill-up makes as many
-- as the materials allow, stopped at the skill, and a craft counts one
-- made per craft.
function MainWindow:MakeOrder(node)
    local auto = node and node.auto
    if not auto or not auto.item or type(auto.skill) ~= "string" then return nil end
    if auto.verb ~= "craft" and auto.verb ~= "skillup" then return nil end
    local Crafting, Client = ns.Kit.Crafting, M("Client")
    if not Crafting or not Client then return nil end
    local api = professionsAPI()
    local recipe, spell
    if api and api.Recipe then
        local ok, found, foundSpell = pcall(api.Recipe, auto.skill, nil, auto.item)
        if ok then recipe, spell = found, foundSpell end
    end
    local order = { profession = auto.skill, spell = spell, item = auto.item }
    local skill = Client:GetSkillRank(auto.skill)
    if auto.verb == "skillup" then
        if skill and skill >= auto.rank then return nil end
        order.untilSkill = auto.rank
        -- A recipe the data does not know: as many as the materials allow,
        -- stopped at the skill. One that gives no skill on the way from the
        -- skill now is past its use: no button.
        if skill and recipe then
            local skills
            if api and api.Skills and spell then
                local ok, answer = pcall(api.Skills, auto.skill, spell)
                if ok then skills = answer end
            end
            order.count = Crafting:ToSkill(recipe, skill, auto.rank, nil, skills)
            -- A planned step with only what is carried: the crafts the bags make.
            if api and api.CarriedCrafts and spell then
                local ok, exact = pcall(api.CarriedCrafts, auto.skill, spell, auto.rank)
                if ok and exact then order.count = exact end
            end
            if not order.count then return nil end
        else
            order.count = math.huge
        end
    else
        local Steps = M("Steps")
        local made = Steps and Steps.CraftCount and Steps:CraftCount(node) or 0
        local have = math.max(made, Client:GetItemCount(auto.item, true) or 0)
        order.count = Crafting:ForItems(auto.count or 1, have, Crafting:AverageMade(recipe))
        local upto = auto.upto
        if upto and type(upto.skill) == "string" and upto.skill:lower() == auto.skill:lower() then
            if skill and skill >= upto.rank then return nil end
            order.untilSkill = upto.rank
        end
    end
    if not order.count or order.count <= 0 then return nil end
    order.recipe = recipe
    return order
end

-- The Make button on the current craft step (Crafting:Button): a batch
-- through the open profession window, else opening the window on the
-- recipe, else what is missing, on the button itself.
local MAKE_BLOCKED = { closed = "Open %s to make it here", missing = "Not in your %s window",
    materials = "No materials for one" }

function MainWindow:AddMakeButton(node)
    local order = self:MakeOrder(node)
    if not order then return nil end
    local Client, Crafting, Names = M("Client"), ns.Kit.Crafting, M("Names")
    local name = Names and Names:DescribeItem(order.item) or ("item " .. tostring(order.item))
    local found, why, other = Client:FindCraft(order.profession, order.spell, order.item)
    local carried = Crafting:CanMake(order.recipe, function(item) return Client:GetItemCount(item, true) end)
    local state = Crafting:Button(order, name, found, why, other, Client:CanOpenProfession(order.profession), carried)
    local text
    if state.mode == "window" then
        text = "Make " .. state.count .. " x " .. name
    elseif state.mode == "open" then
        text = "Open " .. order.profession .. " on " .. name
    else
        text = string.format(MAKE_BLOCKED[state.why] or MAKE_BLOCKED.closed, order.profession)
    end
    self.makeState = state
    return self:AddCardButton(text, function()
        if state.mode == "open" then
            Client:OpenProfession(order.profession, order.spell, order.item)
            return
        end
        local made, reason, otherWindow = Client:Craft(order.profession, order.spell, order.item, order.count,
            order.untilSkill, carried)
        if not made then ns:Print(Crafting:Why(reason, order.profession, otherWindow)) end
    end, state.mode ~= nil, state.words, "accent")
end

-- Tooltips ------------------------------------------------------------------------------------

-- Where a step is, said the way the player reads a map: the zone when the
-- client will name it, then the coordinates, then how far off it is.
local function addLocationLine(tip, node)
    local location = node and node.location
    if not location or type(location.x) ~= "number" or type(location.y) ~= "number" then return end
    local Client = M("Client")
    local zone = Client and Client.GetMapName and Client:GetMapName(location.mapID)
    tip:AddLine(string.format("Location: %s%.1f, %.1f", zone and (zone .. "  ") or "", location.x * 100, location.y * 100), 1, 0.9, 0.6)
    local Navigation = M("Navigation")
    local away = Navigation and Navigation.Measure and Navigation:Measure(location)
    if away and away ~= "" then tip:AddLine(away, 1, 0.9, 0.6) end
end

-- Marks and colours for a goal inside a step tooltip: the same reading the
-- card gives, in the one place a single-line row can show it.
local goalTipMarks = { done = "v", settled = "v", active = "~", moot = "x", todo = "-" }
local goalTipColors = { done = "done", settled = "done", active = "warning", moot = "danger", todo = "text" }

local function collect(list, id)
    if not id then return end
    for _, seen in ipairs(list) do if seen == id then return end end
    table.insert(list, id)
end

-- Tooltip for one goal line: only what the line cannot say. The item's own
-- tooltip, the quest and NPCs it names, and a status the line shows only as
-- a colour; the distance is on the line and the note on the card, so neither
-- is repeated. A goal that names nothing more has no tooltip.
local explainedStatus = { settled = true, moot = true, failed = true }

function MainWindow:GoalTooltip(goal, node, status)
    if not (goal.item or goal.upto or goal.quest or (goal.npcs and #goal.npcs > 0) or explainedStatus[status]) then return nil end
    return function(tip)
        local Names, Steps = M("Names"), M("Steps")
        local shown = goal.item and tip.SetItemByID and pcall(tip.SetItemByID, tip, goal.item)
        if not shown then tip:SetText(Steps:GoalText(goal), 1, 1, 1, 1, true) end
        if goal.upto then
            tip:AddLine("Or " .. goal.upto.skill .. " " .. goal.upto.rank
                .. ": whichever comes first. Past that skill this is not needed at all, so the step finishes however little was done.", 0.6, 0.8, 0.95, true)
        end
        if goal.quest then
            local label = goal.startsQuest and "Starts quest: " or "Quest: "
            tip:AddLine(label .. Names:DescribeQuest(goal.quest) .. idText(goal.quest), 0.85, 0.7, 1)
        end
        for _, id in ipairs(goal.npcs or {}) do tip:AddLine("NPC: " .. Names:DescribeNPC(id) .. idText(id), 0.7, 0.94, 0.7) end
        if explainedStatus[status] then tip:AddLine(statusWords[status], 0.7, 0.7, 0.7, true) end
    end
end

-- Tooltip for a whole step: the rows in the guide list and the carried work
-- above the card are one line each, so the tooltip is where the step itself
-- is said -- what it asks for goal by goal, with the same live status the
-- current card shows, then the quests and creatures it names, where it is,
-- how far, and its note unless the note is drawn under the line already.
-- `hint` says something about the step the row cannot (its group, or that
-- the guide waits on it); it comes last, under the step, never instead of it.
function MainWindow:StepTooltip(node, hint, noteShown)
    return function(tip)
        local Names, Steps = M("Names"), M("Steps")
        local title = Steps:Title(node)
        tip:SetText(title ~= "" and title or "Step", 1, 1, 1, 1, true)
        local goals = Steps:Goals(node)
        -- A step with one goal is its own title already.
        local spelled = #goals > 1
        local quests, npcs = {}, {}
        for _, goal in ipairs(goals) do
            local status, progress = Steps:GoalStatus(goal, node)
            if spelled then
                local text = Steps:GoalText(goal)
                if progress then text = text .. "  (" .. progress .. ")" end
                local r, g, b = rgb(goalTipColors[status] or "text")
                tip:AddLine((goalTipMarks[status] or goalTipMarks.todo) .. " " .. text, r, g, b, true)
            elseif status then
                tip:AddLine(statusWords[status] .. (progress and ("  " .. progress) or ""), 0.7, 0.7, 0.7)
            end
            collect(quests, goal.quest)
            for _, id in ipairs(goal.npcs or {}) do collect(npcs, id) end
        end
        for _, id in ipairs(node.refs and node.refs.npcs or {}) do collect(npcs, id) end
        for _, id in ipairs(quests) do
            tip:AddLine("Quest: " .. Names:DescribeQuest(id) .. idText(id), 0.85, 0.7, 1)
        end
        for _, id in ipairs(npcs) do
            tip:AddLine("NPC: " .. Names:DescribeNPC(id) .. idText(id), 0.7, 0.94, 0.7)
        end
        addLocationLine(tip, node)
        if node.wait then tip:AddLine("Takes about " .. tostring(node.wait) .. " seconds", 0.7, 0.7, 0.7) end
        for _, id in ipairs(node.watch or {}) do
            tip:AddLine("Watch for " .. Names:DescribeNPC(id), 0.7, 0.7, 0.7)
        end
        local condition = node.condition and Steps:DescribeCondition(node.condition)
        if condition and condition ~= "" then tip:AddLine("Only " .. condition, 0.7, 0.8, 0.95, true) end
        if not noteShown and node.body and node.body ~= "" and node.body ~= title then
            tip:AddLine(" "); tip:AddLine(node.body, 0.9, 0.9, 0.9, true)
        end
        if hint and hint ~= "" then tip:AddLine(" "); tip:AddLine(hint, 0.5, 0.8, 0.95, true) end
    end
end

-- Tooltip for a sticky quest line: the quest itself, and every objective of
-- it with the client's own progress, since the line shows only the one the
-- player is furthest from.
function MainWindow:StickyTooltip(questID)
    return function(tip)
        local Client, Names = M("Client"), M("Names")
        tip:SetText(Names:DescribeQuest(questID), 1, 1, 1, 1, true)
        if idText(questID) ~= "" then tip:AddLine("Quest ID " .. questID, 0.85, 0.7, 1) end
        for index = 1, 12 do
            local finished, text = Client:GetQuestObjective(questID, index)
            if finished == nil then break end
            if text and text ~= "" then
                if finished then tip:AddLine("v " .. text, 0.5, 0.85, 0.5, true)
                else tip:AddLine("- " .. text, 0.9, 0.9, 0.9, true) end
            end
        end
    end
end

-- Navigation -------------------------------------------------------------------------------

-- Manual controls ignore a second click that lands within a fraction of a
-- second of the first, so a double-click never advances two steps.
function MainWindow:AcceptAction()
    local time = now()
    if self.lastAction and time - self.lastAction < ACTION_DEBOUNCE then return false end
    self.lastAction = time
    return true
end

-- After any navigation (back, skip, the jump box, the scrubber, a list row):
-- the hold on the step landed on is judged at once rather than on the next
-- poll. A step that already reads done keeps it; one still to do drops it
-- right away, so finishing the step auto-continues the guide.
function MainWindow:Landed()
    call("ObservedProgress", "LapseHold")
end

-- Moves forward until `stepIndex` is current, recording the steps passed as
-- skipped, the same as pressing skip that many times.
function MainWindow:JumpTo(guide, stepIndex)
    local Progress = M("Progress")
    for _ = 1, #guide.nodes do
        local node = Progress:GetCurrentNode(guide)
        if not node or node.index == stepIndex then break end
        if not Progress:Forward(guide) then break end
    end
end

-- Moving to a step the player picked: forward records the steps passed over
-- as skipped, the way skip does; back is navigation only and rewrites nothing.
function MainWindow:JumpAction(guide, target)
    return function()
        if not self:AcceptAction() then return end
        local Progress = M("Progress")
        local current = Progress:GetCurrentIndex(guide)
        if current and target.index > current then
            self:JumpTo(guide, target.index)
        else
            Progress:GoTo(guide, target.index)
        end
        self:Landed()
        self:Refresh()
    end
end

-- Back and skip. Each moves one step and holds the step it lands on while it
-- reads done, so a finished step is not passed over again on arrival; the
-- hold lapses once the step reads incomplete. With Shift they walk on past
-- every step that reads done, to the first still to do in that direction.
function MainWindow:Step(direction)
    if not self:AcceptAction() then return end
    local Progress, Client, Observed = M("Progress"), M("Client"), M("ObservedProgress")
    local guide = Progress:GetActiveGuide()
    if guide then
        local shift = Client and Client.IsShiftDown and Client:IsShiftDown()
        if direction > 0 then
            if shift and Observed then Observed:SkipToOutstanding(guide) else Progress:Forward(guide) end
        else
            if shift and Observed then Observed:BackToOutstanding(guide) else Progress:Back(guide) end
        end
        self:Landed()
    end
    self:Refresh()
end

local function backClicked() MainWindow:Step(-1) end
local function skipClicked() MainWindow:Step(1) end
local function menuClicked() MainWindow:ToggleMenu() end
local function closeClicked() MainWindow:Toggle() end
local function counterClicked() MainWindow:ToggleJumpBox() end
local function jumpCommitted(text) MainWindow:JumpToNumber(text) end

-- The window -------------------------------------------------------------------------------

-- The tracker's width as it stands.
function MainWindow:Width()
    local frame = self.frame
    local width = frame and frame:GetWidth() or WIDTH
    if not width or width <= 0 then width = WIDTH end
    return width
end

-- The width is the kit's placement now (dragged from the grip); what hangs
-- on it is laid out again on the next refresh.
function MainWindow:ApplyWidth()
    self:RequestRefresh()
end

-- The tracker's own scale ("Tracker size"). The arrow and the strips beside
-- the tracker scale themselves from the same setting.
function MainWindow:ApplyDisplaySettings()
    local frame = self.frame
    if not frame then return end
    local Config = M("Config")
    local scale = tonumber(Config and Config:Get("tracker.scale")) or 1
    if scale <= 0 then scale = 1 end
    frame:SetScale(scale)
end
MainWindow.ApplyPanelOpacity = MainWindow.ApplyDisplaySettings

-- Which way the tracker grows ("Grow upward"). Downward, from the band at
-- the top: tabs, bar, carried work, the step's card, the step list. Upward
-- the band is at the foot and the same parts stack up from it, so the list
-- is on top; its rows still count up the page.
function MainWindow:Upward()
    local Config = M("Config")
    return Config and Config:Get("tracker.upward") and true or false
end

function MainWindow:ApplyDirection()
    local frame = self.frame
    if not frame then return end
    local upward = self:Upward()
    frame:SetUpward(upward)
    local order = { self.tabRow, self.bar, self.stickyHolder, self.cardHolder, self.listHolder }
    if upward then
        for index = 1, math.floor(#order / 2) do
            order[index], order[#order + 1 - index] = order[#order + 1 - index], order[index]
        end
    end
    self.content:Order(order)
end

function MainWindow:CreateTracker()
    if self.frame then return self.frame end
    local ui = self:UI()
    local places = ns.db and ns.db.windows
    local frame = ui:Panel({
        key = "tracker", place = places, inPlay = true, title = "NuuRoad",
        width = WIDTH, height = 160, resizable = "width", minWidth = MIN_WIDTH, maxWidth = MAX_WIDTH,
        upward = self:Upward(),
        point = { "RIGHT", UIParent, "RIGHT", -60, 120 },
        hidden = true,
    })
    self.frame = frame

    -- The band carries every control: back and skip flank the counter, so
    -- the step the player is on sits between the two ways of leaving it;
    -- the counter doubles as a jump box; then the menu and close.
    local header = frame.header
    self.back = header:GlyphButton{ "back", size = 22, glyphSize = 9, onClick = backClicked,
        tooltip = "Back one step. Shift: back to the first step still to do." }
    self.counter = header:Link{ "", style = "number", color = "text", onClick = counterClicked,
        tooltip = "Click to jump to a step number, forward or back." }
    self.jump = header:Input{ width = 64, numeric = true, compact = true, maxLetters = 4, placeholder = "step #",
        onChange = jumpCommitted, hidden = true }
    self.skip = header:GlyphButton{ "next", size = 22, glyphSize = 9, onClick = skipClicked,
        tooltip = "Skip one step. Shift: forward to the first step still to do." }
    self.menuButton = header:GlyphButton{ "menu", size = 22, glyphSize = 9, onClick = menuClicked,
        tooltip = "Guides, this guide's own actions, and the addon's settings" }
    self.close = header:GlyphButton{ "close", size = 22, glyphSize = 9, onClick = closeClicked,
        tooltip = "Hide the tracker. The minimap button brings it back." }

    local content = frame:Column{ padding = PAD, gap = GAP }
    self.content = content
    -- The open guides' tabs, made again whenever the guides open change.
    self.tabRow = content:Row{ gap = 4 }
    self.tabRow:Hide()
    -- The bar is one continuous strip of the guide, and a scrubber: click or
    -- drag it to move there.
    self.bar = content:SegmentBar{ min = 0, max = 1, barHeight = BAR_HEIGHT, scrub = true,
        tooltipFor = function(value) return MainWindow:ScrubTooltip(value) end,
        onPick = function(value) MainWindow:ScrubTo(value) end }
    -- Carried work, the step's card, and the guide list, each in a column of
    -- its own so they keep their order however often the cards are made.
    self.stickyHolder = content:Column{ gap = 0 }
    self.cardHolder = content:Column{ gap = 0 }
    self.listHolder = content:Column{ gap = 0 }
    self.stickyHolder:Hide()
    self.awayLines = {}

    -- A plain frame of the tracker's own: its beat (the coalesced refresh,
    -- the distances, the POI log), and the font string that measures lines.
    local ticker = CreateFrame("Frame", nil, frame)
    ticker:SetScript("OnUpdate", function(_, elapsed) MainWindow:Tick(elapsed) end)
    self.ticker = ticker
    local probe = ticker:CreateFontString(nil, "OVERLAY")
    probe:SetFont(ns.Kit.UI.FontFile(), 11, "")
    if probe.SetWordWrap then probe:SetWordWrap(true) end
    probe:Hide()
    self.probe = probe

    self:BuildList()
    self:ApplyDirection()
    return frame
end

-- Repaint requests from game events are coalesced here: a burst of quest
-- log updates costs one repaint, and a hidden tracker costs none.
function MainWindow:Tick(elapsed)
    self.awayWait = (self.awayWait or 0) + elapsed
    if self.awayWait >= AWAY_THROTTLE then
        self.awayWait = 0
        self:UpdateDistances()
        -- On the same beat as the distances, because the POI log wants the
        -- step sampled while the player walks it. Throttled inside.
        local POILog = M("POILog")
        if POILog then
            if POILog.Sync then POILog:Sync(self.currentNode) end
            if POILog.Pump then POILog:Pump() end
        end
    end
    -- The jump box goes when it loses the keyboard (Escape, a click away).
    if self.jumpOpen and not self.jump:HasFocus() then self:HideJumpBox() end
    -- The grip changed the width: the lines wrap again.
    local width = self.frame:GetWidth()
    if width and self.laidWidth and math.abs(width - self.laidWidth) >= 1 then
        self.laidWidth = width
        self:RequestRefresh()
    end
    if not self.refreshPending then return end
    self.refreshWait = (self.refreshWait or 0) + elapsed
    if self.refreshWait < REFRESH_THROTTLE then return end
    self:Refresh()
end

-- The band: the guide's name, and the section the player is in as its
-- subtitle, cut to fit beside the controls.
function MainWindow:SetGuideTitle(title, section)
    local frame = self.frame
    local UI = ns.Kit.UI
    frame:SetSubtitle(section or "")
    frame:SetTitle(title or "")
    local room = self:Width() - 2 - 6 - 12 - 8 - 8 - (frame.header:NaturalWidth() or 0) - 8
    if section and section ~= "" and UI.StringWidth(frame.title) + UI.StringWidth(frame.subtitle) > room then
        frame:SetSubtitle("")
    end
    room = room - UI.StringWidth(frame.subtitle)
    if UI.StringWidth(frame.title) <= room or not title then return end
    local low, high = 0, #title
    while low < high do
        local mid = math.floor((low + high + 1) / 2)
        frame:SetTitle(title:sub(1, mid) .. "...")
        if UI.StringWidth(frame.title) <= room then low = mid else high = mid - 1 end
    end
    frame:SetTitle(title:sub(1, low) .. "...")
end

-- The step counter. With no guide there is no count and nothing to step
-- through, so the counter and the back and skip buttons that flank it all
-- go; the jump box stands in the place of both the counter and back.
function MainWindow:SetStatus(text)
    if not self.frame then return end
    local running = text and text ~= ""
    if not running then self.skip:SetHighlighted(false) end
    self.statusText = text or ""
    self.counter:SetText(self.statusText)
    local jumping = self.jumpOpen
    self.counter:SetShown(running and not jumping)
    self.back:SetShown(running and not jumping)
    self.skip:SetShown(running and true or false)
end

-- The jump box ------------------------------------------------------------------------------

function MainWindow:HideJumpBox()
    if not self.jumpOpen then return end
    self.jumpOpen = false
    self.jump:SetText("")
    if self.jump:HasFocus() then self.jump:ClearFocus() end
    self.jump:Hide()
    self:SetStatus(self.statusText)
end

function MainWindow:ToggleJumpBox()
    if self.jumpOpen then self:HideJumpBox(); return end
    local Progress = M("Progress")
    local guide = Progress and Progress:GetActiveGuide()
    if not guide then return end
    self:UI():HideTooltip()
    self.jumpOpen = true
    self.counter:Hide()
    self.back:Hide()
    self.jump:Show()
    self.jump:SetText("")
    self.jump:SetPlaceholder("1 - " .. #guide.nodes)
    self.jump:SetFocus()
end

-- Moves to the step with that number, in either direction. A number that
-- belongs to another character's step lands on the next step of this
-- character's. The step is held, so one already finished is not advanced
-- past on arrival.
function MainWindow:JumpToNumber(text)
    local Progress = M("Progress")
    local guide = Progress:GetActiveGuide()
    if not guide then self:HideJumpBox(); return end
    local steps = self:CharacterSteps(guide)
    local index = tonumber(text)
    if not index or index < 1 or index > #guide.nodes or index % 1 ~= 0 then
        ns:Print("Enter a step number between 1 and " .. #guide.nodes .. ".")
        self.jump:SetText("")
        return
    end
    local target = steps[#steps]
    for _, candidate in ipairs(steps) do
        if candidate.index >= index then target = candidate; break end
    end
    self:HideJumpBox()
    if not target then return end
    local ok, err = Progress:GoTo(guide, target.index)
    if not ok then ns:Print(err or "That step cannot be opened.") end
    self:Landed()
    self:Refresh()
end

-- The tabs -------------------------------------------------------------------------------------

-- A tab's caption: the guide's title. Its tooltip repeats it for a caption
-- the tab cuts short.
local function tabCaption(guide)
    return guide.meta and guide.meta.title or guide.id
end

local function tabChosen(key) MainWindow:ShowGuide(key) end
local function tabClosed(key) MainWindow:CloseGuide(key) end
local function moreClicked(link) MainWindow:OpenMoreTabs(link) end

-- Shows an open guide: the tracker follows it from here, and the load-time
-- scan catches it up on what was done while it was not shown.
function MainWindow:ShowGuide(id)
    local guide = M("GuideRepository"):Get(id)
    if not guide then return end
    M("Progress"):Select(guide)
    self:Landed()
    self:Refresh()
end

function MainWindow:CloseGuide(id)
    local guide = M("GuideRepository"):Get(id) or { id = id }
    M("Progress"):Close(guide)
    self:Landed()
    self:Refresh()
end

-- The guides open that the strip had no room for, to show one.
function MainWindow:OpenMoreTabs(anchor)
    local items = {}
    for _, guide in ipairs(self.moreGuides or {}) do
        local id = guide.id
        table.insert(items, { caption = guide.meta and guide.meta.title or id, onClick = function() self:ShowGuide(id) end })
    end
    self:UI():OpenMenu(items, { anchor = anchor, align = "right", above = self:Upward() })
end

-- The strip shows while two or more guides are open. Each tab is cut to
-- share the width; when even the narrowest would not fit, the strip keeps
-- as many as fit (always the shown guide) and the rest are behind "+N".
-- It is made again only when the guides, the one shown or the width change.
function MainWindow:SyncTabs(active)
    local Progress = M("Progress")
    local open = Progress and Progress.OpenGuides and Progress:OpenGuides() or {}
    local row = self.tabRow
    if not active or #open < 2 then
        if self.tabsKey then
            row:Clear()
            row:Hide()
            self.tabsKey, self.moreGuides = nil, nil
        end
        return
    end
    local room = math.floor(self:Width()) - 2 - 2 * PAD
    local parts = { tostring(room), active.id }
    for _, guide in ipairs(open) do
        table.insert(parts, guide.id)
        table.insert(parts, tostring(guide.updated))
        table.insert(parts, tostring(guide.meta and guide.meta.title))
    end
    local key = table.concat(parts, "|")
    if key == self.tabsKey then return end
    self.tabsKey = key

    local shown, more = open, {}
    local width = math.floor((room - (#open - 1) * TAB_GAP) / #open)
    if width < TAB_MIN then
        local fit = math.max(1, math.floor((room - MORE_WIDTH - 4 + TAB_GAP) / (TAB_MIN + TAB_GAP)))
        width = math.floor((room - MORE_WIDTH - 4 - (fit - 1) * TAB_GAP) / fit)
        local activeAt = 1
        for index, guide in ipairs(open) do
            if guide.id == active.id then activeAt = index end
        end
        shown = {}
        for index, guide in ipairs(open) do
            local keep = index < fit or (index == fit and activeAt <= fit) or index == activeAt
            if keep then table.insert(shown, guide) else table.insert(more, guide) end
        end
    end
    local spec = { value = active.id, pages = false, compact = true, divided = true, grow = 1,
        maxTabWidth = math.min(TAB_MAX, width), onChange = tabChosen, onClose = tabClosed }
    for _, guide in ipairs(shown) do
        table.insert(spec, { key = guide.id, caption = tabCaption(guide),
            tooltip = guide.meta and guide.meta.title or guide.id })
    end
    row:Clear()
    row:Tabs(spec)
    if #more > 0 then
        row:Link{ "+" .. #more, valign = "center", onClick = moreClicked,
            tooltip = "More open guides" }
    end
    self.moreGuides = more
    row:Show()
end

-- The progress bar -----------------------------------------------------------------------------

-- The guide's sections as runs of bar positions, in order. A section's steps
-- are contiguous once imported, so each is its first and last position.
local function sectionSpans(guide, positions)
    local spans = {}
    if not guide or type(guide.sections) ~= "table" then return spans end
    if not positions then
        positions = {}
        for position, node in ipairs(guide.nodes) do positions[node.index] = position end
    end
    for _, section in ipairs(guide.sections) do
        local first, last
        for _, nodeIndex in ipairs(section.nodeIndexes or {}) do
            local position = positions[nodeIndex]
            if position then
                if not first or position < first then first = position end
                if not last or position > last then last = position end
            end
        end
        if first then table.insert(spans, { first = first, last = last, title = section.title or "" }) end
    end
    table.sort(spans, function(a, b) return a.first < b.first end)
    return spans
end

-- The title of the section the player is in, when the guide has more than one.
local function sectionTitle(guide, position)
    local spans = sectionSpans(guide)
    if #spans < 2 then return nil end
    for _, span in ipairs(spans) do
        if position >= span.first and position <= span.last and span.title ~= "" then return span.title end
    end
    return nil
end

-- The guide's steps as this character has it, and each one's place among
-- them: what the progress bar is divided into. The numbers the player reads
-- (counter, list, jump box, bar tooltip) are the guide's own step indexes.
-- Worked out again on every refresh, since an edit can change the guide.
function MainWindow:CharacterSteps(guide)
    if self.numberedGuide ~= guide or not self.numberedSteps then
        self.numberedSteps, self.stepNumbers = M("Progress"):CharacterSteps(guide)
        self.numberedGuide = guide
    end
    return self.numberedSteps, self.stepNumbers
end

-- Where the player stands among those steps: the step they are on, or the
-- last one before it when it is not one of them, or the end once finished.
function MainWindow:BarPosition(guide, node)
    local steps, numbers = self:CharacterSteps(guide)
    if not node then return #steps end
    if numbers[node.index] then return numbers[node.index] end
    local number = 0
    for slot, candidate in ipairs(steps) do
        if candidate.index > node.index then break end
        number = slot
    end
    return number
end

function MainWindow:StepState(guide, candidate, position, state)
    local Progress, GuideScan = M("Progress"), M("GuideScan")
    if (GuideScan and GuideScan:IsStepDone(guide, candidate, state))
        or (state ~= nil and Progress:IsDone(state.statuses[candidate.index])) then
        return "done"
    end
    -- Amber only when the player asked for it; off, a step not open yet reads
    -- as passed or ahead like any other.
    local Config = M("Config")
    if not Progress:IsAvailable(candidate) and Config and Config:Get("tracker.markWaiting") == true then return "gated" end
    return position >= candidate.index and "passed" or "ahead"
end

-- Each step painted for what it is to this character: green once done,
-- amber where the guide waits on it (when asked), the accent for a step
-- already passed but not done, and the bar's own track for what is still
-- ahead. A run of one state is one segment. A pointer stands on the step
-- the player is on. With more than one section, a hairline marks where each
-- section starts and the section the player is in is outlined.
local stepTones = { done = { "done", 0.9 }, gated = { "warning", 0.8 }, passed = { "accent", 0.6 } }

function MainWindow:PaintProgress(guide, position)
    local bar = self.bar
    self.tipCache = {}
    local steps, numbers = {}, {}
    if guide then steps, numbers = self:CharacterSteps(guide) end
    local total = #steps
    if total == 0 then
        bar:SetRange(0, 1)
        bar:SetSegments(nil)
        bar:SetMarks(nil)
        return
    end
    position = position or 0
    local state = M("Progress"):PeekState(guide)
    local segments = {}
    local runStart, runKind = 1, nil
    local function flush(runEnd)
        local tone = stepTones[runKind]
        if tone then table.insert(segments, { from = runStart - 1, to = runEnd, tone = tone[1], alpha = tone[2] }) end
    end
    for index = 1, total do
        local kind = self:StepState(guide, steps[index], position, state)
        if runKind and kind ~= runKind then flush(index - 1); runStart = index end
        runKind = kind
    end
    flush(total)
    local here = math.min(math.max(self:BarPosition(guide, guide.nodes[position]), 1), total)
    local marks = { { at = here - 0.5, kind = "pointer" } }
    local spans = sectionSpans(guide, numbers)
    if #spans > 1 then
        for number, span in ipairs(spans) do
            if number > 1 then table.insert(marks, { at = span.first - 1, tone = "muted" }) end
            if here >= span.first and here <= span.last then
                table.insert(segments, { from = span.first - 1, to = span.last, style = "outline", tone = "accent", alpha = 0.5 })
            end
        end
    end
    bar:SetRange(0, total)
    bar:SetSegments(segments)
    bar:SetMarks(marks)
end

-- The step under the cursor on the bar: step `number` owns the slice from
-- number - 1 to number.
function MainWindow:ScrubIndex(value)
    local Progress = M("Progress")
    local guide = Progress and Progress:GetActiveGuide()
    if not guide or not value then return nil end
    local steps = self:CharacterSteps(guide)
    local total = #steps
    if total == 0 then return nil end
    local number = math.floor(value) + 1
    if number < 1 then number = 1 elseif number > total then number = total end
    return number, guide, steps[number]
end

-- Clicking or dragging the bar is the jump box by another route: the same
-- navigation, so nothing is recorded as skipped and the step is held.
function MainWindow:ScrubTo(value)
    local index, guide, node = self:ScrubIndex(value)
    if not index then return end
    local Progress = M("Progress")
    if (Progress:GetCurrentNode(guide)) == node then return end
    Progress:GoTo(guide, node.index)
    self:Landed()
    -- Coalesced, so dragging across a long guide repaints a few times, not
    -- once per step passed.
    self:RequestRefresh()
end

-- What hovering the bar says about the step under the cursor: one filler
-- per step, kept until the next refresh, so the tooltip is only drawn again
-- when the cursor crosses into another step.
function MainWindow:ScrubTooltip(value)
    local index, guide, node = self:ScrubIndex(value)
    if not index then return nil end
    self.tipCache = self.tipCache or {}
    local cached = self.tipCache[index]
    if cached then return cached end
    local filler = function(tip)
        local Progress, Steps, GuideScan = M("Progress"), M("Steps"), M("GuideScan")
        local _, numbers = self:CharacterSteps(guide)
        tip:SetText("Step " .. node.index .. " / " .. #guide.nodes, 1, 1, 1)
        local spans = sectionSpans(guide, numbers)
        if #spans > 1 then
            for _, span in ipairs(spans) do
                if index >= span.first and index <= span.last then
                    local r, g, b = rgb("accent")
                    tip:AddLine(span.title, r, g, b, true)
                end
            end
        end
        tip:AddLine(Steps:Title(node), 0.9, 0.9, 0.9, true)
        local current = Progress:GetCurrentNode(guide)
        local kind = self:StepState(guide, node, current and current.index or #guide.nodes, Progress:PeekState(guide))
        local warn = { rgb("warning") }
        if kind == "done" then
            local r, g, b = rgb("done")
            tip:AddLine("Done.", r, g, b, true)
        elseif Progress:IsRuledOut(node) then
            tip:AddLine("Not for this character; the guide passes over it.", warn[1], warn[2], warn[3], true)
        elseif Progress:IsWaiting(node) then
            tip:AddLine("Not open to you yet; the guide will wait on it.", warn[1], warn[2], warn[3], true)
        elseif not Progress:IsAvailable(node) then
            tip:AddLine("No longer needed; the guide passes over it.", warn[1], warn[2], warn[3], true)
        elseif GuideScan and GuideScan:NodeIsMoot(node) then
            local r, g, b = rgb("danger")
            tip:AddLine("You do not have this quest; the guide will wait on it.", r, g, b, true)
        elseif kind == "passed" and node ~= current then
            local r, g, b = rgb("accent")
            tip:AddLine("Passed without being done.", r, g, b, true)
        end
        tip:AddLine("Click or drag the bar to jump here.", 0.6, 0.6, 0.6)
    end
    self.tipCache[index] = filler
    return filler
end

-- The guide list -----------------------------------------------------------------------------

function MainWindow:ListSettings()
    local Config = M("Config")
    return Config and Config:Get("stepList") or { rows = 0 }
end

-- The steps the list shows, in flow order. Only steps this character can
-- never do (wrong class, race, faction) are left out; one gated on a quest or
-- a level stays, muted, since it may yet open. Carried steps are left out
-- because they are drawn with the step that carries them, and reminders
-- because they are not a stop.
function MainWindow:BuildListNodes(guide, node)
    local Progress = M("Progress")
    local nodes, current = {}, nil
    for _, candidate in ipairs(guide.nodes) do
        local show = candidate.kind ~= "reminder" and not Progress:IsRuledOut(candidate) and not Progress:IsCarried(candidate)
        if show then
            table.insert(nodes, candidate)
            if candidate == node then current = #nodes end
        end
    end
    return nodes, current
end

local LIST_TIP = { anchor = "ANCHOR_RIGHT" }

local function listNumber(node) return tostring(node.index) end

-- Once per row: the icon's slot and the icon (or its glyph), and the step's
-- one-line title.
local function makeListRow(row)
    row.slot = row:Spacer{ size = LIST_ICON }
    row.icon = row:AddTexture("ARTWORK")
    row.icon:SetSize(LIST_ICON - 1, LIST_ICON - 1)
    row.icon:SetPoint("CENTER", row.slot, "CENTER", 0, 0)
    row.glyph = row:AddText("fine")
    row.glyph:SetPoint("CENTER", row.slot, "CENTER", 0, 0)
    row.title = row:Text{ "", grow = true }
end

local function drawListRow(row, node, at) MainWindow:DrawListRow(row, node, at) end
local function listPicked(node) MainWindow:ListPicked(node) end
local function listTooltip(node) return MainWindow:ListTooltip(node), LIST_TIP end

-- The list for `rows` rows (0: none). Made again only when that count
-- changes; otherwise its items change in place.
function MainWindow:BuildList(rows)
    rows = math.floor(tonumber(rows) or 0)
    if self.listRows == rows and (rows <= 0 or self.list) then return end
    self.listHolder:Clear()
    self.list, self.listRows = nil, rows
    if rows <= 0 then
        self.listHolder:Hide()
        return
    end
    self.listHolder:Show()
    self.list = self.listHolder:List{
        rows = rows, rowHeight = LIST_ROW, gap = SPACING, wheelRows = 1, dividers = false, padLeft = LIST_PAD,
        numbers = listNumber, numberWidth = LIST_NUMBER,
        make = makeListRow, draw = drawListRow, onPick = listPicked, tooltip = listTooltip,
    }
    self.listAnchor = nil
end

-- Places the list under the cards and fills it. Nothing is drawn when the
-- player has set the row count to zero, or when there is no guide.
function MainWindow:LayoutStepList(guide, node)
    local wanted = math.floor(tonumber(self:ListSettings().rows) or 0)
    if wanted <= 0 or not guide then
        self:BuildList(0)
        self.listNodes = nil
        return
    end
    local nodes, current = self:BuildListNodes(guide, node)
    if #nodes == 0 then
        self:BuildList(0)
        self.listNodes = nil
        return
    end
    local visible = math.min(wanted, #nodes)
    self:BuildList(visible)
    local Progress = M("Progress")
    self.listNodes, self.listCurrent, self.listGuide = nodes, current, guide
    self.listState = Progress:PeekState(guide)
    local list = self.list
    -- A step change takes the list back to the step, two rows down so the
    -- ones just done stay in view; a list the player scrolled stays put
    -- until the guide moves on.
    local anchor = node and node.index or false
    if self.listAnchor ~= anchor then
        self.listAnchor = anchor
        list:SetItems(nodes)
        local offset = (current or 1) - 3
        if offset > #nodes - visible then offset = #nodes - visible end
        if offset < 0 then offset = 0 end
        list:ScrollSet(offset)
    else
        list:SetItems(nodes, true)
    end
    list:Select(current and nodes[current] or nil)
end

function MainWindow:ListDone(node)
    local guide, state = self.listGuide, self.listState
    local GuideScan = M("GuideScan")
    if GuideScan then return GuideScan:IsStepDone(guide, node, state) end
    return state ~= nil and M("Progress"):IsDone(state.statuses[node.index])
end

-- One row for `node`: the step's own number (the one the counter, the jump
-- box and a bug report speak; the list hides reminders, carried steps and
-- other characters' steps, so the numbers skip where those sit), the icon
-- for its verb, and its title. Done, gated and moot steps read muted; the
-- current one is the list's selection.
function MainWindow:DrawListRow(row, node, at)
    local Progress, GuideScan, Steps = M("Progress"), M("GuideScan"), M("Steps")
    local isCurrent = node == (self.listNodes and self.listNodes[self.listCurrent or 0])
    local isDone = not isCurrent and self:ListDone(node)
    local gated = not isCurrent and not isDone and not Progress:IsAvailable(node)
    local moot = not isDone and not gated and GuideScan and GuideScan:NodeIsMoot(node)
    row.title:SetText(Steps:Title(node))
    row.title:SetColor((isCurrent and "accent") or ((isDone or gated or moot) and "muted") or "text")
    -- The quest icons are the game's own yellow art, so a tint multiplies
    -- into their colour; the current row shows the art as it is.
    local tint = (isDone and "done") or (moot and "danger") or (isCurrent and "text") or "muted"
    setIcon(row.icon, row.glyph, kindIcon[node.kind] or "note", color(tint))
end

function MainWindow:ListTooltip(node)
    local Progress, GuideScan = M("Progress"), M("GuideScan")
    local isCurrent = node == (self.listNodes and self.listNodes[self.listCurrent or 0])
    local isDone = not isCurrent and self:ListDone(node)
    local gated = not isCurrent and not isDone and not Progress:IsAvailable(node)
    local moot = not isDone and not gated and GuideScan and GuideScan:NodeIsMoot(node)
    return self:StepTooltip(node,
        (gated and "Not open to you yet; the guide will wait on it."
            or moot and "You do not have this quest; the guide will wait on it." or ""))
end

function MainWindow:ListPicked(node)
    local guide = self.listGuide
    if not guide or not node then return end
    self:JumpAction(guide, node)()
end

-- Live lines ------------------------------------------------------------------------------------

-- Unfinished objective lines of the current step's quests, straight from the
-- quest log, so kill and collect counts update live.
function MainWindow:LiveObjectiveLines(node)
    local lines = {}
    if not liveObjectiveKinds[node.kind] or (node.auto and node.auto.part) or not node.refs or not node.refs.quests then return lines end
    local Client = M("Client")
    for _, questID in ipairs(node.refs.quests) do
        if Client:IsQuestInLog(questID) then
            for _, objective in ipairs(Client:GetQuestObjectives(questID) or {}) do
                if not objective.finished and objective.text and objective.text ~= "" and #lines < 4 then table.insert(lines, objective.text) end
            end
        end
    end
    return lines
end

-- The objective step the guide later spends on a sticky quest, preferring the
-- one whose item the client's objective line names (a quest can ask for two
-- things, each with its own step).
local function stickyStep(guide, questID, detail)
    local Names = M("Names")
    local first
    local lowered = detail and string.lower(detail)
    for _, candidate in ipairs(guide.nodes or {}) do
        local auto = candidate.auto
        if auto and (auto.verb == "objective" or auto.verb == "objectives") then
            for _, id in ipairs(auto.quests or {}) do
                if id == questID then
                    first = first or auto
                    local item = auto.collect and auto.collect[1]
                    local itemName = item and Names:DescribeItem(item)
                    if lowered and itemName and string.find(lowered, string.lower(itemName), 1, true) then
                        return auto
                    end
                end
            end
        end
    end
    return first
end

-- The icon for a sticky quest is that of its objective step: a bag for a
-- collect, a skull for kills, the quest marker when the guide has no such step.
local function stickyIcon(auto)
    if auto and auto.collect then return "collect" end
    if auto and auto.kill then return "kill" end
    return "objective"
end

-- Tracked quests that are in the log and not yet ready to turn in, as
-- { text, icon, questID }, with the client's first unfinished objective line
-- where it has one. Loot names the creature it drops from, the first one and
-- "..." when there are more, since that is what the player hunts; the quest
-- name goes. Otherwise the quest name leads, and is dropped when the
-- objective already says it (a quest named after its item).
function MainWindow:StickyLines(guide, node)
    local lines = {}
    local Client, Names = M("Client"), M("Names")
    for _, questID in ipairs(M("Steps"):ActiveTracks(guide, node) or {}) do
        if Client:IsQuestInLog(questID) and not Client:IsQuestReadyToTurnIn(questID) then
            local detail
            for index = 1, 6 do
                local finished, text = Client:GetQuestObjective(questID, index)
                if finished == nil then break end
                if not finished and text and text ~= "" then detail = text break end
            end
            local auto = stickyStep(guide, questID, detail)
            local name = Names:DescribeQuest(questID)
            local text
            if detail and auto and auto.collect and auto.kill and auto.kill[1] then
                local item = auto.collect[1]
                local have, need = string.match(detail, "(%d+)%s*/%s*(%d+)")
                text = (have and (have .. "/" .. need .. " ") or "")
                    .. paint("item", Names:DescribeItem(item), { id = item })
                    .. " from " .. paint("monster", Names:DescribeNPC(auto.kill[1]), { id = auto.kill[1] })
                    .. (auto.kill[2] and "..." or "")
            elseif detail and string.find(string.lower(detail), string.lower(name), 1, true) then
                text = detail
            else
                text = name .. (detail and (" - " .. detail) or "")
            end
            table.insert(lines, { text = text, icon = stickyIcon(auto), questID = questID })
        end
    end
    return lines
end

-- The refresh -----------------------------------------------------------------------------------

-- The cards go back to the kit's pools before each drawing: the step changes
-- their shape.
function MainWindow:BeginCards()
    self.awayLines = {}
    self.card, self.makeState = nil, nil
    self.stickyHolder:Clear()
    self.stickyHolder:Hide()
    self.cardHolder:Clear()
end

-- The height follows what the step asks for: laid out now, then measured.
function MainWindow:FinishLayout()
    local frame = self.frame
    local UI = ns.Kit.UI
    UI.LayoutNow()
    local width = self:Width()
    self.laidWidth = width
    local height = self.content:NaturalHeight(width - 2)
    local band = frame.band and frame.band:IsShown() and (frame.band:GetHeight() or 30) or 0
    frame:SetHeight(UI.Snap(frame, math.max(MIN_HEIGHT, height + band + 2)))
end

-- What follows the step shown: the arrow, the NPC and item strips, the
-- materials list, the quest log selection.
function MainWindow:SyncAfter(node, guide)
    call("Navigation", "Refresh", node, guide)
    self:SyncNPCs()
    self.currentNode = node
    -- Throttled inside: records what the client's waypoints say about this
    -- step's quests, for `/nuuroad poi`. Reads only.
    if node then call("POILog", "Sync", node) end
    -- Last, so the quest log is pointed at the step the tracker has just drawn.
    call("QuestSelection", "Sync", node)
end

function MainWindow:Refresh()
    self.refreshPending, self.refreshWait = false, 0
    if not self.frame then return end
    local Browser = M("GuideBrowser")
    if Browser and Browser.IsShown and Browser.Refresh then
        local ok, shown = pcall(Browser.IsShown, Browser)
        if ok and shown then call("GuideBrowser", "Refresh") end
    end
    readMarkers()
    local Progress = M("Progress")
    local guide = Progress and Progress:GetActiveGuide()
    self:SyncTabs(guide)
    self:BeginCards()
    if not guide then
        self:SetStatus("")
        self:PaintProgress(nil)
        self:OpenCard(self.cardHolder, "muted")
        self:AddLine("Choose a guide to begin.", { marker = ">" })
        self:AddLine("Open the menu above, or right-click the minimap button.", { color = "muted", indent = true })
        self:LayoutStepList(nil)
        self:FinishLayout()
        self:SetGuideTitle("No guide selected")
        self:SyncAfter(nil)
        return
    end
    self.numberedSteps = nil
    local node, state = Progress:GetCurrentNode(guide)
    local position = node and node.index or #guide.nodes
    local stepCount = #guide.nodes
    local section = sectionTitle(guide, position)
    local title = guide.meta and guide.meta.title or guide.id
    self:PaintProgress(guide, position)
    if not node then
        self:SetStatus(stepCount .. " / " .. stepCount)
        self.skip:SetHighlighted(false)
        self:OpenCard(self.cardHolder, "success")
        self:AddLine("Guide complete.", { icon = "done" })
        self:AddLine("Reset it from the menu to run it again, or pick another guide there.", { color = "muted", indent = true })
        self:LayoutStepList(guide, nil)
        self:FinishLayout()
        self:SetGuideTitle(title, section)
        self:SyncAfter(nil)
        return
    end
    -- A farming circuit sends the player back to an earlier step; the lap
    -- count is the only thing that tells the repeated steps apart.
    local lap = Progress:CurrentLap(guide, node.index) or 1
    self:SetStatus(node.index .. " / " .. stepCount .. (lap > 1 and ("  Lap " .. lap) or ""))
    self:DrawStep(guide, node, state)
    self:LayoutStepList(guide, node)
    self:FinishLayout()
    self:SetGuideTitle(title, section)
    self:SyncAfter(node, guide)
end

-- The current step: the carried work's card, then the step's own.
function MainWindow:DrawStep(guide, node, state)
    local Progress, Steps, GuideScan = M("Progress"), M("Steps"), M("GuideScan")
    -- A step counts as done when the player's progress says so or the game
    -- still reports it done.
    local function stepDone(candidate)
        if GuideScan then return GuideScan:IsStepDone(guide, candidate, state) end
        return Progress:IsDone(state.statuses[candidate.index])
    end
    -- Carried work sits above the step: a sticky objective and anything the
    -- guide asked to be done alongside this step share one muted card,
    -- because to the player they are the same thing -- work in hand while
    -- the step below says where to go next.
    local sticky = self:StickyLines(guide, node)
    local carried = Progress:Carried(guide, node) or {}
    if #sticky > 0 or #carried > 0 then
        self:OpenCard(self.stickyHolder, "muted")
        for _, entry in ipairs(sticky) do
            self:AddLine(entry.text, { icon = entry.icon, iconColor = "muted", tooltip = self:StickyTooltip(entry.questID) })
        end
        for _, companion in ipairs(carried) do
            local done = stepDone(companion)
            self:AddLine(Steps:Title(companion), {
                alpha = done and 0.9 or 1, icon = kindIcon[companion.kind] or "note",
                iconColor = done and "done" or "muted", status = done and "done" or nil,
                tooltip = self:StepTooltip(companion, nil, true),
            })
            if companion.body and companion.body ~= "" then
                self:AddLine(companion.body, { color = "muted" })
            end
        end
    end

    -- A member handed in or accepted leaves the card: the group is the work
    -- still in front of the player. The step the guide is actually on always
    -- stays, however it reads -- the flow is what moves it on, not the card.
    local authored = Progress:QuestGroup(guide, node) or { node }
    local group = { node }
    for index = 2, #authored do
        if not stepDone(authored[index]) then table.insert(group, authored[index]) end
    end
    self:OpenCard(self.cardHolder, "accent")
    -- A note or closing step is only its text: show it on the goal line itself.
    local textOnly = (node.kind == "note" or node.kind == "end") and node.body and node.body ~= ""
    local choices = node.choices or {}
    -- Nothing in the game finishes a step with no completion rule (a note, a
    -- vendor visit, a click) or one already behind the player, so the player
    -- moves it on: the step with no rule gets a Done button, and skip lights up.
    local byHand = #choices == 0 and node.kind ~= "end" and node.kind ~= "choice"
        and (node.completion == nil or node.completion.type == "manual")
    local waitsForSkip = #choices == 0 and (byHand or stepDone(node)
        or (GuideScan and GuideScan:Settled(guide, node) or false))
    self.skip:SetHighlighted(waitsForSkip and node.kind ~= "end")
    if textOnly then
        self:AddLine(node.body, { icon = kindIcon[node.kind] or node.kind, iconColor = "muted" })
    else
        self:DrawGoals(guide, node, group)
    end
    for _, line in ipairs(self:LiveObjectiveLines(node)) do
        self:AddLine(line)
    end
    -- The travel route, one muted line. A click picks the next route on offer
    -- (a teleport, walking, the default again), for this step: the route is
    -- the player's call. While the arrow follows a typed-in waypoint, the
    -- line is that route's.
    local Route, Navigation = M("TravelRoute"), M("Navigation")
    local routeNode = node
    if Route and Navigation and Navigation.waypoint and Route.node == Navigation.waypoint then routeNode = Navigation.waypoint end
    local routeLine = Route and Route.RouteLine and Route:RouteLine(routeNode)
    if routeLine then
        if routeNode ~= node then routeLine = routeLine:gsub("^Route:", "Route to the waypoint:") end
        self:AddLine(routeLine, {
            color = "muted", indent = true, marker = ">", iconColor = "muted",
            onClick = function() Route:CycleChoice(routeNode); self:Refresh() end,
            tooltip = "Click for the next route on offer.",
        })
    end
    if byHand then
        self:AddCardButton("Done - next step", function()
            if not self:AcceptAction() then return end
            M("Progress"):Complete(guide, nil, "complete")
            self:Refresh()
        end, true, "Nothing in the game says when this step is done. Click once you have done it; skip (>) at the top passes it over instead.", "accent")
    end
    -- A purchase is often one the player has no need of (they already have
    -- the bag, or a better weapon), and buying is what finishes it, so the
    -- card offers the skip the top bar already has. A purchase settled by the
    -- work after it still needs moving on, so only one recorded or in the
    -- bags drops the button.
    local bought = Progress:IsDone(state.statuses[node.index]) or (GuideScan and GuideScan:NodeCompleted(node))
    if node.kind == "buy" and not bought then
        self:AddCardButton("Skip - I do not need it", function()
            if not self:AcceptAction() then return end
            M("Progress"):Forward(guide)
            self:Landed()
            self:Refresh()
        end, true, "Passes this purchase over, the same as skip (>) at the top.")
    end
    self:AddMakeButton(node)
    if #choices > 0 then self:AddLine("Pick one to continue:", { color = "muted", indent = true }) end
    for index, choice in ipairs(choices) do self:AddChoiceButton(guide, choice, index) end
end

-- The goal lines of the step and the rest of its authored group.
function MainWindow:DrawGoals(guide, node, group)
    local Progress, Steps, GuideScan, Names = M("Progress"), M("Steps"), M("GuideScan"), M("Names")
    -- A step the client cannot judge reads as settled once the proven work
    -- after it says it no longer matters.
    local settled = GuideScan and GuideScan:Settled(guide, node)
    -- The card shows the current and remaining authored quest visits as one
    -- step with a goal line per quest. A visit is a run of members standing
    -- at one NPC, so consecutive steps at the same NPC share one "Talk to".
    local visits = {}
    for _, member in ipairs(group) do
        local goals = Steps:Goals(member)
        local lead = goals[1]
        local key = (lead and lead.verb == "talk" and lead.npcs) and table.concat(lead.npcs, "+") or nil
        local visit = key and visits[#visits] or nil
        if visit and visit.key == key then
            table.insert(visit.entries, { member = member, goals = goals })
        else
            table.insert(visits, { key = key, lead = key and lead or nil, entries = { { member = member, goals = goals } } })
        end
    end
    -- The group is the one place the tracker shows distances: its members are
    -- separate errands the player picks an order for. One reading per visit,
    -- on its first line, not repeated when the next visit stands in the same
    -- spot; objective work (kills, collects) always carries its own.
    local lastPlace
    for _, visit in ipairs(visits) do
        local rows = {}
        for _, entry in ipairs(visit.entries) do
            local memberSettled = entry.member == node and settled
            for index, goal in ipairs(entry.goals) do
                if not (visit.lead and index == 1) then
                    local status, progress = Steps:GoalStatus(goal, entry.member)
                    if memberSettled and status ~= "done" and status ~= "moot" then status = "settled" end
                    table.insert(rows, { goal = goal, member = entry.member, status = status, progress = progress })
                end
            end
        end
        local place = visit.entries[1].member.location
        local placeKey = place and type(place.x) == "number" and type(place.y) == "number"
            and (tostring(place.mapID) .. ":" .. place.x .. ":" .. place.y) or nil
        local ownDistance = not Progress:IsQuestVisit(visit.entries[1].member)
        if placeKey == nil or (placeKey == lastPlace and not ownDistance) then place = nil end
        if placeKey then lastPlace = placeKey end
        -- One errand does not need two lines: a visit that is a single quest
        -- folds its header into the quest ("Accept <quest> from <NPC>").
        local fold = visit.lead and #rows == 1
            and (rows[1].goal.verb == "accept" or rows[1].goal.verb == "turnin")
        if visit.lead and not fold then
            -- The header is behind the player once everything under it is;
            -- having spoken to the NPC without handing anything over is work
            -- under way.
            local status
            for _, entry in ipairs(visit.entries) do
                if Steps:GoalStatus(visit.lead, entry.member) == "active" then status = "active" end
            end
            local behind = #rows > 0
            for _, row in ipairs(rows) do
                if not quietStatus[row.status] then behind = false end
            end
            if behind then status = "done" end
            self:AddLine(Steps:GoalText(visit.lead, paint), {
                icon = visit.lead.verb, status = status, away = place,
                color = quietStatus[status] and "muted" or "text",
                tooltip = self:GoalTooltip(visit.lead, visit.entries[1].member, status),
            })
            place = nil
        end
        for _, row in ipairs(rows) do
            local goal, status, progress = row.goal, row.status, row.progress
            local checked = status == "done" or status == "settled"
            local text = Steps:GoalText(goal, paint)
            if fold then
                text = text .. (goal.verb == "turnin" and " to " or " from ") .. talkTarget(visit.lead)
                goal = withNPCs(goal, visit.lead.npcs)
            end
            -- The item's own texture on a "Use" line, done or not.
            local iconPath
            if goal.useItem then
                local Client = M("Client")
                iconPath = Client and Client.GetItemIcon and Client:GetItemIcon(goal.useItem)
                if not iconPath and Client and Client.RequestItemData then Client:RequestItemData(goal.useItem) end
            end
            self:AddLine(text, {
                icon = goal.verb, iconPath = iconPath, status = status, away = place,
                count = not saysCount(goal) and progress or nil,
                countColor = (checked and "done") or (status == "active" and "warning") or "text",
                -- A goal the player has no quest for keeps its own icon, in red.
                iconColor = ((status == "moot" or status == "failed") and "danger") or ((not checked and goal.verb == "travel") and "accent") or nil,
                color = quietStatus[status] and "muted" or "text",
                tooltip = self:GoalTooltip(goal, row.member, status),
            })
            place = nil
        end
    end
    -- The guide waits on a step it cannot do yet rather than pass it over;
    -- the player opens it or moves on with skip.
    if Progress:IsWaiting(node) then
        local needs = Steps:DescribeCondition(node.condition)
        self:AddLine("Not open to you yet" .. (needs and (" (needs " .. needs .. ")") or "")
            .. ". The guide waits here; skip it (>) to go on without it.", { color = "warning" })
    elseif GuideScan and GuideScan:NodeIsMoot(node) then
        self:AddLine("You do not have this quest. The guide waits here; pick it up, or skip it (>) to go on without it.",
            { color = "danger" })
    elseif node.kind == "escort" and Steps:GoalStatus(Steps:Goals(node)[1], node) == "failed" then
        self:AddLine("The escort failed. Abandon " .. paint("quest", Names:DescribeQuest(node.auto.quests[1]))
            .. " and take it again; the NPC may need a while to come back.", { color = "danger" })
    end
    -- What this step asks the player to bring, and how much is missing. The
    -- whole guide's list is in the materials panel; this is only the step.
    local Materials = M("Materials")
    for _, material in ipairs(Materials and Materials:StepNeeds(node) or {}) do
        local name = Names:DescribeItem(material.itemID)
        local enough = material.short == 0
        -- Like the goal lines, the number is what is still owed.
        local text = (enough and "Have " or "Need ") .. paint("count", (enough and material.count or material.short) .. " ")
            .. paint("item", name, { id = material.itemID })
        self:AddLine(text, {
            icon = materialIcons[material.source] or "collect",
            status = enough and "done" or nil,
            count = (not enough) and (material.have .. "/" .. material.count) or nil,
            color = enough and "muted" or "text",
        })
    end
    if node.wait then
        self:AddLine("Takes about " .. tostring(node.wait) .. " seconds", { color = "muted" })
    end
    for _, id in ipairs(node.watch or {}) do
        self:AddLine("Watch for " .. Names:DescribeNPC(id), { color = "muted" })
    end
    if node.body and node.body ~= "" then self:AddLine(node.body) end
end

-- Asked for by game state that changed without the guide advancing: a quest
-- done out of order, an objective finished early, a level gained. Coalesced
-- on the tracker's beat (REFRESH_THROTTLE).
function MainWindow:RequestRefresh()
    self.refreshPending = true
end

function MainWindow:SyncNPCs()
    call("NPCTracking", "Sync")
    call("NPCPanel", "Refresh")
    call("ItemPanel", "Refresh")
    self:SyncMaterials()
end

-- How many of the things the steps ahead ask for are not in the bags, or nil
-- on a guide that names no materials at all -- which is what keeps the menu's
-- materials entry off a quest guide.
function MainWindow:MaterialsMissing()
    local Materials, Progress = M("Materials"), M("Progress")
    if not Materials or not Progress then return nil end
    local guide = Progress:GetActiveGuide()
    -- Past the last step there is nothing left to bring.
    local from = guide and Progress:GetCurrentIndex(guide)
    if not guide or not from or not Materials:GuideHasMaterials(guide) then return nil end
    return Materials:Summary(guide, from)
end

-- The materials panel appears only for a guide that names any.
function MainWindow:SyncMaterials()
    call("MaterialsPanel", "Refresh")
end

-- The menu -------------------------------------------------------------------------------------

-- Its entries are built fresh on every opening, because what belongs on it
-- depends on the moment: whether a guide is running at all, whether that
-- guide asks for materials, and how much of it is still missing.
function MainWindow:MenuItems()
    local Progress, Config = M("Progress"), M("Config")
    local guide = Progress and Progress:GetActiveGuide()
    local none = guide == nil
    local items = {}
    table.insert(items, { caption = "Guides", onClick = function() self:ToggleGuidePicker() end })
    table.insert(items, { caption = "Edit this guide", disabled = none, reason = none and "Start a guide first." or nil,
        onClick = function() call("Editor", "OpenGuide", M("Progress"):GetActiveGuide()) end })
    -- A reset cannot be undone, so the entry asks for the click twice and the
    -- menu stays open in between to say so. An entry armed and then left
    -- alone is disarmed by the next opening, never carried into it.
    local reset = { caption = "Reset this guide", keep = true, disabled = none,
        reason = none and "Start a guide first." or nil }
    reset.onClick = function(item)
        local running = M("Progress"):GetActiveGuide()
        if not running then return end
        if item.armedAt and now() - item.armedAt < 4 then
            item.armedAt = nil
            M("Progress"):Reset(running)
            self:UI():CloseMenu()
            self:Refresh()
            return
        end
        item.armedAt = now()
        item.caption = "Sure? Click again"
        item.tone = "danger"
    end
    table.insert(items, reset)
    -- Its tab shuts; its progress this session is kept, should it be opened
    -- again. With one guide open there is no strip, so this is the way.
    table.insert(items, { caption = "Close this guide", disabled = none, reason = none and "Start a guide first." or nil,
        onClick = function()
            local running = M("Progress"):GetActiveGuide()
            if running then self:CloseGuide(running.id) end
        end })
    local missing = self:MaterialsMissing()
    if missing then
        table.insert(items, { caption = missing > 0 and ("Materials list (" .. missing .. " missing)") or "Materials list",
            check = true, value = Config and Config:Get("materials.shown") == true,
            onChange = function(on)
                M("Config"):Set("materials.shown", on and true or false)
                self:Refresh()
            end })
    end
    -- The tools for writing guides rather than playing them, one level down
    -- so the menu a player reads is about playing.
    table.insert(items, { caption = "Authoring", items = {
        { caption = "Session log", onClick = function() call("RecordingPanel", "Toggle") end },
        { caption = "Place recorder", onClick = function() call("PlaceRecorder", "Toggle") end },
        { caption = "Diagnostics", onClick = function() self:ShowDiagnostics() end },
    } })
    table.insert(items, { caption = "Report a bug", onClick = function() call("BugReportPanel", "Show") end })
    table.insert(items, { caption = "Options", onClick = function() self:ToggleOptions() end })
    return items
end

function MainWindow:ToggleMenu()
    local ui = self:UI()
    self.menuItems = self:MenuItems()
    ui:OpenMenu(self.menuItems, { anchor = self.menuButton, align = "right", above = self:Upward() })
end

-- The minimap launcher ---------------------------------------------------------------------------

-- A round minimap button that can be dragged around the minimap's rim: a
-- plain frame, as the kit has no minimap button.
function MainWindow:PlaceLauncher()
    local button = self.launcher
    if not button or not Minimap then return end
    local Config = M("Config")
    local angle = math.rad(tonumber(Config and Config:Get("minimap.angle")) or 220)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function MainWindow:CreateLauncher()
    if self.launcher or not rawget(_G, "Minimap") then return self.launcher end
    local button = CreateFrame("Button", nil, Minimap)
    button:SetSize(31, 31); button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp"); button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND"); background:SetSize(20, 20)
    background:SetTexture("Interface/Minimap/UI-Minimap-Background"); background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK"); icon:SetSize(17, 17)
    icon:SetTexture("Interface\\AddOns\\NuuRoad\\Art\\WaypointArrow.tga"); icon:SetPoint("TOPLEFT", 8, -6)
    local border = button:CreateTexture(nil, "OVERLAY"); border:SetSize(53, 53)
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder"); border:SetPoint("TOPLEFT")
    -- The arrow wears the look's accent, and follows it.
    self:UI():Paint(icon, function(t) ns.Kit.UI.VertexColor(icon, t.accent) end)
    button:SetScript("OnDragStart", function(control)
        control:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            if not centerX or not cursorX then return end
            local Navigation = M("Navigation")
            local atan2 = Navigation and Navigation.Atan2 or math.atan2
            M("Config"):Set("minimap.angle", math.deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX)))
            self:PlaceLauncher()
        end)
    end)
    button:SetScript("OnDragStop", function(control) control:SetScript("OnUpdate", nil) end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then self:ToggleGuidePicker() else self:Toggle() end
    end)
    button:SetScript("OnEnter", function(control)
        self:UI():Tooltip(control, function(tip)
            tip:SetText("NuuRoad")
            tip:AddLine("Left-click: show or hide the tracker", 1, 1, 1)
            tip:AddLine("Right-click: choose a guide", 1, 1, 1)
            tip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        end, { anchor = "ANCHOR_LEFT" })
    end)
    button:SetScript("OnLeave", function() self:UI():HideTooltip() end)
    self.launcher = button
    self:PlaceLauncher()
    return button
end

-- Other windows -----------------------------------------------------------------------------------

-- The guide browser (UI/GuideBrowser.lua) makes its own window.
function MainWindow:CreateGuidePicker()
    local Browser = M("GuideBrowser")
    if Browser and Browser.Create then self.picker = Browser:Create() end
    return self.picker
end

function MainWindow:RefreshGuidePicker() call("GuideBrowser", "Refresh") end
function MainWindow:ToggleGuidePicker() call("GuideBrowser", "Toggle") end

-- Opens the guide browser searched for a quest. Used by the quest log button.
function MainWindow:ShowGuidesForQuest(questID)
    call("GuideBrowser", "ShowQuest", questID)
end

-- The options window and the Diagnostics window are UI/Options.lua's.
function MainWindow:ToggleOptions() call("Options", "Toggle") end
function MainWindow:ShowDiagnostics() call("Options", "ShowDiagnostics") end
function MainWindow:RefreshOptionLabels() call("Options", "Sync") end

-- Settings shown here (Config:Changed tells every module).
function MainWindow:OnSettingChanged(path)
    if not self.frame or type(path) ~= "string" then return end
    if path == "automation.selectQuestInLog" or path == "tracker.markWaiting" then
        -- Turning the log selection on points the log at the step in front
        -- of the player straight away, rather than at the next step.
        self:RequestRefresh()
    elseif path == "tracker.scale" then
        self:ApplyDisplaySettings()
    elseif path == "tracker.upward" then
        self:ApplyDirection()
        self:Refresh()
    elseif path == "stepList.rows" or path == "stepList" or string.sub(path, 1, 6) == "realm." then
        self:Refresh()
    elseif path == "minimap.angle" or path == "minimap" then
        self:PlaceLauncher()
    end
end

-- Showing and hiding -------------------------------------------------------------------------------

function MainWindow:Toggle()
    if not self.frame then return end
    if self.frame:IsShown() then
        self.frame:Hide()
        self:UI():CloseMenu()
        call("GuideBrowser", "Hide")
        local Config = M("Config")
        if Config then Config:Set("tracker.shown", false) end
        call("Navigation", "ShowArrowWindow")
        self:SyncNPCs()
    else
        self:Show()
    end
end

-- Showing a tracker the player had closed stores that it is open again;
-- showing one that never was closed stores nothing.
function MainWindow:Show()
    if not self.frame then self:CreateTracker() end
    local Config = M("Config")
    if Config and not Config:Get("tracker.shown") then Config:Set("tracker.shown", true) end
    self.frame:Show()
    self:Refresh()
end

function MainWindow:Initialize()
    self:CreateTracker()
    self:CreateLauncher()
    self:ApplyDisplaySettings()
    local Progress, Config = M("Progress"), M("Config")
    local guide = Progress and Progress:GetActiveGuide()
    ns:Log("main window: restoring " .. (guide and ("'" .. tostring(guide.meta and guide.meta.title or guide.id) .. "'") or "no guide"))
    if Config and Config:Get("tracker.shown") then self:Show() else self:Refresh() end
    -- A craft step's Make button follows the profession window open and shut.
    local Client = M("Client")
    if Client and Client.OnProfessionChange then
        Client:OnProfessionChange(function(kind)
            if kind == "window" or kind == "tradeskill" then self:RequestRefresh() end
        end)
    end
    -- Bags change what the Make button can make.
    local events = CreateFrame("Frame")
    if not pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED") then pcall(events.RegisterEvent, events, "BAG_UPDATE") end
    events:SetScript("OnEvent", function() self:RequestRefresh() end)
    self.events = events
    -- A new look repaints the kit's widgets itself; what the tracker coloured
    -- by hand (washes, icons, names in the goal text) is drawn again.
    self:UI():OnLook(function() self:RequestRefresh() end)
end

ns:RegisterModule("MainWindow", MainWindow)
