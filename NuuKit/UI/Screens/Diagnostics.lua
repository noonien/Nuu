local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- A window of plain report lines an addon gathers about itself and the
-- client (build, detected APIs, saved data): read once and put away. The
-- lines are read again every time it opens.
--
--   local diagnostics = ui:DiagnosticsWindow{ key = "diagnostics", place = db.windows,
--       lines = function() return Client:GetDiagnosticLines() end }
--   diagnostics:Show()   diagnostics:Toggle()   diagnostics:Hide()   diagnostics:Refresh()
--
-- Spec: lines (function returning a list of strings; an error or anything
-- but a table becomes one line saying so), title ("Diagnostics"), key and
-- place, width and height. `diagnostics.win` is the window.

local Diagnostics = {}
Diagnostics.__index = Diagnostics

function Proto:DiagnosticsWindow(spec)
    spec = spec or {}
    local win = self:Window({
        key = spec.key, place = spec.place, title = spec.title or "Diagnostics",
        width = spec.width or 480, height = spec.height or 360,
        resizable = true, minWidth = 320, minHeight = 160, hidden = true,
    })
    local area = win:Column{ padding = 12 }:ScrollArea{ grow = true }
    return setmetatable({ win = win, text = area:Text{ "", wrap = true }, source = spec.lines }, Diagnostics)
end

-- The lines as the addon gives them, or one line saying why there are none.
function Diagnostics:Lines()
    if type(self.source) ~= "function" then return {} end
    local ok, lines = pcall(self.source)
    if not ok then return { "The report could not be read: " .. tostring(lines) } end
    if type(lines) ~= "table" then return { "The report could not be read." } end
    return lines
end

function Diagnostics:Refresh()
    local out = {}
    for index, line in ipairs(self:Lines()) do out[index] = tostring(line) end
    self.text:SetText(table.concat(out, "\n"))
end

function Diagnostics:Show()
    self:Refresh()
    self.win:Show()
end

function Diagnostics:Hide()
    self.win:Hide()
end

function Diagnostics:IsShown()
    return self.win:IsShown()
end

function Diagnostics:Toggle()
    if self.win:IsShown() then self.win:Hide() else self:Show() end
end
