local Kit = _G.LoadKit().Kit
local UI = Kit.UI

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function near(a, b) return math.abs(a - b) < 0.002 end

local function assertColor(color, hex, message)
    local want = UI.Color(hex)
    for index = 1, 3 do
        if not near(color[index], want[index]) then
            error(string.format("%s: expected %s, got %.3f,%.3f,%.3f", message, hex, color[1], color[2], color[3]), 2)
        end
    end
end

-- Colours.
assertColor(UI.Color("#4dc9f0"), "#4dc9f0", "a colour reads from hex")
assertColor(UI.Color("4dc9f0"), "#4dc9f0", "with or without the hash")
assertEquals(UI.Color("nope"), nil, "and anything else is refused")
assertEquals(UI.Color("#4dc9f0", 0.5)[4], 0.5, "an alpha can be given")
assertColor(UI.Mix(UI.Color("#000000"), UI.Color("#ffffff"), 0.5), "#808080", "mixing goes part of the way")
assertEquals(UI.ColorCode(UI.Color("#ffd100")), "|cffffd100", "a colour code for text")

-- Looks.
local look = UI.ResolveLook(nil)
assertEquals(look.theme, "midnight", "no look is the default theme")
assertEquals(look.opacity, 1, "and full opacity")
look = UI.ResolveLook({ theme = "nosuch", opacity = 0.1, textSize = "huge", reduceMotion = 1 })
assertEquals(look.theme, "midnight", "an unknown theme falls back")
assertEquals(look.opacity, 0.4, "opacity is held to 0.4 or more")
assertEquals(look.textSize, "normal", "an unknown text size falls back")
assertEquals(look.reduceMotion, false, "reduceMotion is true or false")
local kept = { theme = "slate", accent = "#6f9dff" }
UI.ResolveLook(kept)
kept.theme = "slate"
assertEquals(UI.ResolveLook(kept) ~= kept, true, "a resolved look is a new table, never the addon's")

-- Tokens.
local t = UI.Tokens({ theme = "midnight" })
assertColor(t.accent, "#4dc9f0", "the accent as text is the accent")
assertColor(t.accentFill, "#1f4856", "its fill is mixed toward the window")
assertEquals(near(t.windowBg[4], 0.97), true, "the window is nearly opaque")
assertEquals(near(t.surfaceBg[4], 0.72), true, "in-play panels show the world through")
assertColor(t.danger, "#e66157", "status colours are the kit's own")

local faded = UI.Tokens({ theme = "midnight", opacity = 0.5 })
assertEquals(near(faded.surfaceBg[4], 0.36), true, "opacity scales the backgrounds")
assertEquals(near(faded.surface[4], 1), true, "but not the opaque planes")

assertEquals(UI.ResolveLook({ theme = "parchment" }).theme, "midnight", "a look kept with the old Parchment falls back")

local theirs = UI.Tokens({ theme = "horde" })
assertColor(theirs.accentRaw, "#e8705a", "no accent in the look is the theme's own")
assertEquals(theirs.art ~= nil, true, "an art theme carries its art")
local chosen = UI.Tokens({ theme = "horde", accent = "#6f9dff" })
assertColor(chosen.accentRaw, "#6f9dff", "an accent in the look wins")
local class = UI.Tokens({ theme = "slate", accent = "class" })
assertColor(class.accentRaw, "#4dc9f0", "the class colour falls back to the theme's outside the client")
assertEquals(UI.TokenColor(t, "muted"), t.muted, "a token by name")
assertColor(UI.TokenColor(t, "#123456"), "#123456", "or any colour")

-- Button colours.
local fill, edge, ink = UI.ButtonColors(t, nil, nil, "rest")
assertEquals(fill, t.surface, "a neutral button rests on the surface")
assertEquals(ink, t.text, "with a caption in the text colour, never muted")
fill, edge, ink = UI.ButtonColors(t, nil, nil, "hover")
assertEquals(edge, t.accent65, "and gains an accent edge on hover")
fill, edge, ink = UI.ButtonColors(t, nil, nil, "active")
assertEquals(ink, t.accent, "the active one of a group wears the accent")
fill, edge, ink = UI.ButtonColors(t, "accent", nil, "rest")
assertColor(fill, "#1f4856", "the call to action is filled")
assertEquals(ink, t.onFill, "with the fill's text")
fill, edge, ink = UI.ButtonColors(t, "danger", "outline", "rest")
assertEquals(fill, nil, "an outline has no fill")
assertColor(edge, "#e66157", "and the tone's edge")
fill, edge, ink = UI.ButtonColors(t, "danger", "ghost", "rest")
assertEquals(edge, nil, "a ghost has no edge either")
fill, edge, ink = UI.ButtonColors(t, "#f48cba", "soft", "rest")
assertEquals(near(fill[4], 0.14), true, "a soft button is a wash of any colour")
fill, edge, ink = UI.ButtonColors(t, "success", nil, "disabled")
assertEquals(near(ink[4], 0.4), true, "a disabled toned button fades its tone")

-- Layout sums.
local placed = UI.Distribute({ { size = 20 }, { grow = 1 }, { size = 30 } }, 100, 5)
assertEquals(placed[2].size, 40, "a growing child takes what is left")
assertEquals(placed[3].offset, 70, "and the next child follows it")
placed = UI.Distribute({ { grow = 1 }, { grow = 3 } }, 100, 0)
assertEquals(placed[1].size, 25, "growth is shared by weight")
assertEquals(placed[2].size, 75, "")
placed = UI.Distribute({ { size = 80 }, { grow = 1, min = 30 } }, 100, 0)
assertEquals(placed[2].size, 30, "a minimum holds a squeezed child open")
assertEquals(UI.AlignStart("right", 100, 40), 60, "right packs to the end")
assertEquals(UI.AlignStart("center", 100, 40), 30, "centre splits the rest")
assertEquals(UI.AlignStart(nil, 100, 40), 0, "left is the default")

-- Money.
assertEquals(Kit.FormatMoney(12005, false, false), "1g 20s", "two coins, rounded")
assertEquals(Kit.FormatMoney(9600, false, false), "96s", "a zero coin is left out")
assertEquals(Kit.FormatMoney(0, false, false), "0c", "nothing is 0c")
assertEquals(Kit.FormatMoney(12005, true, false), "1g 20s 5c", "exact keeps every coin")
assertEquals(Kit.FormatMoney(-150, false, false), "-1s 50c", "a negative amount keeps its sign")
assertEquals(Kit.FormatMoney(150), "1|cffc7c7cfs|r 50|cffeda55fc|r", "coin letters are always coloured")
assertEquals(Kit.FormatMoney(150, false, t), Kit.FormatMoney(150), "passing tokens changes nothing")
assertEquals(Kit.ParseMoney(Kit.FormatMoney(12005, true)), 12005, "coloured money parses back")
assertEquals(string.find(Kit.MoneyHint(), "1|cffffd100g|r 20|cffc7c7cfs|r 5|cffeda55fc|r", 1, true) ~= nil, true, "the hint's example is coloured too")
assertEquals(Kit.ParseMoney("1g 20s 5c"), 12005, "money parses")
assertEquals(Kit.ParseMoney("1g20s"), 12000, "without spaces")
assertEquals(Kit.ParseMoney("250"), 250, "a bare number is copper")
assertEquals(Kit.ParseMoney("32x"), nil, "a typo is refused")
assertEquals(Kit.ParseMoney("1g 1g"), nil, "and so is a coin twice")

-- Key hints.
assertEquals(UI.ShortKey("SHIFT-BUTTON4"), "sM4", "a key hint is cut to fit a corner")
assertEquals(UI.ShortKey("CTRL-5"), "c5", "")
assertEquals(UI.ShortKey(""), nil, "no key, no hint")

-- Themes.
assertEquals(UI.themeOrder[1], "midnight", "the themes keep their order")
UI.AddTheme("test", { window = "#000000", band = "#000000", hairline = "#000000", surface = "#000000",
    raised = "#000000", border = "#000000", text = "#ffffff", muted = "#888888" })
assertEquals(UI.themeOrder[#UI.themeOrder], "test", "an added theme goes last")
assertColor(UI.Tokens({ theme = "test" }).accentRaw, "#4dc9f0", "a theme without an accent gets the kit's")

print("NuuKit UI theme tests passed")
