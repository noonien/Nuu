-- The kit as built, loaded from NuuKit.toc, running B's sample screen (the
-- kit has B's API): what B is to a sketch, this is to the real thing.

local M = {}

local ns = {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
        assert(loadfile(file))("NuuKit", ns)
    end
end
local Kit = ns.Kit
local UI = Kit.UI
assert(UI and UI.types.Toggle, "the kit did not load from NuuKit.toc")

local function look(l) return { theme = l.theme, textSize = l.textScale > 1 and "large" or "normal" } end

function M.NewUI(l, opts)
    local ui = Kit.NewUI(ns, look(l))
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

-- Clearing puts every widget back in its pool.
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
