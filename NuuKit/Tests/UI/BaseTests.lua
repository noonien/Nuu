local Kit = _G.LoadKit().Kit
local UI = Kit.UI

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function near(a, b) return math.abs(a - b) < 0.002 end

-- Every constructor is on the UI and on every container.
for _, name in ipairs({ "Column", "Row", "Spacer", "Rule", "Text", "Section", "Tag", "Notice", "Button",
    "ConfirmButton", "Link", "ResetButton", "GlyphButton", "Tabs", "Disclosure", "Input", "Search", "TextArea",
    "MoneyInput", "NumberInput", "Toggle", "Slider", "Select", "SearchSelect", "MultiSelect", "ScrollArea",
    "List", "Tree", "SplitPanes", "ProgressBar", "Slot", "LookPicker", "Table", "Pager", "Figures", "Card",
    "Setting", "Choices", "SegmentBar" }) do
    assertEquals(type(UI.Proto[name]), "function", "UI:" .. name)
    assertEquals(type(UI.Container[name]), "function", "container:" .. name)
end
for _, name in ipairs({ "Window", "Panel", "StripPanel", "OpenMenu", "CloseMenu", "Tooltip", "HideTooltip",
    "SetLook", "GetLook", "Paint", "TabChain" }) do
    assertEquals(type(UI.Proto[name]), "function", "UI:" .. name)
end

-- A UI keeps its own look, and repaints what it made.
local ui = Kit.NewUI({ name = "Test" }, { theme = "slate" })
assertEquals(ui:GetLook().theme, "slate", "a UI starts in the addon's look")
local painted = {}
local object = {}
ui:Paint(object, function(tokens) painted[#painted + 1] = tokens.look.theme end)
assertEquals(painted[1], "slate", "a painter runs at once")
local told
ui:OnLook(function(l) told = l.theme end)
ui:SetLook({ theme = "obsidian" })
assertEquals(painted[2], "obsidian", "and again after a look change")
assertEquals(told, "obsidian", "and listeners hear of it")
local other = Kit.NewUI({ name = "Other" }, nil)
assertEquals(other:GetLook().theme, "midnight", "another UI keeps its own look")

-- A TextArea's height is its box's, not the widget's: kept out of its layout.
local given = { label = "Notes", height = 80, grow = true }
local layout = UI.LayoutOptions(given, "height")
assertEquals(layout.height, nil, "the inner size is left out")
assertEquals(layout.grow, true, "the other layout options are kept")
assertEquals(given.height, 80, "the widget's own options are untouched")

-- Places snap to whole screen pixels at any UI scale.
local scaled = { GetEffectiveScale = function() return 0.64 end }
local snapped = UI.Snap(scaled, 10.3)
assertEquals(math.abs(snapped * 0.64 - math.floor(snapped * 0.64 + 0.5)) < 1e-9, true, "a snapped value is whole pixels")
assertEquals(math.abs(snapped - 10.3) <= 0.5 / 0.64, true, "and the nearest of them")
assertEquals(UI.Snap(nil, 4.4), 4, "without a frame, whole units")

-- Hairlines are one screen pixel and strokes whole pixels, at any scale, and
-- stay so when the scale changes.
local screenScale = 1.67
local function texture()
    local tex = {}
    function tex:GetEffectiveScale() return screenScale end
    function tex:SetHeight(h) self.height = h end
    function tex:SetWidth(w) self.width = w end
    return tex
end
local hair, stroke = texture(), texture()
UI.Hairline(hair, "height")
UI.Stroke(stroke, "width", 2)
assertEquals(near(hair.height * screenScale, 1), true, "a hairline is one pixel")
assertEquals(near(stroke.width * screenScale, 3), true, "2 units at 1.67 is 3 whole pixels")
screenScale = 0.64
UI.PixelScaleChanged()
assertEquals(near(hair.height * screenScale, 1), true, "still one pixel after the scale changes")
assertEquals(near(stroke.width * screenScale, 1), true, "and a stroke never goes under one")
-- A screen pixel is the effective scale times the physical height over the
-- 768 units the screen always is: 1440p at a UI scale of 0.89 is 1.67.
screenScale = 0.8889
_G.GetPhysicalScreenSize = function() return 2560, 1440 end
local perUnit = UI.PixelsPerUnit(hair)
assertEquals(math.abs(perUnit - 1.6667) < 0.001, true, "pixels per unit use the physical screen: " .. perUnit)
UI.PixelScaleChanged()
assertEquals(math.abs(hair.height * perUnit - 1) < 1e-6, true, "a hairline is one physical pixel")
local onGrid = UI.Snap(hair, 55)
assertEquals(math.abs(onGrid * perUnit - math.floor(onGrid * perUnit + 0.5)) < 1e-6, true, "and a place is whole physical pixels")
_G.GetPhysicalScreenSize = nil
screenScale = 0.64
local told = 0
UI.OnPixelScale(hair, function() told = told + 1 end)
UI.PixelScaleChanged()
assertEquals(told, 1, "a scale change is passed on")

print("NuuKit UI base tests passed")
