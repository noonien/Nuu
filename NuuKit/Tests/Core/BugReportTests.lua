local Kit = _G.LoadKit().Kit

_G.time = function() return 1789862400 end
_G.date = function() return "2026-09-23 12:00:00" end
_G.UnitName = function() return "Dill Douse" end
_G.GetRealmName = function() return "Classic Beta PvP" end
_G.UnitLevel = function() return 13 end

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end
local function assertHas(text, fragment, message)
    if not text:find(fragment, 1, true) then error(message .. ": '" .. fragment .. "' not in report:\n" .. text, 2) end
end
local function assertLacks(text, fragment, message)
    if text:find(fragment, 1, true) then error(message .. ": '" .. fragment .. "' should not be in the report", 2) end
end

-- The addon's recorder, in its own saved table, with the player standing
-- somewhere and a few things done.
local db = {}
local recorder = Kit.NewRecorder({
    db = function() return db end,
    where = function() return 1413, 0.5, 0.3 end,
    version = "test",
})
recorder:Record("rec", { event = "accept", quest = 870 })
recorder:Record("rec", { event = "turnin", quest = 870, map = 1413, at = { 52, 31 } })

-- An addon that reports on a guide it is following: its subject is the guide
-- and the step the player named, its sections read them.
local guide = { id = "nuuroad:test", title = "Test Road", steps = 3, current = 2 }
local running = guide
local reports = Kit.NewBugReports({
    name = "NuuRoad",
    version = "test",
    recorder = recorder,
    subject = function(request)
        if not running then return nil end
        return { guide = running, index = tonumber(request.step) or running.current }
    end,
    fields = function(subject)
        return subject and { guide = subject.guide.id, step = subject.index, kind = "overridden?" } or nil
    end,
    defaultKind = "addon",
})
reports:AddSection("step", "Guide and step", function(subject)
    if not subject then return { "No guide is running." } end
    return { string.format("Guide %s, step %d of %d", Kit.BugReport.Quote(subject.guide.title), subject.index, subject.guide.steps) }
end)
reports:AddSection("where", "Where", function(_, self)
    local here = self.recorder:Where()
    return { string.format("Map %s at %s, %s", tostring(here.map), tostring(here.at[1]), tostring(here.at[2])) }
end)
reports:AddSection("navigation", "Navigation", function() error("navigation exploded") end)
reports:AddSection("empty", "Nothing to say", function() return {} end)
reports:AddKind("guide", {
    label = "Guide",
    sections = { "step" },
    categories = {
        { key = "stuck", label = "Step will not finish", tip = "You did what the step asks and it did not go green." },
        { key = "other", label = "Something else", tip = "Anything else about this guide." },
    },
})
reports:AddKind("addon", {
    label = "Addon",
    sections = { "recorder" },
    categories = {
        { key = "navigation", label = "Arrow and map pins", tip = "The arrow or the pins.", sections = { "step", "navigation", "empty" } },
        { key = "other", label = "Something else", tip = "Anything else about the addon.", sections = { "step" } },
    },
})
reports.leading = { "player", "where" }

-- The registry keeps the kinds in the order they were added.
local kinds = reports:Kinds()
assertEquals(kinds[1] .. "," .. kinds[2], "guide,addon", "kinds listed in the order added")
assertEquals(reports:Category("guide", "stuck").label, "Step will not finish", "a category is found by its key")
assertEquals(reports:Category("guide", "nope"), nil, "and an unknown one is not")

-- Sections: the ones every report carries, the kind's, the category's, in
-- that order and each once.
local sections = reports:Sections("addon", "navigation")
assertEquals(table.concat(sections, ","), "player,where,recorder,step,navigation,empty,recent", "leading, kind, category, trailing")
assertEquals(table.concat(reports:Sections("guide", "stuck"), ","), "player,where,step,recent", "a guide report leads with the step")

-- A guide report on the current step.
local report = reports:Build({ kind = "guide", category = "stuck", description = "  It stays red.  " })
local text = report.text
assertHas(text, "NuuRoad guide report: Step will not finish", "the header names the addon, the kind and category")
assertHas(text, "2026-09-23 12:00:00, NuuRoad test", "and when, on which version")
assertHas(text, "It stays red.", "the player's words are in it")
assertLacks(text, "  It stays red.", "trimmed")
assertHas(text, "== Player ==\nDill Douse-Classic Beta PvP", "the kit's player section names the character")
assertHas(text, "== Where ==\nMap 1413 at 50, 30", "the addon's own leading section")
assertHas(text, 'Guide "Test Road", step 2 of 3', "the subject reaches the sections")
assertHas(text, "== What the player did last ==", "the kit's recent section closes it")
assertHas(text, 'turnin', "with what the player did")
assertHas(text, "@ 1413 52, 31", "and where they did it")
assertLacks(text, "== Session log ==", "a guide report leaves the session log out")
assertEquals(report.data.kind, "guide", "the log row names the kind")
assertEquals(report.data.category, "stuck", "and the category")
assertEquals(report.data.guide, "nuuroad:test", "and the addon's own fields")
assertEquals(report.data.step, 2, "all of them")
assertEquals(report.data.description, "It stays red.", "and the words")
assertEquals(report.data.lines, report.lines, "and the report line for line")

-- The addon's fields never replace the kit's.
assertEquals(report.data.version, "test", "the version stays the kit's")

-- A step other than the current one, named by the player.
text = reports:Build({ kind = "guide", category = "stuck", step = 1 }).text
assertHas(text, "step 1 of 3", "the request reaches the subject")
assertHas(text, "(no description given)", "an empty description is said, not skipped")

-- An addon report: a section that throws becomes one line, an empty one is
-- left out, and the report still reaches its end.
text = reports:Build({ kind = "addon", category = "navigation", description = "Arrow spins." }).text
assertHas(text, "NuuRoad addon report: Arrow and map pins", "addon header")
assertHas(text, "== Session log ==", "the kit's recorder section")
assertHas(text, "Records in the log: 2", "reads the addon's own log")
assertHas(text, "== Navigation ==\nCould not be read: ", "a broken section is one line")
assertHas(text, "navigation exploded", "saying why")
assertLacks(text, "== Nothing to say ==", "a section with nothing to say is left out")
assertHas(text, "== What the player did last ==", "the report still reaches the end")

-- An unknown kind or category falls back rather than failing.
text = reports:Build({ kind = "nonsense", category = "nonsense" }).text
assertHas(text, "NuuRoad addon report: Something else", "unknown input becomes the default kind's last category")

-- No subject: the sections say so.
running = nil
text = reports:Build({ kind = "addon", category = "other" }).text
assertHas(text, "No guide is running.", "no guide is stated")
running = guide

-- A subject that throws is said once, and every section still runs.
local brokenSubject = Kit.NewBugReports({ name = "Broken", recorder = recorder, subject = function() error("progress not loaded") end })
brokenSubject:AddKind("addon", { label = "Addon", categories = { { key = "other", label = "Something else", tip = "" } } })
text = brokenSubject:Build({}).text
assertHas(text, "What the report is about could not be read: ", "the broken subject is one line")
assertHas(text, "progress not loaded", "saying why")
assertHas(text, "== Player ==", "and the rest of the report is there")

-- An addon that registered nothing still gets a report.
local bare = Kit.NewBugReports({ name = "Bare" })
text = bare:Build({ description = "x" }).text
assertHas(text, "Bare addon report: Something else", "no kinds still makes a report")
assertHas(text, "Nothing recorded", "and without a recorder the recent section says so")

-- The recent section reads the addon's own words for a row when it has them.
local described = Kit.NewBugReports({ name = "Described", recorder = recorder,
    describeRecord = function(row) return { text = "Did " .. row.d.event, time = "19:00" } end })
text = described:Build({}).text
assertHas(text, "19:00 Did accept", "a described row reads as the addon says")
local worded = Kit.NewBugReports({ name = "Worded", recorder = recorder, describeRecord = function(row) return row.d.event end })
assertHas(worded:Build({}).text, "1789862400 accept", "a plain string describes it too, stamped by the record")
local throwingDescribe = Kit.NewBugReports({ name = "T", recorder = recorder, describeRecord = function() error("boom") end })
assertHas(throwingDescribe:Build({}).text, 'event = "accept"', "a describer that throws falls back to the data")

-- A section registered under a kit name replaces the kit's.
described:AddSection("player", "Player", function() return { "the addon's own player line" } end)
assertHas(described:Build({}).text, "the addon's own player line", "an addon can replace a kit section")

-- Inline keeps one value on one line; Plain strips what is only for the screen.
assertEquals(Kit.BugReport.Inline("a\nb"), '"a\\nb"', "a newline is escaped")
assertEquals(Kit.BugReport.Inline({ 1, 2, x = "y" }), '{ 1, 2, x = "y" }', "list then sorted keys")
assertEquals(Kit.BugReport.Plain("Go to |cffff0000Ratchet|r"), "Go to Ratchet", "colour codes are stripped")

-- Filing writes one row to the addon's bug channel, with where it happened.
local filed = reports:File({ kind = "guide", category = "other", description = "Typo." })
local bugs = recorder:Records("bug")
assertEquals(#bugs, 1, "one row")
assertEquals(filed.record, bugs[1], "the report knows its row")
assertEquals(bugs[1].d.category, "other", "with the category")
assertEquals(bugs[1].d.lines[1], "NuuRoad guide report: Something else", "and the report line for line")
assertEquals(bugs[1].d.map, 1413, "and the place")
assertEquals(reports.sessionCount, 1, "counted for the session")
assert(filed.text:find("Typo.", 1, true), "the text comes back to show")
assertEquals(bare:File({}).record, nil, "an addon without a recorder files nothing, and does not fail")

-- Registering checks its input, so a mistake shows at load, not in a report.
assert(not pcall(reports.AddKind, reports, "x", { label = "X", categories = {} }), "a kind needs a category")
assert(not pcall(reports.AddSection, reports, "x", "X"), "a section needs a builder")

print("NuuKit bug report tests passed")
