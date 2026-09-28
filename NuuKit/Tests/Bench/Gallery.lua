-- The whole UI-Test1 gallery on the smoke tests' stand-in, counting calls
-- into the client's API: a guard for work on every widget, where the bench
-- screen covers only text, buttons, toggles and stacks. From NuuKit/:
--   nix-shell -p lua5_1 --run "lua Tests/Bench/Gallery.lua"
-- Calls are exact; compare them before and after a change.

local frames = dofile("Tests/Support/Frames.lua")
local Object, objects = frames.Object, frames.objects

-- Text measured from its font size, as Tests/UI1/Run.lua does.
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end

-- Every stand-in method counts as a client call.
local calls, byName = 0, {}
for name, fn in pairs(Object) do
    if type(fn) == "function" and name ~= "__index" and name ~= "Fire" then
        Object[name] = function(...)
            calls = calls + 1
            byName[name] = (byName[name] or 0) + 1
            return fn(...)
        end
    end
end
local index = Object.__index
Object.__index = function(self, key)
    local value = index(self, key)
    if type(value) == "function" and not rawget(Object, key) and type(key) == "string" and key:match("^[A-Z]") then
        return function(...) calls = calls + 1; byName[key] = (byName[key] or 0) + 1; return value(...) end
    end
    return value
end

local ns = {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" then assert(loadfile(file))("NuuKit", ns) end
end
local Kit = ns.Kit
local UI = Kit.UI1

local results = {}
local function measure(label, fn)
    collectgarbage("collect")
    calls, byName = 0, {}
    local before, objectsBefore = collectgarbage("count"), #objects
    collectgarbage("stop")
    local t0 = os.clock()
    fn()
    local took = os.clock() - t0
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    collectgarbage("collect")
    local kept = collectgarbage("count") - before
    results[#results + 1] = string.format("%-28s %8d calls %8.1f ms %8.0f KB allocated %8.0f KB kept %6d objects",
        label, calls, took * 1000, allocated, kept, #objects - objectsBefore)
end

local g
measure("open the gallery", function()
    SlashCmdList.NUUKIT("ui1")
    UI.LayoutNow()
    g = UI.gallery
end)
measure("visit every tab", function()
    for _, key in ipairs({ "look", "controls", "lists", "tables", "inplay", "pooling", "controls" }) do
        g.tabs:SetValue(key)
        UI.LayoutNow()
    end
end)
measure("look changes (4)", function()
    for _, look in ipairs({ { theme = "slate" }, { theme = "horde", textSize = "large" }, { theme = "alliance" }, {} }) do
        g.ui:SetLook(look)
        UI.LayoutNow()
    end
end)
-- Again: every theme has been seen, so nothing is made now.
measure("look changes again (4)", function()
    for _, look in ipairs({ { theme = "slate" }, { theme = "horde", textSize = "large" }, { theme = "alliance" }, {} }) do
        g.ui:SetLook(look)
        UI.LayoutNow()
    end
end)
local buttons = {}
for w in pairs(g.ui.widgets) do
    if w.kitType == "Button" and not w.kitPooled then buttons[#buttons + 1] = w end
end
measure("hover every button", function()
    for _, b in ipairs(buttons) do
        b:GetScript("OnEnter")(b)
        b:GetScript("OnLeave")(b)
    end
end)
local rebuild
for _, b in ipairs(buttons) do if b:GetText() == "Rebuild" then rebuild = b end end
measure("pooling rebuilds (5)", function()
    for _ = 1, 5 do rebuild:Click() end
    UI.LayoutNow()
end)
measure("resize the window (4)", function()
    for _, width in ipairs({ 950, 900, 1000, 900 }) do
        g.win:SetWidth(width)
        UI.Invalidate(g.win.kitInner)
        UI.LayoutNow()
    end
end)
for _, line in ipairs(results) do print(line) end
