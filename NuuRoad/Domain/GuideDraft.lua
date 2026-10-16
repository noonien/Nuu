local _, ns = ...

-- A guide being edited, as its guide source (docs/examples/guide-source.lua): the
-- model under the editor (UI/Editor.lua). It holds the source itself, not
-- the runtime guide, so what the editor shows and keeps is what a guide file
-- says, and a guide made in game can be copied out as text.
--
-- Every change goes through Change(): the value before it is kept for Undo,
-- the guide is built again (Steps:Expand, then GuideCheck:Validate) and what is
-- wrong is put on the step it is about, never in one status line. A step
-- that cannot be built is left out of the runtime guide until it is fixed,
-- so the rest of the guide still plays. Then `onChanged` is told, which is
-- where the editor saves: there is no Save and no Cancel.
--
-- Steps are tables of the value, so a step keeps its identity while steps
-- around it come and go; that is how the tracker keeps the player on the
-- same step when the guide is saved (Map). Labels, which a source uses to point at
-- a step, are made here when something needs one (EnsureLabel) and never
-- typed by the author.
--
-- Touches no frame: Tests/GuideDraftTests.lua runs it outside the client.
local GuideDraft = {}
local Draft = {}
Draft.__index = Draft

local UNDO_LIMIT = 60

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end
GuideDraft.Copy = copy

-- Whether two values hold the same (tables compared by what they hold).
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function trim(text) return (tostring(text or ""):match("^%s*(.-)%s*$")) end

-- Seconds since the epoch, from the client where there is one.
local function now()
    local clock = rawget(_G, "time") or (os and os.time)
    return clock and clock() or 1
end

-- What each step type is made of, beyond the fields any step may carry. A
-- field the new type has no use for is put aside when the type changes and
-- given back if it changes back (SetType), so trying a type loses nothing.
GuideDraft.typeFields = {
    note = {}, finish = { "next" },
    travel = { "to", "zone", "area", "instance" },
    accept = { "quests", "level", "item", "kill" },
    turnin = { "quests", "optional" },
    talk = { "turnin", "accept", "say", "level", "optional" },
    escort = {},
    collect = { "item", "count", "kill", "starts" },
    kill = { "kill", "count" },
    interact = {},
    gather = { "item", "count", "skill" },
    craft = { "item", "count", "skill" },
    skillup = { "item", "skill", "rank" },
    buy = { "item", "count" },
    vendor = { "sell", "repair" },
    equip = { "item" },
    train = { "skill", "rank" },
    learn = { "spells" },
    cast = { "spell", "count" },
    skill = { "skill", "rank" },
    reputation = { "faction", "standing" },
    hearth = { "area" },
    flight = { "node" },
    level = { "level", "xp", "by" },
    choice = { "text", "options" },
}
local COMMON = { type = true, note = true, label = true, cond = true, show = true, npc = true, at = true, stand = true,
    near = true, radius = true, loop = true, wait = true, use = true, sticky = true, with = true, from = true,
    mark = true, needs = true, upto = true, quest = true, object = true }
-- What any step may carry, whatever its type (Schema/Guide.lua's StepCommon is checked against it).
GuideDraft.commonFields = COMMON

-- What a type needs to be a step at all, filled in when a step becomes one.
local STARTERS = {
    vendor = { sell = true },
    choice = { text = "Which way?" },
}

-- Opening ----------------------------------------------------------------------------------

local function newDraft(guide, fields)
    local draft = setmetatable(fields or {}, Draft)
    draft.guide = guide
    draft.undoStack, draft.redoStack, draft.stash = {}, {}, setmetatable({}, { __mode = "k" })
    draft.version = 0
    draft:Rebuild()
    -- The runtime guide the steps stood at when the draft was opened: the
    -- packaged or saved guide, whose positions the first Map starts from.
    draft.builtSteps = draft.builtFrom or draft.entriesSteps
    return draft
end

-- A copy of a guide value to edit. `opts.copyOf` names the packaged guide
-- it was copied from: the draft keeps that guide's ID until the first
-- change, when it becomes a guide of the player's own (Promote).
function GuideDraft:Open(source, opts)
    opts = opts or {}
    local guide = copy(source)
    return newDraft(guide, { copyOf = opts.copyOf, id = guide.id })
end

-- A new guide with one empty step, filed under Personal.
function GuideDraft:New(title, map)
    local guide = {
        kind = "guide", id = ns.modules.GuideRepository.pendingID,
        title = trim(title) ~= "" and trim(title) or "Untitled guide", category = "Personal",
        author = "Player", tags = { "personal" },
        data = { map = map, sections = { { title = "Start", steps = { { type = "note" } } } } },
    }
    return newDraft(guide, { id = guide.id, isNew = true })
end

-- Entries: the steps in order ---------------------------------------------------------------

-- Every step in the order the guide runs, each with where it sits:
-- { step, section (index), container (the list holding it), at (its place
-- there), group (the group wrapper, or nil), groupAt (the wrapper's place in
-- the section), position }. Worked out again after every change.
function Draft:Entries()
    if self.entries then return self.entries end
    local entries, steps = {}, {}
    for sectionIndex, section in ipairs(self.guide.data.sections) do
        for at, item in ipairs(section.steps) do
            if type(item) == "table" and item.group ~= nil then
                for memberAt, member in ipairs(item.group) do
                    local entry = { step = member, section = sectionIndex, container = item.group, at = memberAt,
                        group = item, groupAt = at }
                    entries[#entries + 1] = entry
                    entry.position = #entries
                    steps[#steps + 1] = member
                end
            else
                local entry = { step = item, section = sectionIndex, container = section.steps, at = at }
                entries[#entries + 1] = entry
                entry.position = #entries
                steps[#steps + 1] = item
            end
        end
    end
    self.entries, self.entriesSteps = entries, steps
    return entries
end

function Draft:EntryOf(step)
    for _, entry in ipairs(self:Entries()) do
        if entry.step == step then return entry end
    end
    return nil
end

function Draft:StepAt(position)
    local entry = self:Entries()[position]
    return entry and entry.step
end

function Draft:Count() return #self:Entries() end

function Draft:Sections() return self.guide.data.sections end

-- Changing ----------------------------------------------------------------------------------

-- Runs `edit` as one undoable change. `edit` returns false and a message to
-- refuse, which leaves the guide as it was. `what` says what changed, for
-- the editor's status line.
function Draft:Change(what, edit)
    local before = copy(self.guide)
    local ran, ok, problem = pcall(edit, self)
    if not ran then ok, problem = false, "That change could not be made: " .. tostring(ok) end
    if ok == false then
        -- Refused before it touched anything (the usual case): the steps
        -- keep their identity. Refused half-way: the guide as it was.
        if not same(before, self.guide) then self.guide = before end
        self.entries = nil
        return false, problem
    end
    table.insert(self.undoStack, { guide = before, what = what })
    if #self.undoStack > UNDO_LIMIT then table.remove(self.undoStack, 1) end
    self.redoStack = {}
    self:Changed(what)
    return true
end

function Draft:Changed(what)
    self.entries = nil
    self.version = self.version + 1
    self:Rebuild()
    if self.onChanged then self.onChanged(self, what) end
end

function Draft:CanUndo() return #self.undoStack > 0 end
function Draft:CanRedo() return #self.redoStack > 0 end

-- Undo and redo answer what they undid or did again.
function Draft:Undo()
    local last = table.remove(self.undoStack)
    if not last then return nil end
    table.insert(self.redoStack, { guide = self.guide, what = last.what })
    self.guide = last.guide
    self:Changed("undo")
    return last.what
end

function Draft:Redo()
    local again = table.remove(self.redoStack)
    if not again then return nil end
    table.insert(self.undoStack, { guide = self.guide, what = again.what })
    self.guide = again.guide
    self:Changed("redo")
    return again.what
end

-- Fields --------------------------------------------------------------------------------------

local function empty(value)
    return value == nil or value == "" or (type(value) == "table" and next(value) == nil)
end

-- Sets one field of a step; nil, "" or {} takes it out, as a source has no empty
-- values. A field is changed in place, so the step keeps its identity.
function Draft:SetField(step, key, value, what)
    if empty(value) then value = nil end
    if step[key] == value then return true end
    return self:Change(what or key, function()
        step[key] = value
    end)
end

-- Several fields at once, as one change.
function Draft:SetFields(step, fields, what)
    return self:Change(what or "step", function()
        for key, value in pairs(fields) do
            if empty(value) or value == false then value = nil end
            step[key] = value
        end
    end)
end

-- A field of the guide's wrapper (title, category, levels...).
function Draft:SetGuideField(key, value)
    if empty(value) then value = nil end
    if self.guide[key] == value then return true end
    return self:Change(key, function() self.guide[key] = value end)
end

-- Changes a step's type. The fields only the old type had are put aside
-- (and given back if the type comes back); what any step carries stays.
function Draft:SetType(step, kind)
    if step.type == kind then return true end
    if not GuideDraft.typeFields[kind] then return false, "There is no step type '" .. tostring(kind) .. "'." end
    return self:Change("type", function()
        local keep = {}
        for _, key in ipairs(GuideDraft.typeFields[kind]) do keep[key] = true end
        local aside = self.stash[step] or {}
        for key, value in pairs(step) do
            if not COMMON[key] and not keep[key] then
                aside[key] = value
                step[key] = nil
            end
        end
        -- A field `item` is a number on the types that make or fetch one,
        -- and a list of items anywhere else.
        for key, value in pairs(aside) do
            if keep[key] and step[key] == nil then step[key] = value; aside[key] = nil end
        end
        self.stash[step] = next(aside) and aside or nil
        step.type = kind
        for key, value in pairs(STARTERS[kind] or {}) do
            if step[key] == nil then step[key] = copy(value) end
        end
    end)
end

-- Structure -----------------------------------------------------------------------------------

-- A new step after `after` (a step), or at the start of the guide. After a
-- group member it goes after the group, since groups hold quest visits only.
function Draft:Insert(after, step)
    step = step or { type = "note" }
    local ok, problem = self:Change("add", function()
        local entry = after and self:EntryOf(after)
        if not entry then
            table.insert(self.guide.data.sections[1].steps, 1, step)
            return
        end
        if entry.group then
            table.insert(self.guide.data.sections[entry.section].steps, entry.groupAt + 1, step)
        else
            table.insert(entry.container, entry.at + 1, step)
        end
    end)
    return ok and step or nil, problem
end

-- The same step again after it, without its label (two steps cannot share one).
function Draft:Duplicate(step)
    local twin = copy(step)
    twin.label = nil
    return self:Insert(step, twin)
end

-- A group of one is no group: its member takes the wrapper's place.
local function settleGroup(section, groupAt)
    local wrapper = section.steps[groupAt]
    if type(wrapper) == "table" and wrapper.group ~= nil and #wrapper.group < 2 then
        local member = wrapper.group[1]
        if member then
            member.label = member.label or wrapper.label
            section.steps[groupAt] = member
        else
            table.remove(section.steps, groupAt)
        end
    end
end

-- What points at a label, taken off when the step it names goes: choice
-- options leading there, and `with`, `from` and `by` naming it.
local function forgetLabel(guide, label)
    if not label then return end
    for _, section in ipairs(guide.data.sections) do
        local function clean(step)
            if step.with == label then step.with = nil end
            if step.from == label then step.from = nil end
            if step.by == label then step.by = nil end
            for index = #(step.options or {}), 1, -1 do
                if step.options[index].go == label then table.remove(step.options, index) end
            end
            if step.options and #step.options == 0 then step.options = nil end
        end
        for _, item in ipairs(section.steps) do
            if item.group ~= nil then
                for _, member in ipairs(item.group) do clean(member) end
            else
                clean(item)
            end
        end
    end
end

function Draft:Delete(step)
    if self:Count() <= 1 then return false, "A guide needs at least one step." end
    return self:Change("delete", function()
        local entry = self:EntryOf(step)
        if not entry then return false, "That step is not in the guide." end
        local sections = self.guide.data.sections
        local section = sections[entry.section]
        table.remove(entry.container, entry.at)
        if entry.group then settleGroup(section, entry.groupAt) end
        forgetLabel(self.guide, step.label)
        if #section.steps == 0 then table.remove(sections, entry.section) end
    end)
end

-- One place up (-1) or down (1). At the edge of a group the step leaves it;
-- at the edge of a section it moves into the next section.
function Draft:Move(step, direction)
    return self:Change("move", function()
        local entry = self:EntryOf(step)
        if not entry then return false, "That step is not in the guide." end
        local sections = self.guide.data.sections
        local section = sections[entry.section]
        local target = entry.at + direction
        if entry.group then
            if entry.container[target] then
                entry.container[entry.at], entry.container[target] = entry.container[target], entry.container[entry.at]
                return
            end
            table.remove(entry.container, entry.at)
            local at = direction < 0 and entry.groupAt or entry.groupAt + 1
            table.insert(section.steps, at, step)
            settleGroup(section, direction < 0 and entry.groupAt + 1 or entry.groupAt)
            return
        end
        if section.steps[target] then
            section.steps[entry.at], section.steps[target] = section.steps[target], section.steps[entry.at]
            return
        end
        local other = sections[entry.section + direction]
        if not other then return false, direction < 0 and "This is the first step." or "This is the last step." end
        table.remove(section.steps, entry.at)
        if direction < 0 then table.insert(other.steps, step) else table.insert(other.steps, 1, step) end
        if #section.steps == 0 then table.remove(sections, entry.section) end
    end)
end

-- Into another section, at its end.
function Draft:MoveToSection(step, sectionIndex)
    return self:Change("move", function()
        local entry = self:EntryOf(step)
        local sections = self.guide.data.sections
        local target = sections[sectionIndex]
        if not entry or not target then return false, "There is no such section." end
        if entry.section == sectionIndex and not entry.group then return end
        local section = sections[entry.section]
        table.remove(entry.container, entry.at)
        if entry.group then settleGroup(section, entry.groupAt) end
        table.insert(target.steps, step)
        if #section.steps == 0 then table.remove(sections, entry.section) end
    end)
end

-- A new section starting at `step`: it and the steps after it in its
-- section move into the new one.
function Draft:SplitSection(step, title)
    return self:Change("section", function()
        local entry = self:EntryOf(step)
        if not entry then return false, "That step is not in the guide." end
        local sections = self.guide.data.sections
        local section = sections[entry.section]
        local from = entry.group and entry.groupAt or entry.at
        if from == 1 then return false, "This step already starts its section." end
        local moved = {}
        for index = from, #section.steps do moved[#moved + 1] = section.steps[index] end
        for index = #section.steps, from, -1 do table.remove(section.steps, index) end
        table.insert(sections, entry.section + 1, { title = trim(title) ~= "" and trim(title) or "New section", steps = moved })
    end)
end

-- A section at the end of the guide, holding one empty step.
function Draft:AddSection(title)
    local step = { type = "note" }
    local ok, problem = self:Change("section", function()
        table.insert(self.guide.data.sections, { title = trim(title) ~= "" and trim(title) or "New section", steps = { step } })
    end)
    return ok and step or nil, problem
end

function Draft:RenameSection(index, title)
    title = trim(title)
    local section = self.guide.data.sections[index]
    if not section or title == "" or section.title == title then return true end
    return self:Change("section", function() section.title = title end)
end

-- A section's steps join the one above it; the first joins the one below.
function Draft:MergeSection(index)
    local sections = self.guide.data.sections
    if #sections < 2 then return false, "The guide has only this section." end
    return self:Change("section", function()
        local section = table.remove(sections, index)
        local into = sections[index - 1] or sections[index]
        if index > 1 then
            for _, item in ipairs(section.steps) do table.insert(into.steps, item) end
        else
            for offset, item in ipairs(section.steps) do table.insert(into.steps, offset, item) end
        end
    end)
end

-- Groups: quest visits taken together, the guide's way of saying "these
-- NPCs stand together; do them in any order".
function Draft:GroupWithNext(step)
    return self:Change("group", function()
        local entry = self:EntryOf(step)
        if not entry then return false, "That step is not in the guide." end
        local section = self.guide.data.sections[entry.section]
        local at = entry.group and entry.groupAt or entry.at
        local here, nextItem = section.steps[at], section.steps[at + 1]
        if not nextItem then return false, "There is no step after this one in its section." end
        local members = {}
        for _, item in ipairs({ here, nextItem }) do
            if item.group ~= nil then
                for _, member in ipairs(item.group) do members[#members + 1] = member end
            else
                members[#members + 1] = item
            end
        end
        table.remove(section.steps, at + 1)
        section.steps[at] = { group = members, label = here.group ~= nil and here.label or nil }
    end)
end

function Draft:Ungroup(step)
    return self:Change("group", function()
        local entry = self:EntryOf(step)
        if not entry or not entry.group then return false, "This step is not in a group." end
        local section = self.guide.data.sections[entry.section]
        table.remove(section.steps, entry.groupAt)
        for offset, member in ipairs(entry.group.group) do table.insert(section.steps, entry.groupAt + offset - 1, member) end
    end)
end

-- Several steps at once ----------------------------------------------------------------------
--
-- What the editor does to a selection, each as one change: Undo takes the
-- whole of it back. `steps` is a list of the draft's steps, in any order.

-- The steps in run order, those not in the guide dropped.
function Draft:Ordered(steps)
    local wanted, out = {}, {}
    for _, step in ipairs(steps or {}) do wanted[step] = true end
    for _, entry in ipairs(self:Entries()) do
        if wanted[entry.step] then out[#out + 1] = entry.step end
    end
    return out
end

function Draft:DeleteMany(steps)
    steps = self:Ordered(steps)
    if #steps == 0 then return true end
    if #steps >= self:Count() then return false, "A guide needs at least one step." end
    return self:Change("delete", function()
        for index = #steps, 1, -1 do
            local step = steps[index]
            self.entries = nil
            local entry = self:EntryOf(step)
            local sections = self.guide.data.sections
            local section = sections[entry.section]
            table.remove(entry.container, entry.at)
            if entry.group then settleGroup(section, entry.groupAt) end
            forgetLabel(self.guide, step.label)
            if #section.steps == 0 then table.remove(sections, entry.section) end
        end
        self.entries = nil
    end)
end

-- Copies of the steps, each after the last of them, in their order.
function Draft:DuplicateMany(steps)
    steps = self:Ordered(steps)
    if #steps == 0 then return true end
    local twins = {}
    local ok, problem = self:Change("duplicate", function()
        local after = steps[#steps]
        for _, step in ipairs(steps) do
            local twin = copy(step)
            twin.label = nil
            self.entries = nil
            local entry = self:EntryOf(after)
            if entry.group then
                table.insert(self.guide.data.sections[entry.section].steps, entry.groupAt + 1, twin)
            else
                table.insert(entry.container, entry.at + 1, twin)
            end
            twins[#twins + 1] = twin
            after = twin
        end
        self.entries = nil
    end)
    return ok and twins or nil, problem
end

-- Each step one place up or down, as a block: moving up, the first goes
-- first; moving down, the last. The block stops at the guide's edge.
function Draft:MoveMany(steps, direction)
    steps = self:Ordered(steps)
    if #steps == 0 then return true end
    return self:Change("move", function()
        local order = {}
        for index = 1, #steps do order[index] = steps[direction < 0 and index or (#steps - index + 1)] end
        local edge = direction < 0 and self:StepAt(1) or self:StepAt(self:Count())
        if order[1] == edge then return false, direction < 0 and "The first of them is the first step." or "The last of them is the last step." end
        for _, step in ipairs(order) do
            self.entries = nil
            local entry = self:EntryOf(step)
            local sections = self.guide.data.sections
            local section = sections[entry.section]
            local target = entry.at + direction
            if entry.group then
                if entry.container[target] then
                    entry.container[entry.at], entry.container[target] = entry.container[target], entry.container[entry.at]
                else
                    table.remove(entry.container, entry.at)
                    table.insert(section.steps, direction < 0 and entry.groupAt or entry.groupAt + 1, step)
                    settleGroup(section, direction < 0 and entry.groupAt + 1 or entry.groupAt)
                end
            elseif section.steps[target] then
                section.steps[entry.at], section.steps[target] = section.steps[target], section.steps[entry.at]
            else
                local other = sections[entry.section + direction]
                if other then
                    table.remove(section.steps, entry.at)
                    if direction < 0 then table.insert(other.steps, step) else table.insert(other.steps, 1, step) end
                    if #section.steps == 0 then table.remove(sections, entry.section) end
                end
            end
        end
        self.entries = nil
    end)
end

function Draft:MoveManyToSection(steps, sectionIndex)
    steps = self:Ordered(steps)
    if #steps == 0 then return true end
    return self:Change("move", function()
        local target = self.guide.data.sections[sectionIndex]
        if not target then return false, "There is no such section." end
        for _, step in ipairs(steps) do
            self.entries = nil
            local entry = self:EntryOf(step)
            local sections = self.guide.data.sections
            local section = sections[entry.section]
            table.remove(entry.container, entry.at)
            if entry.group then settleGroup(section, entry.groupAt) end
            table.insert(target.steps, step)
            if #section.steps == 0 then
                for index, candidate in ipairs(sections) do
                    if candidate == section then table.remove(sections, index) break end
                end
            end
        end
        self.entries = nil
    end)
end

-- The steps as one group: they must sit side by side in one section (a
-- group they are part of whole is taken in).
function Draft:GroupSteps(steps)
    steps = self:Ordered(steps)
    if #steps < 2 then return false, "Pick two or more steps to group." end
    return self:Change("group", function()
        local chosen = {}
        for _, step in ipairs(steps) do chosen[step] = true end
        local first, last = self:EntryOf(steps[1]), self:EntryOf(steps[#steps])
        if first.section ~= last.section then return false, "Grouped steps sit in one section: these are in more than one." end
        local section = self.guide.data.sections[first.section]
        local from = first.group and first.groupAt or first.at
        local to = last.group and last.groupAt or last.at
        local members = {}
        for index = from, to do
            local item = section.steps[index]
            if item.group ~= nil then
                for _, member in ipairs(item.group) do
                    if not chosen[member] then return false, "Pick steps next to each other, a whole group or none of it." end
                    members[#members + 1] = member
                end
            else
                if not chosen[item] then return false, "Pick steps next to each other to group them." end
                members[#members + 1] = item
            end
        end
        for index = to, from, -1 do table.remove(section.steps, index) end
        table.insert(section.steps, from, { group = members })
    end)
end

-- Every group a step of these is in, taken apart.
function Draft:UngroupMany(steps)
    steps = self:Ordered(steps)
    local wrappers = {}
    for _, step in ipairs(steps) do
        local entry = self:EntryOf(step)
        if entry and entry.group then wrappers[entry.group] = true end
    end
    if next(wrappers) == nil then return false, "None of them is in a group." end
    return self:Change("group", function()
        for _, section in ipairs(self.guide.data.sections) do
            for index = #section.steps, 1, -1 do
                local item = section.steps[index]
                if wrappers[item] then
                    table.remove(section.steps, index)
                    for offset, member in ipairs(item.group) do table.insert(section.steps, index + offset - 1, member) end
                end
            end
        end
    end)
end

-- The same fields on every step (who sees them, say), as one change.
function Draft:SetFieldsMany(steps, fields, what)
    steps = self:Ordered(steps)
    if #steps == 0 then return true end
    return self:Change(what or "steps", function()
        for _, step in ipairs(steps) do
            for key, value in pairs(fields) do
                if empty(value) or value == false then value = nil end
                step[key] = copy(value)
            end
        end
    end)
end

-- Labels --------------------------------------------------------------------------------------

local function slug(text)
    local out = tostring(text or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return out:sub(1, 24)
end

-- Every label in use, step, group and section alike.
function Draft:Labels()
    local used = {}
    for _, section in ipairs(self.guide.data.sections) do
        if section.label then used[section.label] = true end
        for _, item in ipairs(section.steps) do
            if item.label then used[item.label] = true end
            for _, member in ipairs(item.group or {}) do
                if member.label then used[member.label] = true end
            end
        end
    end
    return used
end

-- The step's label, made from what the step is about when it has none. It
-- changes the guide outside an undoable change of its own: it is always
-- part of a change that points something at the step.
function Draft:EnsureLabel(step, hint)
    if step.label then return step.label end
    local used = self:Labels()
    local base = slug(hint)
    if base == "" then base = "step" end
    local label, n = base, 1
    while used[label] do
        n = n + 1
        label = base .. "-" .. n
    end
    step.label = label
    return label
end

-- The step a label names, or nil.
function Draft:StepLabelled(label)
    if not label then return nil end
    for _, entry in ipairs(self:Entries()) do
        if entry.step.label == label then return entry.step end
        if entry.group and entry.group.label == label and entry.at == 1 then return entry.step end
    end
    for _, section in ipairs(self.guide.data.sections) do
        if section.label == label then
            local first = section.steps[1]
            return first and (first.group and first.group[1] or first)
        end
    end
    return nil
end

-- Points `key` (with, from, by) of `step` at `target`, labelling it.
function Draft:Point(step, key, target, hint)
    return self:Change(key, function()
        if not target then step[key] = nil return end
        step[key] = self:EnsureLabel(target, hint)
    end)
end

-- A choice's options: { text, go = label }.
function Draft:SetOption(step, index, text, target, hint)
    return self:Change("choice", function()
        step.options = step.options or {}
        local option = step.options[index] or {}
        option.text = text or option.text or "This way"
        if target then option.go = self:EnsureLabel(target, hint) end
        step.options[index] = option
    end)
end

function Draft:RemoveOption(step, index)
    return self:Change("choice", function()
        if step.options then table.remove(step.options, index) end
        if step.options and #step.options == 0 then step.options = nil end
    end)
end

-- NPCs ----------------------------------------------------------------------------------------

-- The guide's entry for an NPC, whatever map it is listed under: its name
-- (or { name, at, note }) and that map.
function Draft:NPC(id)
    for map, list in pairs(self.guide.data.npcs or {}) do
        local entry = list[id]
        if entry ~= nil then return entry, map end
    end
    return nil
end

function Draft:NPCName(id)
    local entry = self:NPC(id)
    if type(entry) == "table" then return entry.name end
    if type(entry) == "string" then return entry end
    local Names = ns.modules.Names
    return Names and Names.NPC and Names:NPC(id) or nil
end

-- Puts an NPC in the guide's list with its name, and where it stands when
-- given (a point in hundredths of a percent on `map`). Part of the change
-- that names the NPC on a step, so it has no undo of its own.
function Draft:KeepNPC(id, name, map, at)
    local data = self.guide.data
    data.npcs = data.npcs or {}
    local entry, listedOn = self:NPC(id)
    map = map or listedOn or data.map or 0
    if type(entry) ~= "table" then entry = { name = name or (type(entry) == "string" and entry) or ("NPC " .. id) } end
    if name and name ~= "" then entry.name = name end
    if at then entry.at = at end
    if listedOn and listedOn ~= map then data.npcs[listedOn][id] = nil end
    data.npcs[map] = data.npcs[map] or {}
    data.npcs[map][id] = entry
    if next(data.npcs[listedOn or map] or {}) == nil then data.npcs[listedOn or map] = nil end
end

-- Names `id` as the step's NPC (the first, for a step that names one), and
-- keeps it in the guide's NPC list.
function Draft:SetNPC(step, id, name, map, at)
    return self:Change("npc", function()
        if not id then step.npc = nil return end
        self:KeepNPC(id, name, map, at)
        step.npc = { id }
    end)
end

-- Places --------------------------------------------------------------------------------------

-- The guide's places in the shape the Places panel and the place recorder
-- edit (the runtime's: `place`, points in map percent, `connections`), and
-- back. The panel works on that copy; SetPlaces keeps what it made.
function Draft:RuntimePlaces()
    local out = {}
    for index, place in ipairs(self.guide.data.places or {}) do
        local points = {}
        for at, point in ipairs(place.points or {}) do
            local where = point.at or {}
            points[at] = { at = { (where[1] or 0) / 100, (where[2] or 0) / 100 }, map = where.map, kind = point.kind,
                label = point.label, id = point.id }
        end
        local connections = {}
        for at, link in ipairs(place.links or {}) do connections[at] = { link.from, link.to, link.oneway and true or nil } end
        out[index] = { place = place.id, name = place.name, width = place.width, map = place.map,
            points = points, connections = connections }
    end
    return out
end

local function round(value) return math.floor((value or 0) * 100 + 0.5) end

local function placesFromRuntime(list)
    local out = {}
    for index, place in ipairs(list or {}) do
        local points = {}
        for at, point in ipairs(place.points or {}) do
            local where = point.at or {}
            points[at] = { id = point.id, at = { round(where[1]), round(where[2]), map = point.map }, kind = point.kind,
                label = point.label }
        end
        local links = {}
        for at, link in ipairs(place.connections or {}) do links[at] = { from = link[1], to = link[2], oneway = link[3] or nil } end
        out[index] = { id = place.place, name = place.name, width = place.width, map = place.map, points = points,
            links = #links > 0 and links or nil }
    end
    return out
end

-- Keeps places edited in the runtime shape, as one change; nothing happens
-- when they are what the guide already holds.
function Draft:SetPlaces(list)
    local places = placesFromRuntime(list)
    if #places == 0 then places = nil end
    local text = ns.modules.GuideText
    local before = self.guide.data.places and text:Write({ places = self.guide.data.places }) or ""
    local after = places and text:Write({ places = places }) or ""
    if before == after then return true end
    return self:Change("places", function() self.guide.data.places = places end)
end

-- Problems ------------------------------------------------------------------------------------

-- Steps:Expand's errors in the author's words. Each is the end of the
-- message, after the field it is about.
local PLAIN = {
    { "a talk step with no quests names its NPC", "Choose who to talk to, or add a quest." },
    { "an escort names the NPC escorted", "Choose the NPC to escort." },
    { "an escort names its quest", "Choose the escort's quest." },
    { "a collect step names its item", "Choose the item to collect." },
    { "a kill step names its creatures", "Choose the creatures to kill." },
    { "an interact step names its object", "Write what to click." },
    { "a learn step names its spells", "Add the spells to learn." },
    { "a cast step names one spell by ID", "Choose the spell to cast." },
    { "a skill step needs a rank", "Give the rank to reach." },
    { "a skillup step needs a rank", "Give the rank to craft up to." },
    { "a vendor step sells, repairs, or both", "Choose sell, repair or both." },
    { "a flight step names its TaxiNodes ID", "Choose the flight point." },
    { "a standing from 1 %(Hated%) to 8 %(Exalted%)", "Choose the standing to reach." },
    { "must be a positive level", "Give the level to reach." },
    { "no step is labelled", "It points at a step that is no longer in the guide." },
    { "group members are quest visits or quest objectives", "A group holds only quest visits and objectives: ungroup it." },
    { "is for turn%-ins", "Only a turn-in can be optional." },
}

local function plain(message)
    message = tostring(message):gsub("^NuuRoad: ", "")
    local field, rest = message:match("^(%S+): (.*)$")
    rest = rest or message
    for _, entry in ipairs(PLAIN) do
        if rest:find(entry[1]) then return entry[2] end
    end
    return rest:sub(1, 1):upper() .. rest:sub(2), field
end

-- "data.sections[2].steps[4].group[1]" -> section 2, item 4, member 1.
local function stepPath(message)
    local s, i, m = tostring(message):match("data%.sections%[(%d+)%]%.steps%[(%d+)%]%.group%[(%d+)%]")
    if s then return tonumber(s), tonumber(i), tonumber(m) end
    s, i = tostring(message):match("data%.sections%[(%d+)%]%.steps%[(%d+)%]")
    if s then return tonumber(s), tonumber(i), nil end
    return nil
end

-- The quests the guide takes anywhere, for the turn-in check.
local function acceptedQuests(guide)
    local taken = {}
    local function walk(step)
        for _, id in ipairs(step.type == "accept" and (type(step.quests) == "table" and step.quests or { step.quests }) or {}) do taken[id] = true end
        for _, id in ipairs(step.type == "talk" and step.accept or {}) do taken[id] = true end
    end
    for _, section in ipairs(guide.data.sections) do
        for _, item in ipairs(section.steps) do
            if item.group ~= nil then for _, member in ipairs(item.group) do walk(member) end else walk(item) end
        end
    end
    return taken
end

local function addProblem(problems, step, problem)
    problems[step] = problems[step] or {}
    table.insert(problems[step], problem)
end

-- What the guide says that may not be what the author meant, with the fix
-- where there is one. Warnings: the guide plays as written.
function Draft:Lint(problems)
    local taken = acceptedQuests(self.guide)
    for _, entry in ipairs(self:Entries()) do
        local step = entry.step
        if step.type == "turnin" and not step.optional then
            local missing = false
            for _, id in ipairs(type(step.quests) == "table" and step.quests or { step.quests }) do
                if not taken[id] then missing = true end
            end
            if missing then
                addProblem(problems, step, { level = "warning",
                    text = "Nothing in this guide accepts this quest, so most players will not have it.",
                    fix = { caption = "Make it optional", apply = function(draft) draft:SetField(step, "optional", true, "optional") end } })
            end
        end
        local npc = type(step.npc) == "table" and step.npc[1] or step.npc
        if type(npc) == "number" and not step.at and not step.stand then
            local entryNPC = self:NPC(npc)
            if type(entryNPC) ~= "table" or not entryNPC.at then
                addProblem(problems, step, { level = "warning", npcPosition = true,
                    text = "The guide does not say where this NPC stands, so the arrow has nowhere to point. Target them and press Use my target." })
            end
        end
        if step.type == "choice" and #(step.options or {}) == 0 then
            addProblem(problems, step, { level = "warning", text = "A choice needs at least one way to go." })
        end
    end
end

-- Builds the runtime guide from the value. A step Expand or Validate refuses
-- is noted and left out, and the guide is built again without it, so one
-- unfinished step costs only itself. Sets `built` (the runtime guide, or
-- nil when nothing could be built), `builtFrom` (the step each runtime
-- position came from), `problems` (step -> list) and `guideProblems`.
function Draft:Rebuild()
    local problems, guideProblems = {}, {}
    self.entries = nil
    local entries = self:Entries()
    local trial = copy(self.guide)
    -- A guide not saved yet has no stamp; the runtime guide needs one.
    if type(trial.updated) ~= "number" then trial.updated = now() end
    -- The trial's steps in run order, beside the draft's.
    local function trialEntries()
        local out = {}
        for sectionIndex, section in ipairs(trial.data.sections) do
            for at, item in ipairs(section.steps) do
                if item.group ~= nil then
                    for memberAt in ipairs(item.group) do out[#out + 1] = { sectionIndex, at, memberAt } end
                else
                    out[#out + 1] = { sectionIndex, at }
                end
            end
        end
        return out
    end
    -- Which draft step each trial position stands for; steps left out drop out.
    local origin = {}
    for index, entry in ipairs(entries) do origin[index] = entry.step end
    local function drop(sectionIndex, at, memberAt)
        local where = trialEntries()
        for index, pos in ipairs(where) do
            if pos[1] == sectionIndex and pos[2] == at and pos[3] == memberAt then
                table.remove(origin, index)
                break
            end
        end
        local section = trial.data.sections[sectionIndex]
        if memberAt then
            local wrapper = section.steps[at]
            table.remove(wrapper.group, memberAt)
            settleGroup(section, at)
        else
            table.remove(section.steps, at)
        end
        if #section.steps == 0 then table.remove(trial.data.sections, sectionIndex) end
    end
    local Steps, GuideCheck = ns.modules.Steps, ns.modules.GuideCheck
    local built
    for _ = 1, 40 do
        if #trial.data.sections == 0 then break end
        local ok, result = pcall(Steps.Expand, Steps, trial)
        if ok then
            local valid, errors = GuideCheck:Validate(result)
            if valid then built = result break end
            local index = tonumber(tostring(errors[1]):match("nodes%[(%d+)%]"))
            local where = index and trialEntries()[index]
            if not where then
                table.insert(guideProblems, (plain(errors[1])))
                break
            end
            local step = origin[index]
            if step then addProblem(problems, step, { level = "error", text = (plain(errors[1])) }) end
            drop(where[1], where[2], where[3])
        else
            local sectionIndex, at, memberAt = stepPath(result)
            local section = sectionIndex and trial.data.sections[sectionIndex]
            local item = section and section.steps[at]
            if not item or (memberAt and not (item.group and item.group[memberAt])) then
                table.insert(guideProblems, (plain(result)))
                break
            end
            -- The draft step at that trial position.
            local where, position = trialEntries(), nil
            for index, pos in ipairs(where) do
                if pos[1] == sectionIndex and pos[2] == at and (pos[3] == memberAt or (memberAt == nil and item.group and pos[3] == 1)) then
                    position = index
                    break
                end
            end
            local step = position and origin[position]
            if step then addProblem(problems, step, { level = "error", text = (plain(result)) }) end
            if item.group and not memberAt then
                -- A group refused as a whole: take it apart and try again.
                table.remove(section.steps, at)
                for offset, member in ipairs(item.group) do table.insert(section.steps, at + offset - 1, member) end
            else
                drop(sectionIndex, at, memberAt)
            end
        end
    end
    self:Lint(problems)
    self.problems, self.guideProblems = problems, guideProblems
    if built then
        ns.modules.GuideCheck:IndexNodes(built)
        self.built, self.builtFrom = built, origin
    else
        self.built, self.builtFrom = nil, nil
    end
    return built
end

-- The problems on one step, errors first.
function Draft:ProblemsOf(step)
    local list = self.problems and self.problems[step]
    if not list then return nil end
    table.sort(list, function(a, b) return (a.level == "error" and 0 or 1) < (b.level == "error" and 0 or 1) end)
    return list
end

function Draft:ProblemCount()
    local count = 0
    for _, list in pairs(self.problems or {}) do count = count + #list end
    return count + #(self.guideProblems or {})
end

-- Where each step of the last runtime guide went in this one: old runtime
-- position -> new runtime position, for the steps both have. `old` is the
-- list of steps the old guide was built from (builtSteps).
function Draft:Map(oldSteps)
    local newPosition, map = {}, {}
    for index, step in ipairs(self.builtFrom or {}) do newPosition[step] = index end
    for index, step in ipairs(oldSteps or {}) do
        if newPosition[step] then map[index] = newPosition[step] end
    end
    return map
end

-- The value to keep: the guide as it stands, every step included.
function Draft:Value()
    return copy(self.guide)
end

-- Text: the whole guide, or one step ---------------------------------------------------------

function Draft:Text()
    return ns.modules.GuideText:Write(self.guide)
end

-- Replaces the guide with one read from text, keeping its ID: the editor's
-- Edit as text. The value must be a guide source.
function Draft:ReplaceFromText(text)
    local value, problem = ns.modules.GuideText:Read(text)
    if not value then return false, problem end
    if value.kind ~= "guide" or type(value.data) ~= "table" or type(value.data.sections) ~= "table" or #value.data.sections == 0 then
        return false, "The text is not a guide: it needs kind = \"guide\" and data with sections."
    end
    return self:Change("text", function()
        value.id = self.guide.id
        self.guide = value
    end)
end

-- Replaces one step with the step read from text, in place.
function Draft:ReplaceStepFromText(step, text)
    local value, problem = ns.modules.GuideText:Read(text)
    if not value then return false, problem end
    if type(value.type) ~= "string" then return false, "The text is not a step: it needs a type." end
    return self:Change("text", function()
        for key in pairs(step) do step[key] = nil end
        for key, child in pairs(value) do step[key] = child end
    end)
end

ns:RegisterModule("GuideDraft", GuideDraft)
