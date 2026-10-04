local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local Proto = UI.Proto

-- A window of text for the player to copy out of the game: a report, test
-- results, anything they are asked to paste somewhere else. It opens with the
-- text selected, so Ctrl-C copies it at once; clicking back into it selects
-- it all again.
--
--   local copy = ui:CopyWindow{ key = "copy", place = db.windows }
--   copy:Show(text, "addon-comms")   copy:Hide()   copy:IsShown()   copy:GetText()
--
-- Spec: title ("Copy"), key and place, width and height, hint (the line over
-- the text). Show(text, title) replaces the text, and the title when given.
-- `copy.win` is the window, `copy.area` the text area.

local Copy = {}
Copy.__index = Copy

local HINT = "Selected: press Ctrl-C to copy. Click away and back in to select it all again."

function Proto:CopyWindow(spec)
    spec = spec or {}
    local width, height = spec.width or 560, spec.height or 460
    local win = self:Window({
        key = spec.key, place = spec.place, title = spec.title or "Copy",
        width = width, height = height, hidden = true,
    })
    local body = win:Column{ gap = 6, padding = 12 }
    local hint = body:Text{ spec.hint or HINT, style = "label", wrap = true }
    -- The box fills what the window leaves under the title band and the hint.
    local area = body:TextArea{ boxHeight = math.max(80, height - 110), selectAll = true }
    local copy = setmetatable({ win = win, area = area, hint = hint, title = spec.title or "Copy" }, Copy)
    return copy
end

function Copy:Show(text, title)
    self.area:SetText(text == nil and "" or tostring(text))
    self.win:SetTitle(title or self.title)
    self.win:Show()
    local box = self.area.box
    if box:HasFocus() then box:HighlightText() else box:SetFocus() end
end

function Copy:GetText()
    return self.area:GetText()
end

function Copy:Hide()
    self.area.box:ClearFocus()
    self.win:Hide()
end

function Copy:IsShown()
    return self.win:IsShown()
end
