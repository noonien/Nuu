local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- What an addon's session log holds (Kit.NewRecorder), read as a list of
-- one-line rows, each with a mark for its kind and the rest in a tooltip,
-- and the few things a player does to the log: turn recording on or off,
-- say how many days it keeps, clean it up, empty it. The kit knows the log;
-- what a row says is the addon's.
--
--   local log = ui:SessionLogWindow{ key = "sessionLog", place = db.windows,
--       recorder = ns.recorder, channel = "rec",
--       describe = function(row) return { kind = "accept", time = "12:04", text = "Accepted ...",
--           detail = { "..." } } end,
--       marks = { accept = { glyph = "!", tone = "accent" }, death = { glyph = "X", tone = "danger" } },
--       switch = { "Record what I do", bind = { settings, "enabled" }, default = true, tooltip = "..." },
--       enabled = function() return settings.enabled end,
--       keepDays = { bind = { settings, "keepDays" }, default = 10 },
--       recorded = "What is recorded, in one sentence.",
--       offHint = "Recording is off. Turn it on to log ..." }
--   log:Show()   log:Toggle()   log:Hide()   log:Refresh()   (after a new row)
--
-- Spec: recorder (required), channel ("rec"), describe(row) (a row's kind,
-- time, text and detail lines; a row it cannot describe, or throws on, is
-- shown plain), marks (a glyph and a tone per kind; unknown kinds get "-"
-- in muted), switch (a Toggle's spec for recording on or off, bound to the
-- addon's own setting; left out, no switch), enabled() (whether recording
-- is on, for the hint; the switch's value when not given), keepDays (a
-- NumberInput's spec, bound to the addon's setting; left out, no field),
-- recorded (fine print: what is recorded), onHint, offHint, empty, title
-- ("Session log"), key and place, width and height. `log.win` is the window.

local SessionLog = {}
SessionLog.__index = SessionLog

local STAMP, MARK = 40, 16

local function makeRow(row)
    row.stamp = row:Text{ "", style = "number", width = STAMP, justify = "RIGHT", color = "muted" }
    row.mark = row:Text{ "", width = MARK, justify = "CENTER" }
    row.line = row:Text{ "", grow = true }
end

-- A row as the addon describes it, or nil when it cannot: a log window is
-- not worth a Lua error.
function SessionLog:Describe(entry)
    if type(self.describe) ~= "function" then return nil end
    local ok, result = pcall(self.describe, entry)
    if not ok or type(result) ~= "table" then return nil end
    return result
end

function Proto:SessionLogWindow(spec)
    spec = spec or {}
    local log = setmetatable({
        recorder = spec.recorder, channel = spec.channel or "rec", describe = spec.describe,
        marks = spec.marks or {}, enabled = spec.enabled,
        onHint = spec.onHint or "Recording. Rows are saved when you log out.",
        offHint = spec.offHint or "Recording is off.",
    }, SessionLog)
    local win = self:Window({
        key = spec.key, place = spec.place, title = spec.title or "Session log",
        width = spec.width or 440, height = spec.height or 520,
        resizable = true, minWidth = 360, minHeight = 300, hidden = true,
    })
    log.win = win
    local body = win:Column{ gap = 8, padding = 12 }

    local top = body:Row{ gap = 8 }
    if spec.switch then
        local switch = {}
        for key, value in pairs(spec.switch) do switch[key] = value end
        local chosen = spec.switch.onChange
        switch.onChange = function(value, w)
            if chosen then chosen(value, w) end
            log:Refresh()
        end
        log.switch = top:Toggle(switch)
    end
    top:Spacer{}
    log.count = top:Text{ "", style = "label" }
    log.hint = body:Text{ "", style = "label", wrap = true }

    log.list = body:List{ grow = true, rowHeight = 18, gap = 6, make = makeRow,
        draw = function(row, entry, index)
            local detail = log:Describe(entry)
            local kind = detail and detail.kind or "note"
            local mark = log.marks[kind]
            row.stamp:SetText(detail and detail.time or tostring(index))
            row.mark:SetText(mark and mark.glyph or "-")
            row.mark:SetColor(mark and mark.tone or "muted")
            row.line:SetText(detail and detail.text or "")
        end,
        tooltip = function(entry)
            local detail = log:Describe(entry)
            if not detail then return nil end
            return function(tip)
                tip:SetText(detail.text or "", 1, 1, 1, 1, true)
                local muted = win.ui.tokens.muted
                for _, line in ipairs(type(detail.detail) == "table" and detail.detail or {}) do
                    tip:AddLine(tostring(line), muted[1], muted[2], muted[3], true)
                end
            end
        end,
        empty = spec.empty or "Nothing recorded yet." }

    if spec.recorded then body:Text{ spec.recorded, style = "fine", wrap = true } end
    local foot = body:Row{ gap = 8 }
    if spec.keepDays then
        local days = { min = 1, max = 365, help = "days kept in the log" }
        for key, value in pairs(spec.keepDays) do days[key] = value end
        log.keepDays = foot:NumberInput(days)
    end
    foot:Button{ "Clean up", tooltip = "Drop every record older than that now. It also happens at every login.",
        onClick = function() log:Prune() end }
    foot:Spacer{}
    foot:ConfirmButton{ "Clear log", tone = "danger", tooltip = "Empties the session log: every record of every"
        .. " session kept. Click twice to confirm.", onConfirm = function() log:Clear() end }
    return log
end

function SessionLog:Enabled()
    if type(self.enabled) == "function" then
        local ok, on = pcall(self.enabled)
        return ok and on == true
    end
    return self.switch ~= nil and self.switch:GetValue() == true
end

-- The rows: whatever the recorder's channel holds.
function SessionLog:Entries()
    local recorder = self.recorder
    if not recorder then return {} end
    local ok, rows = pcall(recorder.Records, recorder, self.channel)
    if not ok or type(rows) ~= "table" then return {} end
    return rows
end

-- The switch, the days and the rows, as they are now. Does nothing while
-- the window is away; call it after a new row or a change of the settings.
function SessionLog:Refresh()
    if not self.win:IsShown() then return end
    local on = self:Enabled()
    if self.switch and self.switch:GetValue() ~= on then self.switch:SetValue(on) end
    if self.keepDays and not self.keepDays:HasFocus() and self.recorder then
        self.keepDays:SetValue(self.recorder:KeepDays())
    end
    self.hint:SetText(on and self.onHint or self.offHint)
    self:Paint()
end

-- The log follows its own tail: a new row scrolls the list down unless the
-- player has taken it somewhere, and it follows again once they scroll back
-- to the bottom.
function SessionLog:Paint()
    local list = self.list
    local entries = self:Entries()
    local total = #entries
    self.count:SetText(total == 1 and "1 row" or (total .. " rows"))
    local following = self.follow or list:ScrollAt() >= list:ScrollRange()
    self.follow = nil
    list:SetItems(entries, true)
    if following then list:ScrollSet(list:ScrollRange()) end
end

function SessionLog:Prune()
    local recorder = self.recorder
    if not recorder then return 0 end
    local dropped = recorder:Prune()
    self.win:Status("Dropped " .. dropped .. " record" .. (dropped == 1 and "" or "s") .. " older than "
        .. recorder:KeepDays() .. " days.", { tone = "text" })
    self:Refresh()
    return dropped
end

function SessionLog:Clear()
    local recorder = self.recorder
    if not recorder then return 0 end
    local dropped = recorder:Clear()
    self.win:Status("The session log is empty (" .. tostring(dropped) .. " records went).", { tone = "text" })
    self:Refresh()
    return dropped
end

-- Opening the log shows its end, whatever the player last scrolled to.
function SessionLog:Show()
    self.follow = true
    if not self.win:IsShown() then self.win:Show() end
    self:Refresh()
end

function SessionLog:Hide()
    self.win:Hide()
end

function SessionLog:IsShown()
    return self.win:IsShown()
end

function SessionLog:Toggle()
    if self.win:IsShown() then self.win:Hide() else self:Show() end
end
