-- The shared windows: diagnostics, the session log and the bug report form,
-- on a recorder and a reports object of their own.

local ctx = ...
local Kit, UI, ui, assertTrue, layout = ctx.Kit, ctx.UI, ctx.ui, ctx.assertTrue, ctx.layout

-- Diagnostics: the lines read again on every opening; a source that throws
-- is one line saying so.
local build = "Build 1"
local diagnostics = ui:DiagnosticsWindow{ lines = function() return { build, "Saved data sessions: 3" } end }
diagnostics:Show()
layout()
assertTrue(diagnostics:IsShown() and diagnostics.text:GetText() == "Build 1\nSaved data sessions: 3", "diagnostics lists the lines")
build = "Build 2"
diagnostics:Toggle()
assertTrue(not diagnostics:IsShown(), "diagnostics toggles away")
diagnostics:Toggle()
assertTrue(diagnostics.text:GetText():find("Build 2", 1, true), "the lines are read again")
diagnostics:Hide()
local broken = ui:DiagnosticsWindow{ lines = function() error("no client") end }
broken:Show()
assertTrue(broken.text:GetText():find("could not be read", 1, true), "a failing source says so")
broken:Hide()

-- The session log, on a recorder of its own and settings of its own.
local db, settings = {}, { enabled = true }
local recorder = Kit.NewRecorder({ db = function() return db end, keepDays = function() return settings.keepDays end })
local rows = recorder:Records("rec")
rows[1] = { at = 1, d = { event = "accept", quest = 1 } }
rows[2] = { at = 2, d = { event = "death" } }
rows[3] = { at = 3, d = "not described" }
local log = ui:SessionLogWindow{
    recorder = recorder,
    describe = function(row)
        if type(row.d) ~= "table" then error("cannot describe it") end
        return { kind = row.d.event, time = "0:0" .. row.at, text = row.d.event .. " happened", detail = { "more" } }
    end,
    marks = { accept = { glyph = "!", tone = "accent" }, death = { glyph = "X", tone = "danger" } },
    switch = { "Record what I do", bind = { settings, "enabled" }, default = true },
    keepDays = { bind = { settings, "keepDays" }, default = 10 },
    recorded = "What is recorded.",
    offHint = "Recording is off.",
}
log:Show()
layout()
assertTrue(log:IsShown() and #log.list:GetItems() == 3, "the log lists every row")
assertTrue(log.count:GetText() == "3 rows", "the count: " .. log.count:GetText())
assertTrue(log.switch:GetValue() == true and log.hint:GetText():find("Recording", 1, true), "recording shows on")
log.switch:Click()
layout()
assertTrue(settings.enabled == false and log.hint:GetText() == "Recording is off.", "the switch writes the addon's setting")
assertTrue(log.keepDays:GetValue() == 10, "the days the recorder keeps")
log.keepDays.plus:Click()
assertTrue(settings.keepDays == 11 and recorder:KeepDays() == 11, "the days write the addon's setting")
rows[4] = { at = 4, d = { event = "accept" } }
log:Refresh()
assertTrue(#log.list:GetItems() == 4, "a refresh after a new row lists it")
log:Prune()
log:Clear()
layout()
assertTrue(#log:Entries() == 0 and #log.list:GetItems() == 0 and log.count:GetText() == "0 rows", "clear empties the log")
log:Toggle()
assertTrue(not log:IsShown(), "the log toggles away")

-- The bug report form, on a reports object of its own, with a field of the
-- addon's and a check that holds one kind back.
local reports = Kit.NewBugReports({ name = "Smoke", recorder = recorder, fields = function(_, request)
    return { where = request.where } end })
reports:AddKind("content", { label = "Content", caption = "The content", tooltip = "What it shows.",
    categories = { { key = "wrong", label = "Wrong", tip = "It is wrong." }, { key = "other", label = "Other" } } })
reports:AddKind("addon", { label = "Addon", categories = { { key = "error", label = "Lua error" },
    { key = "other", label = "Other" } } })
local ready = false
local form = ui:BugReportWindow{
    reports = reports,
    defaultKind = function() return "addon" end,
    extra = function(area, f) f.data.where = area:Input{ label = "Where" } end,
    onShow = function(f) f.data.where:SetText("here") end,
    check = function(f)
        if f.kind == "content" and not ready then return "Nothing to report on.", "Open something first." end
        return "About: " .. tostring(f.kind), true
    end,
    request = function(request, f) request.where = f.data.where:GetText() end,
}
form:Show()
layout()
assertTrue(form:IsShown() and form.kind == "addon", "the addon's default kind")
assertTrue(form.kinds.buttons[1]:GetText() == "The content", "a kind's caption on its button")
assertTrue(form.data.where:GetText() == "here", "the addon's field is set on showing")
assertTrue(form.category == "other" and form.submit:IsEnabled(), "the kind opens on its catch-all, ready to file")
form.categories.buttons[1]:Click()
assertTrue(form.category == "error" and form.submit:IsEnabled(), "a category makes it ready")
assertTrue(form.about:GetText() == "About: addon", "the addon says what it is about")
form.kinds.buttons[1]:Click()
layout()
assertTrue(form.kind == "content" and form.category == "other", "another kind opens on its own catch-all")
form.categories.buttons[1]:Click()
assertTrue(not form.submit:IsEnabled(), "the addon's check holds it back")
ready = true
form:Refresh()
assertTrue(form.submit:IsEnabled(), "and lets it go")
form.description:SetText("It broke.")
form.submit:Click()
layout()
local filed = recorder:Records("bug")
assertTrue(form.filed and #filed == 1 and filed[1].d.where == "here" and filed[1].d.category == "wrong",
    "filed with the addon's field")
assertTrue(form.reportSection:IsShown() and form.reportText:GetText():find("It broke.", 1, true), "the report to copy")
form:Show()
assertTrue(not form.reportSection:IsShown() and form.category == "other", "opening again starts afresh")
form:Toggle()
assertTrue(not form:IsShown(), "the form toggles away")
