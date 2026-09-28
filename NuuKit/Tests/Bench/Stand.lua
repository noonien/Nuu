-- A light stand-in for the client's frame API that counts every call into it.
-- In the client those calls cross into C and cost far more than a Lua table
-- lookup, so the count is the best predictor of in-game cost the bench has.
-- The stand-in's own frame state sits at frame[1], in the table's array part,
-- so the hash part holds only what the kit puts there (and the client's [0]),
-- as in the client, which keeps frame state in C. Stand.StateBytes() measures
-- that state, to take it off the totals. Every frame is kept alive in a
-- list made at full size up front (the client never frees a frame), so no
-- table of the stand-in grows during a measurement.

local Stand = { calls = 0, byName = {}, objects = 0 }

local function count(name)
    Stand.calls = Stand.calls + 1
    Stand.byName[name] = (Stand.byName[name] or 0) + 1
end

function Stand.Reset()
    Stand.calls, Stand.byName = 0, {}
end

local Object = {}
local noops = {}
-- Kit-side names the stand-in must not answer for (the kit checks for them).
local KIT = { Repaint = true }
local meta = {
    __index = function(self, key)
        local method = Object[key]
        if method then return method end
        if type(key) == "string" and key:match("^[A-Z]") and not KIT[key] and not key:match("^Kit") then
            local noop = noops[key]
            if not noop then
                noop = function() count(key) end
                noops[key] = noop
            end
            return noop
        end
        return nil
    end,
}

local all, allCount = {}, 0
for i = 1, 700000 do all[i] = false end

local function new(kind, parent)
    Stand.objects = Stand.objects + 1
    local o = setmetatable({ { _kind = kind, _parent = parent, _w = 0, _h = 0 }, [0] = false }, meta)
    o[1].self = o
    allCount = allCount + 1
    all[allCount] = o
    if Stand.recording then table.insert(Stand.recording, o) end
    return o
end

-- The bytes the side table holds for `objects` (recorded while
-- Stand.recording was a list): emptied and collected, so those frames are
-- not usable afterwards.
function Stand.StateBytes(objects)
    collectgarbage("collect")
    collectgarbage("collect")
    local before = collectgarbage("count")
    local empty = {}
    for _, o in ipairs(objects) do rawset(o, 1, empty) end
    collectgarbage("collect")
    collectgarbage("collect")
    return (before - collectgarbage("count")) * 1024
end

function Stand.Fire(object, script, ...)
    local st = rawget(object, 1)
    local scripts = st._scripts
    local fn = scripts and scripts[script]
    if fn then fn(object, ...) end
    local hooks = st._hooks
    local list = hooks and hooks[script]
    if list then for _, hook in ipairs(list) do hook(object, ...) end end
end
local function fire(st, script, ...) Stand.Fire(st.self, script, ...) end

-- `fn(st, ...)` gets the frame's state; `self` (the frame) is st.self.
local function def(name, fn)
    Object[name] = function(self, ...)
        count(name)
        return fn(rawget(self, 1), ...)
    end
end

def("GetObjectType", function(s) return s._kind end)
def("GetParent", function(s) return s._parent end)
def("SetParent", function(s, p) s._parent = p end)
def("CreateTexture", function(s) return new("Texture", s.self) end)
def("CreateFontString", function(s) return new("FontString", s.self) end)
def("CreateLine", function(s) return new("Line", s.self) end)
def("SetWidth", function(s, w)
    if w ~= s._w then s._w = w; fire(s, "OnSizeChanged", s._w, s._h) end
end)
def("SetHeight", function(s, h)
    if h ~= s._h then s._h = h; fire(s, "OnSizeChanged", s._w, s._h) end
end)
def("SetSize", function(s, w, h)
    if w ~= s._w or h ~= s._h then s._w, s._h = w, h; fire(s, "OnSizeChanged", w, h) end
end)
def("GetWidth", function(s) return s._w end)
def("GetHeight", function(s) return s._h end)
def("GetSize", function(s) return s._w, s._h end)
def("Show", function(s)
    if s._hidden then s._hidden = nil; fire(s, "OnShow") end
end)
def("Hide", function(s)
    if not s._hidden then s._hidden = true; fire(s, "OnHide") end
end)
def("SetShown", function(s, on)
    if on then s.self:Show() else s.self:Hide() end
end)
def("IsShown", function(s) return not s._hidden end)
def("IsVisible", function(s)
    local o = s
    while o do
        if o._hidden then return false end
        o = o._parent and rawget(o._parent, 1)
    end
    return true
end)
def("SetScript", function(s, name, fn)
    local scripts = s._scripts or {}
    s._scripts = scripts
    scripts[name] = fn
end)
def("GetScript", function(s, name)
    local scripts = s._scripts
    return scripts and scripts[name]
end)
def("HookScript", function(s, name, fn)
    local hooks = s._hooks or {}
    s._hooks = hooks
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], fn)
end)
def("SetText", function(s, text) s._text = text end)
def("GetText", function(s) return s._text end)
def("SetFont", function(s, file, size) s._size = size; return true end)
def("GetFont", function(s) return "Fonts\\FRIZQT__.TTF", s._size or 12, "" end)
-- About 6 units a letter at size 12.
def("GetStringWidth", function(s) return #tostring(s._text or "") * 6 * (s._size or 12) / 12 end)
def("GetUnboundedStringWidth", function(s) return #tostring(s._text or "") * 6 * (s._size or 12) / 12 end)
def("GetStringHeight", function(s) return (s._size or 12) + 2 end)
def("IsEnabled", function(s) return not s._disabled end)
def("Enable", function(s) s._disabled = nil end)
def("Disable", function(s) s._disabled = true end)
def("GetEffectiveScale", function() return 1 end)
def("GetNumPoints", function() return 0 end)
def("GetFrameLevel", function() return 1 end)
def("GetLeft", function() return 0 end)
def("GetTop", function() return 0 end)
def("IsMouseOver", function() return false end)
def("GetTexture", function() return "tex" end)

-- Globals the architectures (and the real kit) touch.
function CreateFrame(kind, name, parent)
    count("CreateFrame")
    return new(kind or "Frame", parent)
end
function GetPhysicalScreenSize()
    count("GetPhysicalScreenSize")
    return 1920, 1080
end
function GetTime()
    count("GetTime")
    return 0
end
UIParent = new("Frame")
GameFontNormal = new("Font")
NumberFontNormal = new("Font")
UISpecialFrames = {}
SlashCmdList = {}
Stand.objects = 0

return Stand
