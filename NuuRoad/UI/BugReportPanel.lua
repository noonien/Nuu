local _, ns = ...

-- The window a player reports a bug from: the kit's form
-- (ui:BugReportWindow, NuuKit/UI/Screens/BugReportForm.lua) on NuuRoad's
-- reports (Domain/BugReport, Kit.NewBugReports). What is NuuRoad's own is
-- here: which step the report is about, what guide it names, and that a
-- guide report needs a guide running.
--
-- A filed report is written to the session log's `bug` channel and read out
-- of the saved variables outside the game (`sessions.py --bugs`).
local BugReportPanel = {}

-- The active guide and the step the report points at.
function BugReportPanel:Subject(step)
    local reports = ns.modules.BugReport
    if not (reports and reports.Subject) then return nil end
    local ok, subject = pcall(reports.Subject, reports, step)
    return ok and subject or nil
end

-- The step field and its hint, under the categories.
local function stepField(area, form)
    local where = area:Section{ "Which step", gap = 6 }
    local row = where:Row{ gap = 10 }
    form.data.step = row:Input{ width = 70, numeric = true, maxLetters = 5,
        onType = function() form:Refresh() end, onChange = function() form:Refresh() end }
    form.data.stepHint = row:Text{ "", grow = true, wrap = true }
end

-- What the report will be about, and whether it can be filed: a guide
-- report needs a guide running.
local function check(form)
    local step, hint = form.data.step, form.data.stepHint
    local subject = BugReportPanel:Subject()
    if not subject then
        hint:SetText("No guide, so no step.")
        step:SetEnabled(false)
        if form.kind == "guide" then
            return "No guide is running. Pick a guide first, or report the addon instead.",
                "No guide is running: report the addon instead."
        end
        return "No guide is running; the report will say so.", true
    end
    step:SetEnabled(true)
    local named = tonumber(step:GetText())
    local node = named and subject.guide.nodes and subject.guide.nodes[named]
    local current = subject.current and ("You are on step " .. subject.current .. ".") or "The guide is finished."
    if named and not node then
        hint:SetText("No step " .. named .. " in this guide. " .. current)
    elseif node then
        local Steps = ns.modules.Steps
        local title = Steps and Steps:Title(node) or node.title or ("Step " .. named)
        hint:SetText(title .. (named ~= subject.current and ("  (" .. current .. ")") or "  (you are here)"))
    else
        hint:SetText(current .. " Type another number if the problem was elsewhere.")
    end
    local meta = subject.guide.meta
    return "Guide: " .. tostring(meta and meta.title or subject.guide.id), true
end

function BugReportPanel:Build()
    if self.form then return self.form end
    self.form = ns:GetUI():BugReportWindow({
        key = "bugReport", place = ns.db and ns.db.windows, reports = ns.modules.BugReport,
        -- A running guide makes it a guide report, since that is what most
        -- reports are.
        defaultKind = function() return self:Subject() and "guide" or "addon" end,
        extra = stepField,
        onShow = function(form)
            local subject = self:Subject()
            form.data.step:SetText(subject and subject.current and tostring(subject.current) or "")
        end,
        check = check,
        request = function(request, form) request.step = tonumber(form.data.step:GetText()) end,
        readyHint = "Your position, the step, and the addon's state are added for you.",
        submitTooltip = "Gathers the guide, the step, your position, and the addon's state, and writes it all to the"
            .. " session log.",
    })
    self.win = self.form.win
    return self.form
end

-- `kind` preselects guide or addon.
function BugReportPanel:Show(kind)
    self:Build():Show(kind)
end

function BugReportPanel:Hide()
    if self.form then self.form:Hide() end
end

function BugReportPanel:Toggle(kind)
    self:Build():Toggle(kind)
end

ns:RegisterModule("BugReportPanel", BugReportPanel)
