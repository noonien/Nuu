-- Builds every widget against a stand-in for the client's frame API and runs
-- the layouts, look changes and the common interactions. It proves nothing
-- about how things look; it catches calls to missing functions, typos and
-- arithmetic on nil in the frame code, which the pure tests never reach.

local frames = dofile("Tests/Support/Frames.lua")
local objects, tick, assertTrue = frames.objects, frames.tick, frames.assertTrue

local ns = _G.LoadKit("NuuKit")
local Kit = ns.Kit
local UI = Kit.UI

assertTrue(type(SlashCmdList.NUUKIT) == "function", "the gallery registers /nuukit")
SlashCmdList.NUUKIT("ui")
tick()
local g = UI.gallery
assertTrue(g and g.win, "the gallery opens")
UI.LayoutNow()
assertTrue(UI.LayoutSettled(), "the layout settles: laying a container out does not queue it again")

local function find(test)
    for _, o in ipairs(objects) do if test(o) then return o end end
end

-- Shows a gallery tab. The client tells a frame its anchors resized it; the
-- stand-in only tells on SetSize, so a scroll area's content is told here.
local tabs = find(function(o) return o.tabs and o.Select end)
local function show(key)
    tabs.tabs[key]:Click()
    tick()
    for _, o in ipairs(objects) do
        if o.kind == "ScrollFrame" and o:IsVisible() then o:Fire("OnSizeChanged", o:GetWidth(), o:GetHeight()) end
    end
    tick()
end

-- One part of the kit at a time, in this order, on the one gallery.
local ctx = { Kit = Kit, UI = UI, g = g, objects = objects, Object = frames.Object, tick = tick, find = find,
    show = show, tabs = tabs, assertTrue = assertTrue }
for _, part in ipairs({ "Theme", "Chrome", "Base", "Display", "Controls", "Keyboard" }) do
    assert(loadfile("Tests/UI/Smoke/" .. part .. ".lua"))(ctx)
end
g.win:Hide()
tick()
assert(loadfile("Tests/UI/Smoke/Examples.lua"))(ctx)

print("NuuKit UI smoke tests passed (" .. #objects .. " objects)")
