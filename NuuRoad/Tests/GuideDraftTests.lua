-- The editor's model (Domain/GuideDraft.lua) and the guide as text
-- (Data/GuideText.lua), outside the client: steps added, moved, grouped and
-- deleted in a guide source, labels made when something points at a step, undo
-- and redo, problems put on their step while the rest still builds, the
-- step map that keeps the tracker's place, saving through the repository,
-- and text written and read back.
local ns = NewNamespace()
ns.db = { account = { guides = {}, nextUserGuideNumber = 0 } }
Load(ns, "Data/IDNames.lua")
for _, file in ipairs({ "Data/GuideCheck.lua", "Data/Names.lua", "Data/Steps.lua", "Data/GuideText.lua",
    "Domain/GuideDraft.lua", "Domain/GuideRepository.lua", "Domain/Progress.lua" }) do Load(ns, file) end
local Draft, Text, Repository = ns.modules.GuideDraft, ns.modules.GuideText, ns.modules.GuideRepository

local function source()
    return { kind = "guide", id = "test:draft", updated = 1789862400, title = "Draft", category = "Test",
        data = { map = 1413,
            npcs = { [1413] = { [3448] = { name = "Tonga Runetotem", at = { 5226, 3193 } } } },
            sections = {
                { title = "One", steps = {
                    { group = {
                        { type = "accept", quests = { 870 }, npc = { 3448 } },
                        { type = "accept", quests = { 871 }, npc = { 3448 } },
                    } },
                    { type = "kill", kill = { 3244 }, quest = { 870, 1 } },
                    { type = "turnin", quests = { 870 }, npc = { 3448 } },
                } },
                { title = "Two", steps = {
                    { type = "note", note = "Walk on." },
                    { type = "finish", note = "Done." },
                } },
            } } }
end

local function titles(draft)
    local out = {}
    for _, entry in ipairs(draft:Entries()) do out[#out + 1] = entry.step.type end
    return table.concat(out, ",")
end

-- Opening: the steps in run order, a runtime guide that plays.
local draft = Draft:Open(source())
assert(draft:Count() == 6, "six steps")
assert(titles(draft) == "accept,accept,kill,turnin,note,finish", titles(draft))
assert(draft.built and #draft.built.nodes == 6, "the whole guide builds")
assert(draft:ProblemCount() == 0, "no problems: " .. draft:ProblemCount())
assert(draft:Entries()[1].group and draft:Entries()[2].group, "the group's members know their group")

-- Adding after a group member goes after the group.
local first = draft:StepAt(1)
local added = draft:Insert(first, { type = "note", note = "Here" })
assert(added and draft:EntryOf(added).position == 3 and not draft:EntryOf(added).group, "after the group, not in it")
assert(draft:Undo() == "add" and draft:Count() == 6, "undone")
assert(draft:Redo() == "add" and draft:Count() == 7, "and done again")
draft:Undo()

-- Moving: within a section, then across into the next one.
local turnin = draft:StepAt(4)
assert(draft:Move(turnin, 1))
assert(draft:EntryOf(turnin).section == 2 and draft:EntryOf(turnin).at == 1, "into the next section at its start")
assert(draft:Move(turnin, -1))
assert(draft:EntryOf(turnin).section == 1 and draft:EntryOf(turnin).position == 4, "and back")
-- A group member moved past its group's edge leaves it; the group of one is undone.
local second = draft:StepAt(2)
assert(draft:Move(second, 1))
assert(not draft:EntryOf(second).group and not draft:EntryOf(draft:StepAt(1)).group, "the group came apart")
draft:Undo()
assert(draft:EntryOf(draft:StepAt(2)).group, "undo puts it back together")

-- Grouping: a kill for an objective may join; a vendor visit may not, and
-- the guide says why on the step.
assert(draft:GroupWithNext(draft:StepAt(1)) and draft:EntryOf(draft:StepAt(3)).group, "the objective joins")
draft:Undo()
local shop = draft:Insert(draft:StepAt(2), { type = "vendor", sell = true })
assert(draft:GroupWithNext(draft:StepAt(1)))
local problems = draft:ProblemsOf(shop)
assert(problems and problems[1].level == "error" and problems[1].text:find("ungroup"), "the problem is on the step")
assert(draft.built and #draft.built.nodes == 6, "the rest still builds")
draft:Undo()
draft:Undo()
assert(draft:ProblemCount() == 0 and draft:Count() == 6)

-- A half-made step: a talk with no NPC and no quests. Left out of the
-- runtime guide, with the problem in the author's words.
local talk = draft:Insert(draft:StepAt(4), { type = "talk" })
problems = draft:ProblemsOf(talk)
assert(problems and problems[1].text == "Choose who to talk to, or add a quest.", problems and problems[1].text)
assert(#draft.built.nodes == 6, "built without it")
assert(draft:SetField(talk, "npc", { 3448 }))
assert(not draft:ProblemsOf(talk) and #draft.built.nodes == 7, "fixed, and in")

-- Changing type puts aside what only the old type had, and gives it back.
assert(draft:SetType(talk, "vendor"))
assert(talk.sell == true and talk.npc[1] == 3448, "a vendor sells by default; the NPC stays")
assert(draft:SetField(talk, "sell", nil))
assert(draft:ProblemsOf(talk)[1].text == "Choose sell, repair or both.")
draft:SetField(talk, "repair", true)
draft:SetType(talk, "turnin")
draft:SetField(talk, "quests", { 871 })
draft:SetType(talk, "kill")
assert(talk.quests == nil, "the turn-in's quests are put aside")
draft:SetType(talk, "turnin")
assert(talk.quests and talk.quests[1] == 871, "and given back")

-- Lint: a turn-in nothing accepts, with its fix.
local stray = draft:Insert(talk, { type = "turnin", quests = { 999 }, npc = { 3448 } })
problems = draft:ProblemsOf(stray)
assert(problems and problems[1].level == "warning" and problems[1].fix, "a warning with a fix")
problems[1].fix.apply(draft)
assert(stray.optional == true and not draft:ProblemsOf(stray), "optional now")

-- An NPC the guide does not place.
local vendor = draft:Insert(stray, { type = "vendor", sell = true, npc = { 2136 } })
assert(draft:ProblemsOf(vendor)[1].npcPosition, "no position for the arrow")
draft:SetNPC(vendor, 2136, "Oliver Dwor", 1413, { 6100, 5200 })
assert(not draft:ProblemsOf(vendor), "placed")
assert(draft:NPCName(2136) == "Oliver Dwor" and draft.guide.data.npcs[1413][2136].at[1] == 6100, "kept in the guide's NPCs")

-- Labels are made when something points at a step, and a choice goes there.
local finish = draft:StepAt(draft:Count())
local choice = draft:Insert(draft:StepAt(1), { type = "choice", text = "Which way?" })
assert(draft:ProblemsOf(choice)[1].text:find("at least one"), "a choice with nowhere to go")
assert(draft:SetOption(choice, 1, "Straight to the end", finish, "the end"))
assert(finish.label == "the-end" and choice.options[1].go == "the-end", "labelled from the hint")
assert(not draft:ProblemsOf(choice), "fine now")
local carried = draft:StepAt(4)
assert(draft:Point(carried, "with", finish, "the end"))
assert(carried.with == "the-end", "the label is reused")
-- Deleting the target takes away what pointed at it.
assert(draft:Delete(finish))
assert(choice.options == nil and carried.with == nil, "nothing points at a step that is gone")
assert(not draft:Delete(draft:StepAt(1)) == false)

-- Sections: split, renamed, merged.
local count = #draft:Sections()
local fourth = draft:StepAt(4)
assert(draft:SplitSection(fourth, "Later"))
assert(#draft:Sections() == count + 1 and draft:EntryOf(fourth).section == 2 and draft:EntryOf(fourth).at == 1)
assert(draft:RenameSection(2, "Much later") and draft:Sections()[2].title == "Much later")
assert(draft:MergeSection(2) and #draft:Sections() == count)
local sectionStep = draft:AddSection("Extra")
assert(sectionStep and draft:EntryOf(sectionStep).section == #draft:Sections())
assert(draft:MoveToSection(draft:StepAt(1), #draft:Sections()))
assert(draft:Entries()[draft:Count()].section == #draft:Sections())

-- The last step cannot go.
local single = Draft:New("Tiny", 1413)
assert(single:Count() == 1 and single.built, "a new guide builds")
local ok, why = single:Delete(single:StepAt(1))
assert(not ok and why:find("at least one"))

-- The step map: where each runtime position went.
local mapped = Draft:Open(source())
local before = mapped.builtSteps
mapped:Insert(nil, { type = "note", note = "First" })
local map = mapped:Map(before)
assert(map[1] == 2 and map[6] == 7, "every old step moved down one")

-- Saving: a packaged guide becomes the player's own copy on its first save,
-- and the tracker's place follows it.
ns.packagedGuides = { source() }
Repository:Initialize()
local Progress = ns.modules.Progress
Progress.store = { openGuides = { "test:draft" }, activeGuideID = "test:draft" }
local packaged = Repository:Get("test:draft")
local state = Progress:GetState(packaged)
state.currentStep = 4
local copy = Draft:Open(Repository:Source("test:draft"), { copyOf = "test:draft" })
local steps = copy.builtSteps
copy:Insert(nil, { type = "note", note = "Before everything" })
local old, new = Repository:SaveDraft(copy)
assert(old == packaged and new and new.id == "user:guide-1", "a copy of its own")
assert(copy.guide.title == "Draft (my copy)" and ns.db.account.guides["user:guide-1"].kind == "guide", "kept as a source")
Progress:Rebuilt(old, new, copy:Map(steps))
assert(Progress.store.activeGuideID == "user:guide-1" and Progress.store.openGuides[1] == "user:guide-1", "the tab follows the copy")
assert(Progress:GetState(new).currentStep == 5, "still on the same step, one further down")
assert(Repository:Get("test:draft") == packaged, "the packaged guide is untouched")
-- Built again at login from what was kept.
Repository:BuildUserGuides()
assert(Repository:Get("user:guide-1") and #Repository:Get("user:guide-1").nodes == 7, "rebuilt from its source")

-- Text: written, read back, the same guide.
local text = Text:Write(source())
assert(text:find('type = "accept", quests = { 870 }, npc = { 3448 }', 1, true), "a step on one line, type first")
local back = assert(Text:Read(text))
assert(Text:Write(back) == text, "round trip")
assert(Text:Read("return " .. text), "a leading return is fine")
local value, problem = Text:Read("{ kind = 'guide', x = 1.5 }")
assert(not value and problem:find("whole"), "no fractions")
value, problem = Text:Read("{ kind = os.exit() }")
assert(not value and problem:find("does not read"), "nothing to call")
value = Text:Read(Text:WriteStep({ type = "kill", kill = { 1, 2 }, note = "a\nb" }))
assert(value.type == "kill" and value.note == "a\nb", "a step, newlines kept")

-- Edit as text: the guide replaced, its ID kept; a step replaced in place.
local edited = Draft:Open(source())
assert(edited:ReplaceFromText(text:gsub('"Walk on%."', '"Run on."')))
assert(edited:StepAt(5).note == "Run on." and edited.guide.id == "test:draft")
local stepNow = edited:StepAt(5)
assert(edited:ReplaceStepFromText(stepNow, '{ type = "note", note = "Swapped" }'))
assert(edited:StepAt(5) == stepNow and stepNow.note == "Swapped", "the same step table")
assert(not edited:ReplaceStepFromText(stepNow, "{ note = 'no type' }"))

print("guide draft tests passed")

-- Several steps at once, each one change.
local many = Draft:Open(source())
local s1, s2, s3, s4 = many:StepAt(1), many:StepAt(2), many:StepAt(3), many:StepAt(4)
local ok, why = many:GroupSteps({ s2, s3 })
assert(not ok and why:find("whole group"), "half a group is refused: " .. tostring(why))
local gok, gwhy = many:GroupSteps({ s1, s2, s3 })
assert(gok, "a group and the step after it: " .. tostring(gwhy))
assert(many:EntryOf(s3).group and #many:EntryOf(s3).group.group == 3, "one group of three")
assert(many:Undo() and not many:Entries()[3].group, "one undo")
s1, s2, s3, s4 = many:StepAt(1), many:StepAt(2), many:StepAt(3), many:StepAt(4)
assert(many:UngroupMany({ s1 }) and not many:EntryOf(s2).group, "taken apart")
local fifth = many:StepAt(5)
ok, why = many:GroupSteps({ s4, fifth })
assert(not ok and why:find("one section"), "not across sections")
assert(many:MoveMany({ s3, s4 }, -1))
assert(many:EntryOf(s3).position == 2 and many:EntryOf(s4).position == 3, "moved up as a block")
assert(many:MoveManyToSection({ s1, s2 }, 2))
assert(many:EntryOf(s1).section == many:EntryOf(s2).section and many:EntryOf(s2).position == many:Count(), "into the last section, in order")
local twins = many:DuplicateMany({ s3, s4 })
assert(twins and #twins == 2 and many:EntryOf(twins[1]).position == many:EntryOf(s4).position + 1, "copies after the last")
assert(many:SetFieldsMany({ s3, s4 }, { cond = { class = "ROGUE" } }, "who"))
assert(s3.cond.class == "ROGUE" and s4.cond.class == "ROGUE" and s3.cond ~= s4.cond, "the same rule, each its own table")
local before = many:Count()
assert(many:DeleteMany({ s3, s4, twins[1] }) and many:Count() == before - 3, "deleted together")
assert(many:Undo() and many:Count() == before, "and back with one undo")
ok = many:DeleteMany(many:Entries() and (function() local all = {} for _, e in ipairs(many:Entries()) do all[#all + 1] = e.step end return all end)())
assert(not ok, "not every step")
print("guide draft multi tests passed")
