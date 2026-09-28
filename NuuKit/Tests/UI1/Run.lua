-- Smoke tests for UI-Test1, on the same stand-in for the client's frame API
-- as UI/'s (Tests/Support/Frames.lua). From NuuKit/:
--   nix-shell -p lua5_1 --run "lua Tests/UI1/Run.lua"
-- `lua Tests/UI1/Run.lua Base Buttons` runs only those parts.
--
-- Each part is Tests/UI1/Smoke/<Part>.lua, called with a context; it builds
-- what it tests in a window of its own and checks it. Parts whose kit
-- files do not exist yet are skipped.

local frames = dofile("Tests/Support/Frames.lua")
local assertTrue, objects, tick = frames.assertTrue, frames.objects, frames.tick

-- Text measured from its font size (the shared stand-in answers 12 for any):
-- about 6 units a letter and 2 of leading at size 12.
local Object = frames.Object
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 11, "" end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end
-- A font string made from a template (GameFontNormal) has its font.
local createFontString = Object.CreateFontString
function Object:CreateFontString(name, layer, template)
    local text = createFontString(self, name, layer, template)
    if template then text.fontSize = 12 end
    return text
end
-- As the client: no text on a font string before it has a font.
local setText = Object.SetText
function Object:SetText(text)
    if self.kind == "FontString" and not self.fontSize then error("FontString:SetText(): Font not set", 2) end
    return setText(self, text)
end

-- UI-Test1's files, in load order (as in NuuKit.toc).
local FILES = {
    "UI-Test1/Base/Core.lua", "UI-Test1/Base/Draw.lua", "UI-Test1/Base/Layout.lua", "UI-Test1/Base/Scroll.lua",
    "UI-Test1/Base/Focus.lua", "UI-Test1/Base/Drag.lua", "UI-Test1/Base/Tooltip.lua",
    "UI-Test1/Base/Text.lua", "UI-Test1/Controls/Buttons.lua", "UI-Test1/Chrome/Window.lua", "UI-Test1/Chrome/Tabs.lua",
    "UI-Test1/Controls/Fields.lua", "UI-Test1/Controls/Menus.lua", "UI-Test1/Display/Lists.lua",
    "UI-Test1/Display/Feedback.lua", "UI-Test1/Display/Tables.lua", "UI-Test1/Controls/Forms.lua",
    "UI-Test1/Display/Slots.lua", "UI-Test1/Theme/LookPicker.lua",
}

local function exists(path)
    local handle = io.open(path)
    if handle then handle:close() end
    return handle ~= nil
end

-- The kit's own files first (UI-Test1 uses UI/Theme), then UI-Test1's.
local ns = {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^UI%-Test1/") and not file:match("^Dev/") then
        assert(loadfile(file))("NuuKit", ns)
    end
end
-- The parts, and the kit files each needs.
local PARTS = {
    { "Base", { "UI-Test1/Base/Text.lua" } },
    { "Buttons", { "UI-Test1/Controls/Buttons.lua" } },
    { "Chrome", { "UI-Test1/Chrome/Window.lua", "UI-Test1/Chrome/Tabs.lua" } },
    { "Fields", { "UI-Test1/Controls/Fields.lua", "UI-Test1/Controls/Forms.lua" } },
    { "Menus", { "UI-Test1/Controls/Menus.lua" } },
    { "Lists", { "UI-Test1/Display/Lists.lua", "UI-Test1/Display/Tables.lua" } },
    { "Display", { "UI-Test1/Display/Feedback.lua", "UI-Test1/Display/Slots.lua", "UI-Test1/Theme/LookPicker.lua" } },
    { "Pooling", { "UI-Test1/Controls/Buttons.lua" } },
    { "Gallery", { "Dev/Gallery1.lua" } },
    { "Examples", FILES },
    { "Report", { "Dev/Report.lua" } },
}
-- The gallery needs every file too.
for _, part in ipairs(PARTS) do
    if part[1] == "Gallery" or part[1] == "Report" then
        for _, file in ipairs(FILES) do table.insert(part[2], file) end
    end
end

-- Named parts load the core and their own files only; none, everything.
-- `--copy` runs everything with methods copied onto frames: the path a
-- client that refuses frames a metatable takes.
local wanted, copyMode = {}, false
for _, name in ipairs(arg or {}) do
    if name == "--copy" then copyMode = true else wanted[name] = true end
end
local only
if next(wanted) then
    only = {}
    for _, file in ipairs(FILES) do
        if file:match("^UI%-Test1/Base/") or file:match("Text%.lua$") or file:match("Buttons%.lua$") then only[file] = true end
    end
    for _, part in ipairs(PARTS) do
        if wanted[part[1]] then for _, file in ipairs(part[2]) do only[file] = true end end
    end
end
local loaded = {}
for _, file in ipairs(FILES) do
    if exists(file) and (not only or only[file]) then
        assert(loadfile(file))("NuuKit", ns)
        loaded[file] = true
    end
end
for _, dev in ipairs({ "Dev/Gallery1.lua", "Dev/Report.lua" }) do
    if exists(dev) and (not only or only[dev]) then
        assert(loadfile(dev))("NuuKit", ns)
        loaded[dev] = true
    end
end

local Kit = ns.Kit
local UI = Kit.UI1
if copyMode then UI.sharedMethods = false end

-- A window stand-in for parts that run before Chrome/Window.lua exists: a
-- column the size of a window.
local function testWindow(ui, width, height)
    if ui.Window then
        local win = ui:Window({ width = width or 600, height = height or 500 })
        win:Show()
        return win, win.kitInner
    end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(width or 600, height or 500)
    local body = ui:Column(holder, { gap = 8, padding = 10 })
    body:SetAllPoints(holder)
    body.kitFillChildren = true
    return holder, body
end

local function find(test)
    for _, o in ipairs(objects) do if test(o) then return o end end
end

local ctx = {
    Kit = Kit, UI = UI, objects = objects, Object = frames.Object, tick = tick, find = find,
    assertTrue = assertTrue, testWindow = testWindow, loaded = loaded,
    layout = function() UI.LayoutNow(); assertTrue(UI.LayoutSettled(), "the layout settles") end,
}

local ran, skipped = {}, {}
for _, part in ipairs(PARTS) do
    local name, needs = part[1], part[2]
    local ready = exists("Tests/UI1/Smoke/" .. name .. ".lua")
    for _, file in ipairs(needs) do
        if not exists(file) then ready = false end
    end
    if (next(wanted) == nil or wanted[name]) then
        if ready then
            ctx.ui = Kit.NewUI1({ name = "Test" .. name }, nil)
            assert(loadfile("Tests/UI1/Smoke/" .. name .. ".lua"))(ctx)
            ctx.layout()
            ran[#ran + 1] = name
        else
            skipped[#skipped + 1] = name
        end
    end
end
assertTrue(UI.sharedMethods == not copyMode, "methods shared through metatables unless copied on purpose")
print("UI-Test1 smoke tests passed" .. (copyMode and " (methods copied)" or "") .. ": " .. table.concat(ran, ", ")
    .. (#skipped > 0 and ("; not ready: " .. table.concat(skipped, ", ")) or "") .. " (" .. #objects .. " objects)")
