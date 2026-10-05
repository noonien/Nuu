local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI
local types = UI.types

-- Columns and rows: stacks that place what is made in them.
--
-- A child's layout options are in its spec: `grow` (a weight, or true for
-- 1) takes a share of the spare room along the stack, `width` and `height`
-- fix a size, `minWidth` / `minHeight` hold a growing child open. Across a
-- column, children stretch to its width unless their type does not
-- (buttons, toggles) or they give a width or `stretch = false`; `align`
-- places those ("left", "center", "right"). Across a row, children are
-- centred, or `valign` ("top", "bottom", "stretch") on the row or the child;
-- the row's `align` packs it when nothing grows.
--
-- A stack's own spec: `gap` between children and `padding` round them;
-- `padLeft` and `padRight` give one side a padding of its own.
--
-- What changes a size calls w:Changed(). On the next frame (or at
-- UI.LayoutNow) the pass measures again, deepest first, only what changed,
-- and goes up only while a size really changes; then it lays out, top down,
-- only the stacks whose children moved, and places a child only where its
-- edges moved. Natural sizes are kept between passes.

-- The sums, apart from any frame -------------------------------------------------

-- Hands out `available` along a stack: `sizes[i]` for a fixed child, or
-- `grows[i]` (a weight) with `mins[i]` for a growing one. Fills `offsets`
-- and `out` (the size of each); tables are passed in so a pass reuses them.
local function distribute(count, sizes, grows, mins, available, gap, offsets, out)
    local fixed, weights = 0, 0
    for i = 1, count do
        if grows[i] then weights = weights + grows[i] else fixed = fixed + sizes[i] end
    end
    local spare = math.max(0, available - fixed - gap * math.max(0, count - 1))
    local offset = 0
    for i = 1, count do
        local size = sizes[i]
        if grows[i] then size = math.max(mins[i] or 0, weights > 0 and spare * grows[i] / weights or 0) end
        offsets[i], out[i] = offset, size
        offset = offset + size + gap
    end
end
UI.Distribute = distribute

-- Where a run of `total` starts in `available` for an alignment.
function UI.AlignStart(align, available, total)
    if align == "center" then return math.max(0, (available - total) / 2) end
    if align == "right" or align == "bottom" then return math.max(0, available - total) end
    return 0
end

-- In combat the client refuses to move or size a protected frame: a secure
-- button, or a frame holding one (a strip of secure slots). Such a frame is
-- left as it is and held; when combat ends, what was held is laid out again.
local held, schedule = {}, nil
local function hold(w, how)
    if held[w] ~= "fit" then held[w] = how end
    schedule()
end
local function locked(frame)
    return type(InCombatLockdown) == "function" and InCombatLockdown()
        and frame.IsProtected ~= nil and frame:IsProtected() and true or false
end

-- Puts `child` at x, y (down from `parent`'s top left) sized w by h, on
-- whole screen pixels, skipping what did not move. Answers whether its size
-- changed.
local function place(parent, child, x, y, w, h)
    local left, top = UI.Snap(parent, x), UI.Snap(parent, y)
    local width = math.max(0.01, UI.Snap(parent, x + w) - left)
    local height = math.max(0.01, UI.Snap(parent, y + h) - top)
    if locked(child) then
        hold(parent, true)
        return false
    end
    if child.kitPX ~= left or child.kitPY ~= top then
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
        child.kitPX, child.kitPY = left, top
    end
    if child.kitPW ~= width or child.kitPH ~= height then
        child:SetSize(width, height)
        child.kitPW, child.kitPH = width, height
        return true
    end
    return false
end

-- The pass ---------------------------------------------------------------------------

-- What changed since the last pass: widget -> its natural width and height
-- before the first change (false when never measured). And the stacks to
-- lay out.
local oldW, oldH, layouts = {}, {}, {}
local driver

function schedule()
    if driver then
        driver:Show()
    elseif type(CreateFrame) == "function" then
        driver = UI.NewFrame("Frame")
        driver:SetScript("OnUpdate", function() UI.LayoutNow() end)
        pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")
        driver:SetScript("OnEvent", function()
            for w, how in pairs(held) do
                held[w] = nil
                if how == "fit" then
                    UI.Fit(w)
                    if w.StackLayout and w.StackLayout ~= UI.Stack.StackLayout then layouts[w] = true end
                elseif how == "self" then
                    if not w.kitPooled then layouts[w] = true end
                elseif not w.kitPooled then
                    layouts[w.kitInner or w] = true
                end
            end
            schedule()
        end)
    end
end

function UI.Changed(w)
    if oldW[w] == nil then
        oldW[w] = w.kitNatW or false
        oldH[w] = w.kitNatH or false
    end
    w.kitNatW, w.kitNatH = nil, nil
    schedule()
end

-- Lays `stack` out on the next pass, whether or not its size changed.
function UI.Invalidate(stack)
    layouts[stack.kitInner or stack] = true
    schedule()
end

local function depthOf(w) return w.kitDepth or 0 end

-- The pass's own lists, emptied after each use rather than made again.
local levels, seen, list, done = {}, {}, {}, {}

local function addToLevel(w, d)
    local level = levels[d]
    if not level then
        level = {}
        levels[d] = level
    end
    level[#level + 1] = w
end

-- Measures what changed, deepest first; a widget whose size changed makes
-- its parent measure again and lay out.
local function measure()
    local deepest, lowest = 0, math.huge
    for w in pairs(oldW) do
        local d = depthOf(w)
        addToLevel(w, d)
        if d > deepest then deepest = d end
        if d < lowest then lowest = d end
    end
    local d = deepest
    while d >= lowest do
        local level = levels[d]
        local index = 1
        while level and level[index] do
            local w = level[index]
            level[index] = nil
            index = index + 1
            -- A stack nothing lays out (a window's body) has no size to
            -- report: it is laid out, not measured.
            if not seen[w] and (w.kitParent or w.kitFree) then
                seen[w] = true
                local width = w:NaturalWidth()
                local height = w:NaturalHeight(w.kitPW or width)
                local parent = w.kitParent
                if parent and (width ~= oldW[w] or height ~= oldH[w]) then
                    -- A column stretches its children: only a new height
                    -- (or the width of one it does not stretch) moves them.
                    if height ~= oldH[w] or parent.kitAxis ~= "column"
                        or w.kitStretch == false or w.kitLayout.width then
                        layouts[parent] = true
                    end
                    if oldW[parent] == nil then
                        oldW[parent] = parent.kitNatW or false
                        oldH[parent] = parent.kitNatH or false
                        local pd = depthOf(parent)
                        if pd >= d then pd = d - 1 end
                        if pd < lowest then lowest = pd end
                        addToLevel(parent, pd)
                    end
                    -- Measured since its own change (a caller fitting it at
                    -- once), its size no longer holds either way.
                    parent.kitNatW, parent.kitNatH = nil, nil
                elseif not parent and w.kitFree and (width ~= oldW[w] or height ~= oldH[w]) then
                    UI.Fit(w)
                end
            end
        end
        d = d - 1
    end
    for w in pairs(oldW) do oldW[w], oldH[w] = nil, nil end
    for w in pairs(seen) do seen[w] = nil end
end

-- Lays out now: for code that needs sizes before the next frame. Each round
-- lays out the stacks waiting, shallowest first; a stack resized there
-- lays out at once, so one round usually does. Whether a child is shown is
-- asked of the client once per pass.
local byDepth = function(a, b) return depthOf(a) < depthOf(b) end
function UI.LayoutNow()
    if next(oldW) == nil and next(layouts) == nil then return end
    UI.passShown = UI.passShown or {}
    for _ = 1, 100 do
        if next(oldW) == nil and next(layouts) == nil then break end
        measure()
        for stack in pairs(layouts) do list[#list + 1] = stack end
        for stack in pairs(layouts) do layouts[stack] = nil end
        table.sort(list, byDepth)
        for index = 1, #list do
            local stack = list[index]
            list[index] = nil
            -- A holder's class has a stack's layout but no children of its
            -- own; a type's own StackLayout (a strip's) always runs.
            local layout = stack.StackLayout
            if layout and (stack.kitChildren or layout ~= UI.Stack.StackLayout)
                and not done[stack] and not stack.kitPooled then
                -- A type's own layout sizes its parts directly: a protected
                -- one (a strip of secure slots) waits for combat to end.
                if layout ~= UI.Stack.StackLayout and locked(stack) then
                    hold(stack, "self")
                else
                    stack:StackLayout()
                end
            end
        end
        for stack in pairs(done) do done[stack] = nil end
    end
    for child in pairs(UI.passShown) do UI.passShown[child] = nil end
    UI.passShown = nil
    if driver and next(oldW) == nil and next(layouts) == nil then driver:Hide() end
end

-- Whether nothing is waiting to be laid out.
function UI.LayoutSettled()
    return next(oldW) == nil and next(layouts) == nil
end

-- Sizes a widget the caller placed to its natural size.
function UI.Fit(w)
    local width = w:NaturalWidth()
    local height = w:NaturalHeight(width)
    width, height = UI.Snap(w, width), UI.Snap(w, height)
    if w.kitPW ~= width or w.kitPH ~= height then
        if locked(w) then hold(w, "fit"); return end
        w:SetSize(math.max(0.01, width), math.max(0.01, height))
        w.kitPW, w.kitPH = width, height
        if w.Sized then w:Sized(width, height) end
        if w.kitChildren or w.kitInner then UI.Invalidate(w) end
    end
end

-- After a change of pixel scale: every place is worked out again.
function UI.PlacedAgain()
    for ui in pairs(UI.uis) do
        for w in pairs(ui.widgets) do
            if not w.kitPooled then
                w.kitPX, w.kitPY, w.kitPW, w.kitPH = nil, nil, nil, nil
                if w.kitChildren then layouts[w] = true end
            end
        end
    end
    schedule()
end

-- Stacks ------------------------------------------------------------------------------

UI.Stack = UI.Stack or {}
local Stack = UI.Stack
local Holder = UI.Holder

local function stretches(child)
    return child.kitStretch ~= false and not child.kitLayout.width
end

-- Whether a child is shown, asked of the client once per pass: a pass asks
-- about every child of a stack several times (measuring, laying out).
local function shown(child)
    local cache = UI.passShown
    if not cache then return child:IsShown() end
    local value = cache[child]
    if value == nil then
        value = child:IsShown() and true or false
        cache[child] = value
    end
    return value
end

-- A child shown or hidden changes its stack. Font strings have no scripts;
-- the Text type tells from its own Show and Hide.
function UI.ChildToggled(child)
    if UI.passShown then UI.passShown[child] = nil end
    local parent = child.kitParent
    if parent then
        layouts[parent] = true
        UI.Changed(parent)
    end
end
local childToggled = UI.ChildToggled

-- Its depth and window, and those of the parts it was built with (a
-- section's heading and body): usually a few frames, as a widget is placed
-- before anything is made in it.
local function settle(w, depth, window)
    w.kitDepth, w.kitWindow = depth, window
    local children = w.kitChildren
    if children then
        for index = 1, #children do settle(children[index], depth + 1, window) end
    end
    local inner = w.kitInner
    if inner and inner ~= w and inner.kitDepth ~= depth + 1 then settle(inner, depth + 1, window) end
end

function Stack:Append(child)
    local children = self.kitChildren
    children[#children + 1] = child
    child.kitParent = self
    settle(child, (self.kitDepth or 0) + 1, self.kitWindow)
    -- A window, pane or page fills with what fills.
    if not child.kitGrow and self.kitFillChildren and child.kitLayout.grow == nil then
        local def = types[child.kitType]
        local fills = def and def.fills
        if type(fills) == "function" then fills = fills(child.kitLayout) end
        if fills then child.kitGrow = 1 end
    end
    -- A widget tells from its own Show and Hide; a plain frame through its
    -- scripts.
    if child.HookScript and not child.kitShowHooked and not child.kitRawShow then
        child.kitShowHooked = true
        child:HookScript("OnShow", childToggled)
        child:HookScript("OnHide", childToggled)
    end
    layouts[self] = true
    UI.Changed(self)
    return child
end

-- Takes a child out and back to its pool.
function Stack:Remove(child)
    local inner = self.kitInner or self
    local children = inner.kitChildren
    for index = 1, #children do
        if children[index] == child then
            table.remove(children, index)
            child.kitParent = nil
            UI.Release(child)
            layouts[inner] = true
            UI.Changed(inner)
            return
        end
    end
end

-- Every child back to its pool.
function Stack:ReleaseChildren()
    local children = self.kitChildren
    for index = #children, 1, -1 do
        local child = children[index]
        children[index] = nil
        child.kitParent = nil
        if child.kitType then UI.Release(child) else child:Hide() end
    end
end

function Stack:Clear()
    local inner = self.kitInner or self
    inner:ReleaseChildren()
    layouts[inner] = true
    UI.Changed(inner)
end

function Stack:GetChildren() return (self.kitInner or self).kitChildren end
function Stack:Relayout() UI.Invalidate(self) end

-- Lays the children out in the order of `list`: the stack's own children,
-- each once. Those it leaves out follow, in the order they had.
function Stack:Order(list)
    local inner = self.kitInner or self
    local children, listed, ordered = inner.kitChildren, {}, {}
    for _, child in ipairs(list) do
        if child.kitParent == inner and not listed[child] then
            listed[child] = true
            ordered[#ordered + 1] = child
        end
    end
    for _, child in ipairs(children) do
        if not listed[child] then ordered[#ordered + 1] = child end
    end
    local same = true
    for index = 1, #children do
        if children[index] ~= ordered[index] then same = false end
        children[index] = ordered[index]
    end
    if same then return end
    layouts[inner] = true
    UI.Changed(inner)
end

-- A widget holding a stack answers for it.
Holder.Clear = Stack.Clear
Holder.Remove = Stack.Remove
Holder.Relayout = Stack.Relayout
Holder.GetChildren = Stack.GetChildren
Holder.Order = Stack.Order

-- The least width: the narrowest a widget can be laid out with nothing in it
-- cut or pushed past its edge, what a window's least size is made from
-- (Chrome/Window.lua). Worked out when asked, from the natural widths the
-- pass keeps. A row needs each fixed child at its natural width and each
-- growing one at its minWidth (more, if it holds a stack that needs more:
-- a growing leaf, as text, is cut short instead); a column needs what its
-- widest child needs. A type with a need of its own answers LeastWidth.
local function holds(w) return w.kitChildren ~= nil or (w.kitInner ~= nil and w.kitInner ~= w) end

local function leastOf(child)
    return child.kitLayout.width or (child.LeastWidth and child:LeastWidth()) or child:NaturalWidth()
end

function UI.Widget:LeastWidth()
    local fixed = self.kitLayout.width
    if fixed then return fixed end
    local children, axis = self.kitChildren, self.kitAxis
    if children and axis then
        local p = self.kitPadding or 0
        local need, count = (self.kitPadLeft or p) + (self.kitPadRight or p), 0
        local widest = 0
        for index = 1, #children do
            local child = children[index]
            if child:IsShown() then
                count = count + 1
                if axis == "column" then
                    widest = math.max(widest, leastOf(child))
                elseif child.kitGrow then
                    local least = child.kitLayout.minWidth or 0
                    if holds(child) then least = math.max(least, leastOf(child)) end
                    need = need + least
                else
                    need = need + math.max(child:NaturalWidth(), leastOf(child))
                end
            end
        end
        if axis == "row" then return need + math.max(0, count - 1) * self.kitGap end
        return need + widest
    end
    local inner = self.kitInner
    if inner and inner ~= self then
        return math.max(0, self:NaturalWidth() - inner:NaturalWidth()) + inner:LeastWidth()
    end
    return self:NaturalWidth()
end

-- The room a state message takes.
local function statePad(self, height)
    if self.kitState then return math.max(height, self.kitStateHeight or 90) end
    return height
end

-- Column sums.
local function columnMeasure(self, width)
    local p, gap = self.kitPadding, self.kitGap
    local sides = (self.kitPadLeft or p) + (self.kitPadRight or p)
    local inner = (width or 0) - sides
    local tall, wide, count = 0, 0, 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            local natural = child:NaturalWidth()
            if natural > wide then wide = natural end
            if child.kitGrow then
                tall = tall + (child.kitLayout.minHeight or 0)
            else
                local cw = natural
                if width then cw = stretches(child) and inner or math.min(inner, natural) end
                tall = tall + child:NaturalHeight(cw)
            end
            count = count + 1
        end
    end
    return wide + sides, statePad(self, tall + 2 * p + math.max(0, count - 1) * gap)
end

-- Row sums.
local function rowMeasure(self)
    local p, gap = self.kitPadding, self.kitGap
    local long, tall, count = 0, 0, 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            local natural = child:NaturalWidth()
            long = long + (child.kitGrow and (child.kitLayout.minWidth or 0) or natural)
            local height = child:NaturalHeight(natural)
            if height > tall then tall = height end
            count = count + 1
        end
    end
    long = long + (self.kitPadLeft or p) + (self.kitPadRight or p) + math.max(0, count - 1) * gap
    return long, statePad(self, tall + 2 * p)
end

function Stack:Measure(width)
    if self.kitAxis == "row" then return rowMeasure(self) end
    return columnMeasure(self, width)
end

-- A layout can start inside another (a size event, a Sized hook laying out
-- a stack of its own), so each level of nesting has its own lists.
local scratch, nest = {}, 0
local function scratchLists()
    local lists = scratch[nest]
    if not lists then
        lists = { {}, {}, {}, {}, {}, {}, {} }
        scratch[nest] = lists
    end
    return lists[1], lists[2], lists[3], lists[4], lists[5], lists[6], lists[7]
end

-- A child the layout resized: told, and its own stack laid out at once (a
-- layout inside another has lists of its own).
local function layChild(child, resized)
    if not resized then return end
    if child.Sized then child:Sized(child.kitPW, child.kitPH) end
    if child.kitChildren and child.StackLayout and not child.kitPooled then
        layouts[child] = nil
        child:StackLayout()
    end
    local inner = child.kitInner
    if inner and inner ~= child and not done[inner] then layouts[inner] = true end
end

local function columnLayout(self, width, height)
    local kids, sizes, grows, mins, offsets, out, widths = scratchLists()
    if self.kitAutoHeight then
        local _, natural = self:Measure(width)
        if math.abs(height - natural) > 0.5 and locked(self) then
            hold(self, true)
        elseif math.abs(height - natural) > 0.5 then
            height = UI.Snap(self, natural)
            self:SetHeight(height)
            self.kitPH = height
        end
    end
    local p, gap = self.kitPadding, self.kitGap
    local padLeft = self.kitPadLeft or p
    local inner = width - padLeft - (self.kitPadRight or p)
    local count = 0
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            count = count + 1
            kids[count] = child
            local cw = stretches(child) and inner or math.min(inner, child:NaturalWidth())
            out[count] = cw
            if child.kitGrow then
                grows[count], mins[count], sizes[count] = child.kitGrow, child.kitLayout.minHeight or 0, 0
            else
                grows[count], mins[count], sizes[count] = nil, nil, child:NaturalHeight(cw)
            end
        end
    end
    for i = 1, count do widths[i] = out[i] end
    distribute(count, sizes, grows, mins, height - 2 * p, gap, offsets, out)
    for i = 1, count do
        local child = kids[i]
        local x = padLeft
        if not stretches(child) then
            x = padLeft + UI.AlignStart(child.kitLayout.align or self.kitAlign, inner, widths[i])
        end
        layChild(child, place(self, child, x, p + offsets[i], widths[i], out[i]))
        kids[i] = nil
    end
end

local VALIGN = { top = "left", bottom = "bottom" }

local function rowLayout(self, width, height)
    local kids, sizes, grows, mins, offsets, out = scratchLists()
    local p, gap = self.kitPadding, self.kitGap
    local innerHeight = height - 2 * p
    local count, anyGrow = 0, false
    for _, child in ipairs(self.kitChildren) do
        if shown(child) then
            count = count + 1
            kids[count] = child
            if child.kitGrow then
                anyGrow = true
                grows[count], mins[count], sizes[count] = child.kitGrow, child.kitLayout.minWidth or 0, 0
            else
                grows[count], mins[count], sizes[count] = nil, nil, child:NaturalWidth()
            end
        end
    end
    local padLeft, padRight = self.kitPadLeft or p, self.kitPadRight or p
    local innerWidth = width - padLeft - padRight
    distribute(count, sizes, grows, mins, innerWidth, gap, offsets, out)
    local start = 0
    if not anyGrow and count > 0 then
        start = UI.AlignStart(self.kitAlign, innerWidth, offsets[count] + out[count])
    end
    for i = 1, count do
        local child = kids[i]
        local def = child.kitType and types[child.kitType]
        local valign = child.kitLayout.valign or (def and def.valign) or self.kitValign
        local h
        if child.kitLayout.height then
            h = child.kitLayout.height
        elseif valign == "stretch" then
            h = innerHeight
        else
            h = math.min(innerHeight, child:NaturalHeight(out[i]))
        end
        local y = p + UI.AlignStart(VALIGN[valign] or (valign == "stretch" and "left") or "center", innerHeight, h)
        layChild(child, place(self, child, padLeft + start + offsets[i], y, out[i], h))
        kids[i] = nil
    end
end

function Stack:StackLayout()
    if UI.passShown then done[self] = true end
    local width = self.kitPW or self:GetWidth() or 0
    local height = self.kitPH or self:GetHeight() or 0
    if width <= 0 then return end
    nest = nest + 1
    local ok, err = pcall(self.kitAxis == "row" and rowLayout or columnLayout, self, width, height)
    nest = nest - 1
    if not ok then error(err, 0) end
end

-- A stack sized by its anchors (a window body, a scroll area's content)
-- lays out when they size it; one its parent sizes, when the parent does.
local function stackSized(self, width, height)
    if self.kitPW == nil or math.abs((self.kitPW or 0) - (width or 0)) > 0.001 or math.abs((self.kitPH or 0) - (height or 0)) > 0.001 then
        if self.kitParent == nil then
            layouts[self] = true
            schedule()
        end
    end
end

-- Makes `frame` a stack of `axis` ("column" or "row") for `ui`: for widgets
-- that build a stack of their own (a section's body, a window's).
function UI.MakeStack(ui, frame, axis, opts)
    opts = opts or {}
    if frame.StackLayout ~= Stack.StackLayout then
        if frame.kitType then
            -- A widget whose class has no stack's methods: they go on it.
            for key, fn in pairs(Stack) do frame[key] = fn end
            for key, fn in pairs(UI.Makers) do frame[key] = fn end
        else
            -- A plain frame becomes a stack, as a class of its own.
            UI.Adopt(frame, "Stack", { UI.Widget, Stack, UI.Makers })
        end
    end
    frame.ui = ui
    frame.kitLayout = frame.kitLayout or opts
    frame.kitWraps = true
    -- Known to its UI, so a change of pixel scale lays it out again.
    ui.widgets[frame] = true
    UI.SetStack(frame, axis, opts)
    if frame.HookScript and not frame.kitSizeHooked then
        frame.kitSizeHooked = true
        frame:HookScript("OnSizeChanged", stackSized)
    end
    return frame
end

-- A stack a widget builds itself from (a section's heading and body, a
-- setting's name column): a plain frame made a stack, with its layout
-- options. The caller appends it where it goes.
function UI.Part(ui, parent, axis, opts, layout)
    local frame = UI.NewFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeStack(ui, frame, axis, opts)
    frame.kitLayout = layout or {}
    return frame
end

-- Sets a stack's own options (a pooled stack gets them again).
function UI.SetStack(frame, axis, opts)
    frame.kitAxis = axis
    frame.kitChildren = frame.kitChildren or {}
    frame.kitGap = opts.gap or (axis == "row" and 6 or 8)
    frame.kitPadding = opts.padding or 0
    frame.kitAlign = opts.align
    frame.kitValign = opts.valign
    frame.kitPadLeft = opts.padLeft
    frame.kitPadRight = opts.padRight
    frame.kitState = nil
end

local function stackType(axis)
    return {
        stack = true, fit = false, fills = axis == "column",
        Build = function(w)
            w:SetSize(1, 1)
            w:SetScript("OnSizeChanged", stackSized)
            w.kitSizeHooked = true
        end,
        Init = function(w, spec)
            UI.SetStack(w, axis, spec)
            w.kitFillChildren = nil
            if spec.width or spec.height then w:SetSize(spec.width or 1, spec.height or 1) end
        end,
        Release = function(w)
            if w.kitStateFrame then w:SetState(nil) end
        end,
    }
end
UI.Define("Column", stackType("column"))
UI.Define("Row", stackType("row"))

-- Room that grows, or a fixed gap with `size`.
UI.Define("Spacer", {
    grow = function(spec) return not spec.size end,
    Init = function(w, spec) w.kitSize = spec.size or 0 end,
    methods = {
        Measure = function(self) return self.kitSize, self.kitSize end,
    },
})

-- A hairline: across a column, or along a row taking the spare room.
UI.Define("Rule", {
    grow = function(spec, parent) return parent and parent.kitAxis == "row" or nil end,
    Build = function(w)
        w.line = w:CreateTexture(nil, "ARTWORK")
        w.line:SetPoint("LEFT")
        w.line:SetPoint("RIGHT")
        UI.Hairline(w.line, "height")
    end,
    Init = function(w, spec) w.kitColor = spec.color end,
    methods = {
        Measure = function() return 1, 1 end,
        Paint = function(self, t) UI.TexColor(self.line, UI.Colour(t, self.kitColor) or t.hairline) end,
    },
})

-- States: loading, empty, error -------------------------------------------------------------

-- Puts a stack's content aside for a message: "loading" (with a moving
-- ellipsis), "empty", or "error" (in the danger colour). `opts.tone` is a
-- colour token for the message instead ("warning"). `opts.action` is
-- { caption, onClick } for a button under the message; `opts.height` the
-- room it takes. `SetState(nil)` brings the content back.
local function stateTick(overlay, elapsed)
    if overlay.kind ~= "loading" then return end
    overlay.clock = (overlay.clock or 0) + elapsed
    local dots = math.floor(overlay.clock * 2) % 4
    if dots ~= overlay.dots then
        overlay.dots = dots
        overlay.message:SetText(overlay.text .. string.rep(".", dots))
    end
end

local function paintState(overlay, t)
    UI.ApplyStyle(overlay.message, "body", t,
        overlay.tone or (overlay.kind == "error" and "danger" or (overlay.kind == "empty" and "text" or "muted")))
end

function Stack:SetState(kind, text, opts)
    local inner = self.kitInner or self
    local ui = inner.ui
    if not kind then
        if inner.kitState then
            inner.kitState = nil
            for child in pairs(inner.kitStateHidden or {}) do child:Show() end
            inner.kitStateHidden = nil
            if inner.kitStateFrame then inner.kitStateFrame:Hide() end
            layouts[inner] = true
            UI.Changed(inner)
        end
        return
    end
    opts = opts or {}
    local overlay = inner.kitStateFrame
    if not overlay then
        overlay = UI.NewFrame("Frame", nil, inner)
        overlay:SetAllPoints(inner)
        overlay:SetFrameLevel(inner:GetFrameLevel() + 5)
        overlay.message = UI.NewText(overlay)
        if overlay.message.SetWordWrap then overlay.message:SetWordWrap(true) end
        overlay.message:SetJustifyH("CENTER")
        overlay.message:SetPoint("LEFT", overlay, "LEFT", 16, 8)
        overlay.message:SetPoint("RIGHT", overlay, "RIGHT", -16, 8)
        overlay:SetScript("OnUpdate", stateTick)
        ui:Paint(overlay, function(t) paintState(overlay, t) end)
        inner.kitStateFrame = overlay
    end
    overlay.kind, overlay.text, overlay.clock, overlay.dots = kind, text or "", 0, 0
    overlay.tone = opts.tone
    overlay.message:SetText(overlay.text)
    if opts.action then
        if not overlay.action then
            overlay.action = ui:Button(overlay, { opts.action.caption or "" })
            overlay.action:SetPoint("TOP", overlay.message, "BOTTOM", 0, -10)
        end
        overlay.action:SetText(opts.action.caption or "")
        overlay.action:SetOnClick(opts.action.onClick)
        overlay.action:Show()
    elseif overlay.action then
        overlay.action:Hide()
    end
    paintState(overlay, ui.tokens)
    if not inner.kitState then
        inner.kitStateHidden = {}
        for _, child in ipairs(inner.kitChildren) do
            if child:IsShown() then
                inner.kitStateHidden[child] = true
                child:Hide()
            end
        end
    end
    inner.kitState = kind
    inner.kitStateHeight = opts.height
    overlay:Show()
    layouts[inner] = true
    UI.Changed(inner)
end

function Stack:GetState()
    return (self.kitInner or self).kitState
end

Holder.SetState = Stack.SetState
Holder.GetState = Stack.GetState
