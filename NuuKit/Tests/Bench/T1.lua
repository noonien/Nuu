-- T1: the real UI-Test1, loaded from NuuKit.toc's kit files (UI/ for the
-- look code it shares, then UI-Test1/), running B's sample screen: UI-Test1
-- has B's API. What B is to a sketch, T1 is to the kit as built.

local M = {}

local ns = {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
        assert(loadfile(file))("NuuKit", ns)
    end
end
local Kit = ns.Kit
local UI = Kit.UI1
assert(UI and UI.types.Toggle, "UI-Test1 is not in NuuKit.toc yet, or has no Toggle")

local function look(l) return { theme = l.theme, textSize = l.textScale > 1 and "large" or "normal" } end

function M.NewUI(l, opts)
    local ui = Kit.NewUI1(ns, look(l))
    ui.track = {}
    ui.pool = not (opts and opts.pool == false)
    return ui
end
function M.SetLook(ui, l) ui:SetLook(look(l)) end
function M.Flush() UI.LayoutNow() end

-- A window's body stand-in, as B's: a column of fixed size.
function M.Window(ui, width, height)
    local frame = CreateFrame("Frame", nil, UIParent)
    local win = ui:Column(frame, { gap = 0 })
    win:SetSize(width, height)
    return win
end

-- Clearing puts every widget back in its pool (UI-Test1 always pools).
function M.Clear(ui, win) win:Clear() end

local screen = dofile(BENCH .. "B.lua").Screen
function M.Screen(ui, win, db, items)
    local body = screen(ui, win, db, items)
    -- The buttons (not toggles), for the hover and click runs.
    for _, row in ipairs(body.kitChildren) do
        for _, child in ipairs(row.kitChildren or {}) do
            if child.kitType == "Button" then ui.track[#ui.track + 1] = child end
        end
    end
    return body
end

return M
