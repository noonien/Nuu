local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- The window a player reports a bug from, on an addon's reports object
-- (Kit.NewBugReports): what it is about (the kinds), which kind of problem
-- (the kind's categories, each tip as its tooltip), a line in their own
-- words, and Report. Everything else a report needs is gathered by the
-- reports object the moment Report is pressed, so the form asks for nothing
-- the addon can find out for itself. A filed report goes to the session log
-- and is shown as text to copy.
--
-- What only the addon knows comes in through the spec: fields of its own
-- (a guide step), what the report will be about, and whether it can be
-- filed yet.
--
--   local form = ui:BugReportWindow{ key = "bugReport", place = db.windows, reports = reports,
--       defaultKind = function() return guideRunning and "guide" or "addon" end,
--       extra = function(area, form) form.data.step = area:Section{ "Which step" }:Input{ ... } end,
--       onShow = function(form) form.data.step:SetText(...) end,
--       check = function(form) return "Guide: Barrens", guideRunning or "No guide is running." end,
--       request = function(request, form) request.step = tonumber(form.data.step:GetText()) end }
--   form:Show("addon")   form:Toggle()   form:Hide()   form:Refresh()
--
-- Spec: reports (required), title ("Report a bug"), key and place, width
-- and height, defaultKind() (the kind Show picks when given none; the first
-- kind when not given), extra(area, form) (builds the addon's own fields,
-- after the categories and before the description; keep them in
-- `form.data`), onShow(form) (resets them), check(form) (returns a line
-- saying what the report will be about, and either true or the reason it
-- cannot be filed yet; called on every change), request(request, form)
-- (adds the addon's fields to what is filed), readyHint (the status while
-- it can be filed), submitTooltip, placeholder (the description's).
-- A kind added to the reports object may carry `caption` and `tooltip` for
-- its button; its `label` otherwise. `form.win` is the window; `form.kind`
-- and `form.category` what is chosen.

local Form = {}
Form.__index = Form

function Proto:BugReportWindow(spec)
    spec = spec or {}
    local form = setmetatable({ reports = spec.reports, spec = spec, data = {} }, Form)
    local win = self:Window({
        key = spec.key, place = spec.place, title = spec.title or "Report a bug",
        width = spec.width or 520, height = spec.height or 680,
        resizable = true, minWidth = 420, minHeight = 420, hidden = true, status = true,
    })
    form.win = win
    local body = win:Column{ gap = 10, padding = 12 }
    local area = body:ScrollArea{ grow = true, gap = 14, padding = 2 }

    -- What it is about: the question a player can always answer, and the one
    -- that decides which categories and which diagnostics follow.
    local about = area:Section{ "What it is about", gap = 6 }
    local kinds = { columns = 2, onChange = function(kind) form:SelectKind(kind) end }
    for _, key in ipairs(form:Kinds()) do
        local kind = form.reports:Kind(key)
        table.insert(kinds, { value = key, caption = kind.caption or kind.label or key, tooltip = kind.tooltip })
    end
    form.kinds = about:Choices(kinds)
    form.about = about:Text{ "", style = "label", wrap = true }

    -- The categories of the chosen kind, made again when the kind changes.
    local what = area:Section{ "What went wrong", hint = "hover one for what it covers", gap = 6 }
    form.categoryBox = what:Column{ gap = 0 }

    if spec.extra then spec.extra(area, form) end

    form.description = area:TextArea{ label = "What happened", boxHeight = 90, maxLetters = 1000,
        placeholder = spec.placeholder or "What you expected, what happened instead. For an error, paste its text here." }

    -- The filed report, to copy; shown once there is one.
    form.reportSection = area:Section{ "The report", hint = "click in it to select it all, then Ctrl-C to copy", gap = 6 }
    form.reportText = form.reportSection:TextArea{ boxHeight = 160 }
    form.reportSection:Hide()

    local foot = body:Row{ gap = 8, align = "right" }
    form.submit = foot:Button{ "Report", tone = "accent", tooltip = spec.submitTooltip
        or "Gathers the addon's state and writes it all to the session log.", onClick = function() form:Submit() end }
    return form
end

function Form:Kinds()
    local reports = self.reports
    return reports and reports:Kinds() or {}
end

-- The category buttons for the chosen kind, two to a row.
function Form:LayoutCategories()
    local box = self.categoryBox
    box:Clear()
    local kind = self.kind and self.reports:Kind(self.kind)
    local options = { columns = 2, value = self.category, onChange = function(key) self:SelectCategory(key) end }
    for _, category in ipairs(kind and kind.categories or {}) do
        table.insert(options, { value = category.key, caption = category.label, tooltip = category.tip })
    end
    self.categories = box:Choices(options)
end

function Form:SelectKind(kind)
    if kind ~= self.kind then self.category = nil end
    self.kind = kind
    if self.kinds:GetValue() ~= kind then self.kinds:SetValue(kind) end
    self:LayoutCategories()
    self:Refresh()
end

function Form:SelectCategory(key)
    self.category = key
    if self.categories and self.categories:GetValue() ~= key then self.categories:SetValue(key) end
    self:Refresh()
end

-- What the report will be about, said back to the player before they send
-- it, and whether Report can be pressed yet.
function Form:Refresh()
    local text, ready = nil, true
    if self.spec.check then
        local ok, said, allowed = pcall(self.spec.check, self)
        if ok then text, ready = said, allowed else text, ready = "Could not check the report: " .. tostring(said), true end
    end
    self.about:SetText(text or "")
    local reason
    if not self.category then
        reason = "Pick what kind of problem it is."
    elseif ready ~= true then
        reason = type(ready) == "string" and ready or "The report cannot be filed yet."
    end
    self.submit:SetEnabled(reason == nil, reason)
    if reason then
        self.win:Status(reason)
    elseif not self.filed then
        self.win:Status(self.spec.readyHint or "The addon's state is added for you.")
    end
end

function Form:Submit()
    local reports = self.reports
    if not (reports and self.category) then return nil end
    self.description:ClearFocus()
    local request = { kind = self.kind, category = self.category, description = self.description:GetText() }
    if self.spec.request then pcall(self.spec.request, request, self) end
    local ok, report = pcall(reports.File, reports, request)
    if not ok or type(report) ~= "table" then
        self.win:Status("The report could not be filed: " .. tostring(report), { tone = "danger" })
        return nil
    end
    self.filed = true
    self.description:SetText("")
    self.reportText:SetText(report.text or table.concat(report.lines or {}, "\n"))
    self.reportSection:Show()
    self.win:Status(string.format("Report %d saved to the session log; it reaches disk at logout or /reload.",
        tonumber(reports.sessionCount) or 1), { tone = "text" })
    return report
end

-- Opens the form afresh on `kind`, else the addon's default, else the first
-- kind; no category is picked.
function Form:Show(kind)
    self.filed, self.category = false, nil
    self.reportSection:Hide()
    self.reportText:SetText("")
    if self.spec.onShow then pcall(self.spec.onShow, self) end
    if not kind and self.spec.defaultKind then
        local ok, chosen = pcall(self.spec.defaultKind, self)
        if ok then kind = chosen end
    end
    self:SelectKind(kind or self:Kinds()[1])
    self.win:Show()
end

function Form:Hide()
    self.win:Hide()
end

function Form:IsShown()
    return self.win:IsShown()
end

function Form:Toggle(kind)
    if self.win:IsShown() then self.win:Hide() else self:Show(kind) end
end
