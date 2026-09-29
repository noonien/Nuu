-- The options window, the diagnostics window, the session log and the bug
-- report form, built on the kit's stand-in for the client and driven the
-- way a player drives them: switches clicked, sliders moved, numbers typed,
-- resets clicked, the look changed, recording turned off and on, a bug
-- filed. Nothing may reach the error handler, and the kit's reset audit
-- must find every change these screens make to a kit widget marked.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle = ctx.ns, ctx.check, ctx.settle

local Options = ns.modules.Options
local RecordingPanel = ns.modules.RecordingPanel
local BugReportPanel = ns.modules.BugReportPanel
local Config = ns.modules.Config
check(Options and RecordingPanel and BugReportPanel, "the forms are registered")

-- A module that shows settings: Config:Changed must reach it.
local heard = {}
if not ns.modules.FormsProbe then
    ns:RegisterModule("FormsProbe", { OnSettingChanged = function(_, path) heard[#heard + 1] = path end })
else
    ns.modules.FormsProbe.OnSettingChanged = function(_, path) heard[#heard + 1] = path end
end
local function heardPath(path)
    for _, seen in ipairs(heard) do if seen == path then return true end end
    return false
end
local settings = function() return ns.db.settings end

-- Opening ---------------------------------------------------------------------------

Options:Show()
settle()
ctx.noErrors("options open")
check(Options.win:IsShown(), "the options window shows")
local rows = {}
for _, row in ipairs(Options.rows) do rows[row.spec.path] = row end
local count = 0
for path in pairs(rows) do
    count = count + 1
    check(Config:Default(path) ~= nil or path:match("^realm%."), "a row for a real setting: " .. path)
end
check(count == 26, "a row for every option (" .. count .. ")")

-- Changing ----------------------------------------------------------------------------

-- A switch clicked.
local markWaiting = rows["tracker.markWaiting"]
check(markWaiting.control:GetValue() == false, "mark waiting starts off")
markWaiting.control:Click()
settle()
check(settings().tracker and settings().tracker.markWaiting == true, "the click is stored")
check(heardPath("tracker.markWaiting"), "Config:Changed reached the module")
check(markWaiting.control:IsStored(), "its reset shows")

-- A slider moved: the tracker's size in percent, stored as a scale.
local scale = rows["tracker.scale"]
check(scale.control:GetValue() == 100, "the tracker's size shows in percent")
scale.control.slider:SetValue(115)
settle()
check(math.abs(settings().tracker.scale - 1.15) < 1e-9, "the size is stored as a scale")
check(heardPath("tracker.scale"), "the size change is heard")

-- The steps on screen, through Config's own setter.
rows["stepList.rows"].control.slider:SetValue(4)
check(Config:Get("stepList.rows") == 4, "steps on screen stored")

-- A number stepped with its +.
local keepDays = rows["recording.keepDays"]
keepDays.control.plus:Click()
check(settings().recording.keepDays == 11, "keep days stepped up")
check(ns.recorder:KeepDays() == 11, "the recorder reads the new days")

-- The realm's rate typed, then a switch left unanswered by default.
local rate = rows["realm.xpRate"]
rate.control.box:SetFocus()
rate.control.box:SetText("1.5")
rate.control.box:Fire("OnEnterPressed")
check(Config:Get("realm.xpRate") == 1.5, "the experience rate is stored as a number")
check(rows["realm.selfFound"].control:GetValue() == false and not Config:IsSet("realm.selfFound"),
    "self found stays unanswered")
rows["realm.selfFound"].control:Click()
check(Config:Get("realm.selfFound") == true, "self found answered")
ctx.noErrors("options changed")

-- A setting changed elsewhere (the tracker's menu) shows here.
Config:Set("materials.shown", false)
check(rows["materials.shown"].control:GetValue() == false, "the options follow a change made elsewhere")

-- Resetting ---------------------------------------------------------------------------

heard = {}
markWaiting.setting.reset:Click()
settle()
check(not Config:IsSet("tracker.markWaiting"), "the reset forgets the choice")
check(markWaiting.control:GetValue() == false, "the switch shows the default")
check(heardPath("tracker.markWaiting"), "the reset is heard")
scale.setting.reset:Click()
check(not Config:IsSet("tracker.scale") and scale.control:GetValue() == 100, "the size back to 100%")

-- Recording turned off here goes through the recorder; its reset turns it
-- back on.
local record = rows["recording.enabled"]
record.control:Click()
check(Config:Get("recording.enabled") == false, "recording off")
record.setting.reset:Click()
check(Config:Get("recording.enabled") == true and not Config:IsSet("recording.enabled"), "recording back on, unstored")

-- Reset all, window places too.
ns.db.windows.probe = { x = 1, y = 2 }
Options:ResetAll()
settle()
check(next(settings()) == nil, "reset all leaves nothing stored")
check(ns.db.windows.probe == nil, "reset all forgets window places")
check(rows["realm.xpRate"].control:GetText() == "", "the rate box is empty again")
ctx.noErrors("options reset")

-- The look ------------------------------------------------------------------------------

Options:SetLook({ theme = "slate", accent = "#6f9dff" })
settle()
check(ns.db.look and ns.db.look.theme == "slate", "the look is kept in NuuRoadDB.look")
check(ns:GetUI():GetLook().theme == "slate", "the UI wears it")
Options:SetLook({ theme = "horde" })
settle()
Options:SetLook(nil)
settle()
ctx.noErrors("look")

-- Diagnostics -------------------------------------------------------------------------

Options:ShowDiagnostics()
settle()
check(Options.diagnostics:IsShown(), "diagnostics shows")
check(Options.diagnostics.text:GetText():find("Build", 1, true), "the client build is listed")
Options:ToggleDiagnostics()
check(not Options.diagnostics:IsShown(), "diagnostics put away")
Options:Toggle()
check(not Options.win:IsShown(), "options put away")
ctx.noErrors("diagnostics")

-- The session log -------------------------------------------------------------------------

Options:Show()
RecordingPanel:Toggle()
settle()
check(RecordingPanel.win:IsShown(), "the session log shows")
check(RecordingPanel.log.switch:GetValue() == true, "recording shows on")
local before = #RecordingPanel:Entries()
RecordingPanel.log.switch:Click()
settle()
check(Config:Get("recording.enabled") == false, "recording turned off from the log")
check(rows["recording.enabled"].control:GetValue() == false, "the options follow")
check(RecordingPanel.log.hint:GetText():find("off", 1, true), "the hint says it is off")
RecordingPanel.log.switch:Click()
settle()
check(Config:Get("recording.enabled") == true, "recording on again")
check(#RecordingPanel:Entries() > before, "turning it on is a row of the log")
check(#RecordingPanel.log.list:GetItems() == #RecordingPanel:Entries(), "the list holds every row")
check(RecordingPanel.log.count:GetText():find("row", 1, true), "the count shows")
RecordingPanel.log.keepDays.plus:Click()
check(Config:Get("recording.keepDays") == 11, "keep days from the log")
check(rows["recording.keepDays"].control:GetValue() == 11, "the options follow the days")
RecordingPanel:Prune()
RecordingPanel:Clear()
settle()
check(#RecordingPanel:Entries() == 0 and #RecordingPanel.log.list:GetItems() == 0, "clear empties the log")
RecordingPanel:Toggle()
check(not RecordingPanel.win:IsShown(), "the session log put away")
Config:Reset("recording.keepDays")
Options:Hide()
ctx.noErrors("session log")

-- The bug report ---------------------------------------------------------------------------

local form
local function file(kind)
    BugReportPanel:Show(kind)
    form = BugReportPanel.form
    settle()
    check(BugReportPanel.win:IsShown(), "the form shows")
    check(form.category == "other", "the form opens on the catch-all category")
    local buttons = form.categories.buttons
    check(#buttons > 1, "the kind's categories")
    buttons[1]:Click()
    check(form.category ~= nil, "a category picked")
    form.description:SetText("The arrow pointed the wrong way.")
    form.submit:Click()
    settle()
    check(form.filed, "filed")
    check(form.reportSection:IsShown(), "the report shows to copy")
    check(form.reportText:GetText():find("The arrow pointed the wrong way.", 1, true), "the report holds the words")
    check(form.description:GetText() == "", "the description is emptied")
end

local bugs = #ns.recorder:Records("bug")
file("addon")
check(#ns.recorder:Records("bug") == bugs + 1, "the report is on the bug channel")

-- The other kind: its categories replace the first's.
form.kinds.buttons[1]:Click()
settle()
check(form.kind == form.kinds.buttons[1].kitChoiceValue, "the kind picked")
check(form.category == "other", "a new kind opens on its own catch-all")

-- A guide report, with a guide running.
local Repository, Progress = ns.modules.GuideRepository, ns.modules.Progress
local guide = Repository:Get("nuuroad:getting-started")
check(guide, "a packaged guide to report on")
Progress:Select(guide)
-- Without a guide a guide report cannot be filed.
Progress:Deselect()
BugReportPanel:Show("guide")
settle()
check(not BugReportPanel:Subject(), "no guide running")
BugReportPanel.form.categories.buttons[1]:Click()
check(not BugReportPanel.form.submit:IsEnabled(), "no guide, no guide report")
Progress:Select(guide)
file("guide")
check(form.about:GetText():find("Guide:", 1, true), "the form names the guide")
form.data.step:SetText("1")
form:Refresh()
check(form.data.stepHint:GetText() ~= "", "the step is described")
local filed = ns.recorder:Records("bug")
local current = BugReportPanel:Subject().current
check(current and filed[#filed].d.step == current, "the step field goes with the report: "
    .. tostring(filed[#filed].d.step))
BugReportPanel:Toggle()
check(not BugReportPanel.win:IsShown(), "the form put away")

ctx.noErrors("forms")
print("NuuRoad options and forms UI tests passed")
