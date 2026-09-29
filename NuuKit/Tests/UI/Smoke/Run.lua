-- Smoke tests for the UI kit, on a stand-in for the client's frame API
-- (Tests/Support/Frames.lua). From NuuKit/:
--   nix-shell -p lua5_1 --run "lua Tests/UI/Smoke/Run.lua"
-- `lua Tests/UI/Smoke/Run.lua Base Buttons` runs only those parts;
-- `--copy` runs them with methods copied onto frames.
--
-- Each part is Tests/UI/Smoke/<Part>.lua, called with a context; it builds
-- what it tests in a window of its own and checks it.

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
-- SetToDefaults as build 70009 showed it (/nuukit report, 2026-09-28): it
-- puts back alpha, scale, strata, level, shown, size, anchors, enabled,
-- text, attributes, scripts and hooks, and turns the mouse off; it keeps
-- the parent, the wheel, events, regions, children and Lua fields. A font
-- string loses its font too.
function Object:SetToDefaults()
    self.alpha, self.strata = 1, nil
    self.level = (self.parent and self.parent.level or 0) + 1
    self.shown, self.enabled = true, true
    self.width, self.height, self.points = 0, 0, {}
    self.scripts, self.hooks = {}, {}
    self.mouse, self.attributes = false, nil
    self.text = nil
    if self.kind == "FontString" then self.fontSize = nil end
end
function Object:EnableMouse(on) self.mouse = on and true or false end
function Object:IsMouseEnabled() return self.mouse ~= false end
-- As the client: no text on a font string before it has a font.
local setText = Object.SetText
function Object:SetText(text)
    if self.kind == "FontString" and not self.fontSize then error("FontString:SetText(): Font not set", 2) end
    return setText(self, text)
end

-- The kit as the client loads it: every file in NuuKit.toc but the
-- development global, galleries and report included.
local ns, loaded = {}, {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" then
        assert(loadfile(file))("NuuKit", ns)
        loaded[file] = true
    end
end

local PARTS = { "Base", "Buttons", "Chrome", "Fields", "Menus", "Lists", "Display", "Screens", "Pooling", "Reset", "Gallery", "Examples", "Report" }

-- Named parts run alone; none, all of them. `--copy` runs with methods
-- copied onto frames: the path a client that refuses frames a metatable
-- takes.
local wanted, copyMode = {}, false
for _, name in ipairs(arg or {}) do
    if name == "--copy" then copyMode = true else wanted[name] = true end
end

local Kit = ns.Kit
local UI = Kit.UI
if copyMode then UI.sharedMethods = false end

-- A window of its own for a part, and the body to build in.
local function testWindow(ui, width, height)
    local win = ui:Window({ width = width or 600, height = height or 500 })
    win:Show()
    return win, win.kitInner
end

local function find(test)
    for _, o in ipairs(objects) do if test(o) then return o end end
end

local ctx = {
    Kit = Kit, UI = UI, objects = objects, Object = frames.Object, tick = tick, find = find,
    assertTrue = assertTrue, testWindow = testWindow, loaded = loaded,
    layout = function() UI.LayoutNow(); assertTrue(UI.LayoutSettled(), "the layout settles") end,
}

local ran = {}
for _, name in ipairs(PARTS) do
    if next(wanted) == nil or wanted[name] then
        ctx.ui = Kit.NewUI({ name = "Test" .. name }, nil)
        assert(loadfile("Tests/UI/Smoke/" .. name .. ".lua"))(ctx)
        ctx.layout()
        ran[#ran + 1] = name
    end
end
assertTrue(UI.sharedMethods == not copyMode, "methods shared through metatables unless copied on purpose")
print("NuuKit UI smoke tests passed" .. (copyMode and " (methods copied)" or "") .. ": " .. table.concat(ran, ", ")
    .. " (" .. #objects .. " objects)")
