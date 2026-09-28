-- D: declarative. The addon writes `render()`, which returns the whole screen
-- as nested spec tables from its own data; `view:Update()` renders it again
-- on the next flush and the kit reconciles the new tree against the last one
-- (by position): same kind, it sets what changed on the existing widget;
-- another kind, it releases the old widget and makes a new one. No widget
-- handles are kept by the addon. Built on B's widgets, with pooling.

local C = dofile(BENCH .. "Common.lua")
local M = dofile(BENCH .. "B.lua")
local make, release = M.make, M.release

local newUI = M.NewUI
function M.NewUI(look, opts)
    local ui = newUI(look, { pool = true })
    ui.views = {}
    return ui
end

-- A spec is { kind, caption?, key = value..., childSpec... }: for a stack,
-- every table in the array part after the kind is a child.
local function create(ui, parent, spec)
    local w = make(ui, spec[1], parent, {
        spec[2], grow = spec.grow, style = spec.style, tone = spec.tone, onClick = spec.onClick,
        value = spec.value, onChange = spec.onChange, gap = spec.gap, padding = spec.padding,
    })
    parent:Append(w)
    return w
end

local reconcile

local function reconcileChildren(ui, w, spec, old)
    local at = 0
    for index = 2, #spec do
        local child = spec[index]
        if type(child) == "table" then
            at = at + 1
            local node = w.children[at]
            if node and node.kitType == child[1] then
                reconcile(ui, node, child, node.kitSpec)
            else
                if node then
                    -- Another kind in this place: out with the old one and
                    -- everything after it, which is made again in order.
                    for i = #w.children, at, -1 do
                        release(ui, w.children[i])
                        w.children[i] = nil
                    end
                end
                local made = create(ui, w, child)
                made.kitSpec = child
                if made.children then reconcileChildren(ui, made, child, nil) end
            end
        end
    end
    for i = #w.children, at + 1, -1 do
        release(ui, w.children[i])
        w.children[i] = nil
        ui.layouts[w] = true
        ui.dirty[w] = true
    end
end

-- Sets on `w` what differs between the new spec and the one it was made or
-- last updated from.
function reconcile(ui, w, spec, old)
    if old then
        if spec[2] ~= old[2] and type(spec[2]) ~= "table" and w.SetText then w:SetText(spec[2]) end
        if spec.value ~= old.value and w.SetValue then w:SetValue(spec.value) end
        if spec.tone ~= old.tone and w.SetTone then w:SetTone(spec.tone) end
        w.onClick, w.onChange = spec.onClick, spec.onChange
    end
    w.kitSpec = spec
    if w.children then reconcileChildren(ui, w, spec, old) end
end

-- Mounts `render` in `parent`; the view renders again after Update.
function M.Mount(ui, parent, render)
    local view = { render = render }
    function view.Update() ui.views[view] = true end
    local spec = render()
    view.root = create(ui, parent, spec)
    reconcile(ui, view.root, spec, nil)
    return view
end

local flush = M.Flush
function M.Flush(ui)
    for view in pairs(ui.views) do
        ui.views[view] = nil
        local spec = view.render()
        reconcile(ui, view.root, spec, view.root.kitSpec)
    end
    flush(ui)
end

-- The sample screen: a render function over the addon's data.
-- screen:begin
function M.Screen(ui, win, db, items)
    local view
    local function render()
        local body = { "Column", gap = 6, padding = 10,
            { "Row", gap = 8,
                { "Text", "Settings", style = "title" },
                { "Spacer" },
                { "Button", "Reset", onClick = function()
                    for _, key in ipairs(C.KEYS) do db[key] = nil end
                    for _, item in ipairs(items) do item.count = 0 end
                    view.Update()
                end },
            },
        }
        for _, key in ipairs(C.KEYS) do
            body[#body + 1] = { "Toggle", key, value = db[key] or false, onChange = function(on)
                db[key] = on
                view.Update()
            end }
        end
        for _, item in ipairs(items) do
            body[#body + 1] = { "Row", gap = 8,
                { "Text", item.name, grow = true },
                { "Text", item.count, style = "number" },
                { "Button", "+1", onClick = function()
                    item.count = item.count + 1
                    view.Update()
                end },
            }
        end
        return body
    end
    view = M.Mount(ui, win, render)
    return view.root
end
-- screen:end

return M
