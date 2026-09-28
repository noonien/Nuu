local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Moves or sizes `frame` while `handle` is held: each frame the frame is put
-- where it was when the button went down plus how far the cursor has gone
-- since, so no motion is lost and the point grabbed stays under the cursor.
-- `mode`: "move", "size" (the right and bottom edges) or "width". `opts`:
-- can(frame) false refuses a drag, bounds { minW, minH, maxW, maxH },
-- onStop(frame) when let go.

local function cursor(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale() or 1
    return x / scale, y / scale
end

local function clamp(value, low, high)
    if low and value < low then value = low end
    if high and value > high then value = high end
    return value
end

local function stop(driver)
    if not driver.kitFrom then return end
    driver.kitFrom = nil
    driver:Hide()
    local opts = driver.kitOpts
    if opts.onStop then opts.onStop(driver.kitFrame) end
end

local function follow(driver)
    local from, frame = driver.kitFrom, driver.kitFrame
    if not from then driver:Hide(); return end
    -- The release may land off the handle, which then never hears it.
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then stop(driver); return end
    local x, y = cursor(frame)
    local dx, dy = x - from.x, y - from.y
    if driver.kitMode == "move" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(frame, from.left + dx), UI.Snap(frame, from.top + dy))
    else
        local b = driver.kitOpts.bounds or {}
        frame:SetWidth(UI.Snap(frame, clamp(from.w + dx, b.minW, b.maxW)))
        if driver.kitMode == "size" then frame:SetHeight(UI.Snap(frame, clamp(from.h - dy, b.minH, b.maxH))) end
    end
end

local function grab(handle, button)
    local driver = handle.kitDragDriver
    if button ~= "LeftButton" or type(GetCursorPosition) ~= "function" then return end
    local opts, frame = driver.kitOpts, driver.kitFrame
    if opts.can and not opts.can(frame) then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local x, y = cursor(frame)
    driver.kitFrom = { x = x, y = y, left = left, top = top, w = frame:GetWidth(), h = frame:GetHeight() }
    -- Held by its top-left corner, so sizing grows it right and down.
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", UI.Snap(frame, left), UI.Snap(frame, top))
    driver:Show()
end

local function letGo(handle, button)
    if button == "LeftButton" then stop(handle.kitDragDriver) end
end

local function hidden(handle) stop(handle.kitDragDriver) end

function UI.DragFrame(handle, frame, mode, opts)
    local driver = UI.NewFrame("Frame", nil, handle)
    driver:Hide()
    driver.kitFrame, driver.kitMode, driver.kitOpts = frame, mode, opts or {}
    driver:SetScript("OnUpdate", follow)
    handle.kitDragDriver = driver
    handle:HookScript("OnMouseDown", grab)
    handle:HookScript("OnMouseUp", letGo)
    handle:HookScript("OnHide", hidden)
    return driver
end
