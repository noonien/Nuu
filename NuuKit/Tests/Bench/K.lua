-- K: the real kit, loaded from NuuKit.toc, running A's sample screen (A is
-- written in the kit's own API). It checks that A is a fair stand-in for
-- the kit; the kit does more per widget (art plates, focus, tooltips, press
-- nudges), so it is expected to cost more than A.

local C = dofile(BENCH .. "Common.lua")
local M = {}

local ns = {}
for line in io.lines("NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and not file:match("^Dev/") then
        assert(loadfile(file))("NuuKit", ns)
    end
end
local Kit, UI = ns.Kit, ns.Kit.UI

local function look(l) return { theme = l.theme, textSize = l.textScale > 1 and "large" or "normal" } end

function M.NewUI(l)
    local ui = Kit.NewUI(ns, look(l))
    ui.track = {}
    return ui
end
function M.SetLook(ui, l) ui:SetLook(look(l)) end
function M.Window(ui, width, height) return ui:Window({ width = width, height = height }) end
function M.Flush() UI.LayoutNow() end
function M.Clear(ui, win) win:Clear() end

local screen = dofile(BENCH .. "A.lua").Screen
function M.Screen(ui, win, db, items)
    local body = screen(ui, win, db, items)
    -- The buttons (not toggles), for the hover and click runs.
    local function walk(frame)
        for _, child in ipairs(frame.kitChildren or {}) do
            if child:GetObjectType() == "Button" and rawget(child, "kitChecked") == nil and child.label then
                ui.track[#ui.track + 1] = child
            end
            walk(child)
        end
    end
    walk(body)
    return body
end

return M
