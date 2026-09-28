-- A stand-in for the client's frame API, enough for the kit to build and run
-- every widget. Installs itself in _G; returns what the smoke tests look at.

local function assertTrue(value, message)
    if not value then error(message, 2) end
end

local objects = {}
local Object = {}
local function noop() end

local function new(kind, parent)
    local o = setmetatable({
        kind = kind, parent = parent, points = {}, scripts = {}, hooks = {}, shown = true,
        width = 0, height = 0, text = "", enabled = true, level = parent and ((parent.level or 0) + 1) or 1,
    }, Object)
    objects[#objects + 1] = o
    return o
end

-- Unknown methods do nothing, as long as the name looks like a WoW method.
-- The kit's own methods are left out, so calling one before the kit adds it
-- (a Repaint before Finish) fails here as it does in the client.
local KIT_METHODS = { Repaint = true }
Object.__index = function(self, key)
    local method = rawget(Object, key)
    if method then return method end
    if type(key) == "string" and key:match("^[A-Z]") and not KIT_METHODS[key] and not key:match("^Kit") then return noop end
    return nil
end

function Object:GetObjectType() return self.kind end
function Object:GetParent() return self.parent end
function Object:SetParent(p) self.parent = p end
function Object:SetSize(w, h) self:SetWidth(w); self:SetHeight(h) end
function Object:SetWidth(w)
    assertTrue(type(w) == "number" and w == w, "SetWidth with " .. tostring(w))
    if w ~= self.width then self.width = w; self:Fire("OnSizeChanged", self.width, self.height) end
end
function Object:SetHeight(h)
    assertTrue(type(h) == "number" and h == h, "SetHeight with " .. tostring(h))
    if h ~= self.height then self.height = h; self:Fire("OnSizeChanged", self.width, self.height) end
end
-- A frame held by opposite anchors takes its size from them, as in the client.
local function anchor(self, names)
    for _, p in ipairs(self.points) do
        if p[1] == "ALL" then return p end
        for _, name in ipairs(names) do
            if p[1] == name then
                if type(p[2]) == "number" then return { p[1], self.parent, p[1], p[2], p[3] } end
                return p
            end
        end
    end
end
local depthGuard = 0
function Object:GetWidth()
    local all = anchor(self, {})
    local left, right = anchor(self, { "TOPLEFT", "LEFT", "BOTTOMLEFT" }), anchor(self, { "TOPRIGHT", "RIGHT", "BOTTOMRIGHT" })
    local rel = all and (all[2] or self.parent) or (left and right and (left[2] or self.parent))
    if rel and depthGuard < 50 and (all or right[2] == nil or right[2] == rel) then
        depthGuard = depthGuard + 1
        local w = rel:GetWidth()
        depthGuard = depthGuard - 1
        if all then return w end
        return w - (left[4] or 0) + (right[4] or 0)
    end
    return self.width
end
function Object:GetHeight()
    local all = anchor(self, {})
    local top, bottom = anchor(self, { "TOPLEFT", "TOP", "TOPRIGHT" }), anchor(self, { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })
    local rel = all and (all[2] or self.parent) or (top and bottom and (top[2] or self.parent))
    if rel and depthGuard < 50 and (all or bottom[2] == nil or bottom[2] == rel) then
        depthGuard = depthGuard + 1
        local h = rel:GetHeight()
        depthGuard = depthGuard - 1
        if all then return h end
        return h + (top[5] or 0) - (bottom[5] or 0)
    end
    return self.height
end
function Object:GetSize() return self:GetWidth(), self:GetHeight() end
function Object:SetPoint(...)
    local args = { ... }
    for index = 2, #args do
        local a = args[index]
        if type(a) == "number" then assertTrue(a == a, "SetPoint with NaN") end
    end
    table.insert(self.points, args)
end
function Object:ClearAllPoints() self.points = {} end
function Object:GetNumPoints() return #self.points end
function Object:GetPoint(i) return unpack(self.points[i] or {}) end
function Object:SetAllPoints(target) self.points = { { "ALL", target } } end
function Object:GetLeft() return 100 end
function Object:GetTop() return 500 end
function Object:GetRight() return 100 + self:GetWidth() end
function Object:GetBottom() return 500 - self:GetHeight() end
function Object:GetEffectiveScale() return 1 end
function Object:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
function Object:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
function Object:SetShown(on) if on then self:Show() else self:Hide() end end
function Object:IsShown() return self.shown end
function Object:SetAlpha(a) self.alpha = a end
function Object:EnableMouseWheel(on) self.wheel = on and true or false end
function Object:GetAlpha() return self.alpha or 1 end
function Object:IsVisible()
    local o = self
    while o do
        if not o.shown then return false end
        o = o.parent
    end
    return true
end
function Object:IsMouseOver() return false end
function Object:GetFrameLevel() return self.level end
function Object:SetFrameLevel(l) self.level = l end
function Object:SetScript(name, fn) self.scripts[name] = fn end
function Object:GetScript(name) return self.scripts[name] end
function Object:HookScript(name, fn)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], fn)
end
function Object:Fire(name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, fn in ipairs(self.hooks[name] or {}) do fn(self, ...) end
end
function Object:CreateTexture() return new("Texture", self) end
function Object:CreateLine() return new("Line", self) end
function Object:CreateFontString() return new("FontString", self) end
function Object:CreateAnimationGroup() return new("AnimationGroup", self) end
function Object:CreateAnimation() return new("Animation", self) end
function Object:SetText(text) self.text = text == nil and "" or tostring(text) end
function Object:GetText() return self.text end
function Object:GetStringWidth() return #(self.text or "") * 6 end
function Object:GetUnboundedStringWidth() return #(self.text or "") * 6 end
function Object:GetStringHeight() return 12 end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", 11, "" end
function Object:GetTextColor() return 1, 1, 1, 1 end
function Object:SetTexture(path) self.texture = path; return true end
function Object:GetTexture() return self.texture end
function Object:IsEnabled() return self.enabled end
function Object:Enable() self.enabled = true; self:Fire("OnEnable") end
function Object:Disable() self.enabled = false; self:Fire("OnDisable") end
function Object:SetEnabled(on) if on then self:Enable() else self:Disable() end end
function Object:HasFocus() return self.focus or false end
function Object:SetFocus() self.focus = true; self:Fire("OnEditFocusGained") end
function Object:ClearFocus() if self.focus then self.focus = false; self:Fire("OnEditFocusLost") end end
function Object:IsMultiLine() return self.multi end
function Object:SetMultiLine(on) self.multi = on end
function Object:GetVerticalScroll() return self.scroll or 0 end
function Object:SetVerticalScroll(v) self.scroll = v end
function Object:GetThumbTexture() self.thumb = self.thumb or new("Texture", self); return self.thumb end
function Object:SetValue(v) self.value = v; self:Fire("OnValueChanged", v) end
function Object:GetValue() return self.value end
function Object:Click(mouse) self:Fire("PreClick", mouse or "LeftButton"); self:Fire("OnClick", mouse or "LeftButton") end

_G.CreateFrame = function(kind, _, parent) return new(kind, parent) end
_G.UIParent = new("Frame")
_G.GameTooltip = new("GameTooltip", _G.UIParent)
_G.GetCursorPosition = function() return 300, 300 end
_G.GetTime = function() return 0 end
_G.IsShiftKeyDown = function() return false end
_G.GetCurrentKeyBoardFocus = function() return nil end
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.print = print

-- Runs what the client would run on the next frames.
local function tick()
    for _ = 1, 5 do
        for _, o in ipairs(objects) do
            if o.scripts.OnUpdate and o.kind == "Frame" and o.shown then o.scripts.OnUpdate(o, 0.016) end
        end
    end
end

return { assertTrue = assertTrue, objects = objects, Object = Object, new = new, tick = tick }
