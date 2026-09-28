local addonName, ns = ...

local Kit = ns.Kit

-- Development only, never shipped: `/nuukit report` (or the report button on
-- the gallery's Pooling tab) runs in the client what the UI kit needs
-- measured there, and shows the result as text to copy.
--
-- It reports the client and its scale; how the kit gives widgets their
-- methods; the client features docs/api-compatibility.md lists; and the
-- benchmark of Tests/Bench, with the client's own costs: a
-- screen of 60 rows (name, count, "+1") and three toggles, built, hovered,
-- clicked, repainted, resized and rebuilt. It runs one step a frame so the
-- game does not stall, and catches every error with its stack.

local ROWS, KEYS = 60, { "sellBack", "showMap", "autoLoot" }

local lines = {}
local function add(text) lines[#lines + 1] = text end
local function addf(fmt, ...) add(string.format(fmt, ...)) end

local function now()
    if type(debugprofilestop) == "function" then return debugprofilestop() end
    return (GetTime and GetTime() or 0) * 1000
end

local function addonMemory()
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if type(update) ~= "function" or type(get) ~= "function" then return nil end
    collectgarbage("collect")
    update()
    return get(addonName)
end

-- Frames made while `fn` runs, heard through a secure hook on CreateFrame
-- (replacing the global would taint it for the game's own code).
local made, counting = 0, false
local hooked = false
local function counted(fn)
    if not hooked and type(hooksecurefunc) == "function" then
        hooksecurefunc("CreateFrame", function() if counting then made = made + 1 end end)
        hooked = true
    end
    made, counting = 0, true
    local ok, err = xpcall(fn, debugstack or debug.traceback)
    counting = false
    if not ok then error(err, 0) end
    return hooked and made or nil
end

local function fire(frame, script)
    if type(ExecuteFrameScript) == "function" then
        ExecuteFrameScript(frame, script)
        return
    end
    local handler = frame:GetScript(script)
    if handler then handler(frame) end
end

-- The best of `rounds` runs of `fn(count)`, per run of `count`.
local function best(rounds, count, fn)
    local fastest
    for _ = 1, rounds do
        local t0 = now()
        fn(count)
        local took = (now() - t0) / count
        if not fastest or took < fastest then fastest = took end
    end
    return fastest
end

local function newItems()
    local items = {}
    for i = 1, ROWS do items[i] = { name = "Item " .. i, count = 8 + (i % 3) } end
    return items
end

-- The kit, driven as the bench drives it ----------------------------------------------

-- The bench's screen.
local function screen(ui, win, db, items, plus)
    local body = win:Column{ gap = 6, padding = 10 }
    local head = body:Row{ gap = 8 }
    head:Text{ "Settings", style = "title" }
    head:Spacer{}
    local toggles, counts = {}, {}
    head:Button{ "Reset", onClick = function()
        for _, toggle in ipairs(toggles) do toggle:Reset() end
        for i, item in ipairs(items) do item.count = 0; counts[i]:SetText(0) end
    end }
    for _, key in ipairs(KEYS) do toggles[#toggles + 1] = body:Toggle{ key, bind = { db, key } } end
    for i, item in ipairs(items) do
        local row = body:Row{ gap = 8 }
        row:Text{ item.name, grow = true }
        counts[i] = row:Text{ item.count, style = "number" }
        plus[i] = row:Button{ "+1", onClick = function() item.count = item.count + 1; counts[i]:SetText(item.count) end }
    end
end

-- Each kit measured gets a column: the kit, and any variant being compared
-- with it (a copy with one part changed).
local KITS = {
    {
        name = "UI",
        make = function(look) return Kit.NewUI({ name = "NuuKitReport" }, look) end,
        flush = function() Kit.UI.LayoutNow() end,
        -- What the client's size event would do a frame later.
        resized = function(win) Kit.UI.Invalidate(win.kitInner) end,
        screen = screen,
    },
}

-- A window off to the side, see-through, for one kit's runs.
local function newWindow(kit, ui)
    local win = ui:Window({ width = 420, height = 1900, point = { "TOPLEFT", UIParent, "TOPRIGHT", 40, 0 } })
    win:SetClampedToScreen(false)
    win:SetAlpha(0)
    win:Show()
    return win
end

-- The steps --------------------------------------------------------------------------

local steps = {}
local function step(label, fn) steps[#steps + 1] = { label = label, fn = fn } end

step("client", function()
    add("NuuKit UI report")
    local version, build, date, toc = "?", "?", "?", "?"
    if type(GetBuildInfo) == "function" then version, build, date, toc = GetBuildInfo() end
    addf("client %s build %s (%s), interface %s", tostring(version), tostring(build), tostring(date), tostring(toc))
    local width, height = 0, 0
    if type(GetPhysicalScreenSize) == "function" then width, height = GetPhysicalScreenSize() end
    addf("screen %dx%d, UIParent scale %.3f, pixels per unit %.4f", width or 0, height or 0,
        UIParent:GetEffectiveScale(), Kit.UI and Kit.UI.PixelsPerUnit() or 0)
end)

step("features", function()
    add("")
    add("Client features")
    local frame = CreateFrame("Frame", nil, UIParent)
    local function yes(value) return value and "yes" or "NO" end
    addf("  Line objects (glyphs): %s", yes(frame.CreateLine ~= nil))
    addf("  SetClipsChildren: %s", yes(frame.SetClipsChildren ~= nil))
    local group = frame.CreateAnimationGroup and frame:CreateAnimationGroup()
    local translation = group and pcall(group.CreateAnimation, group, "Translation")
    addf("  Translation animations: %s", yes(translation))
    addf("  SetPropagateKeyboardInput: %s", yes(frame.SetPropagateKeyboardInput ~= nil))
    local text = frame:CreateFontString(nil, "OVERLAY")
    addf("  GetUnboundedStringWidth: %s", yes(text.GetUnboundedStringWidth ~= nil))
    addf("  ExecuteFrameScript: %s", yes(type(ExecuteFrameScript) == "function"))
    local texture = frame:CreateTexture()
    local art = {}
    for _, file in ipairs({ "horde\\bg", "horde\\frame", "alliance\\bg", "alliance\\plate" }) do
        art[#art + 1] = file .. " " .. yes(Kit.UI.LoadTexture(texture, Kit.UI.MediaPath(file)))
    end
    addf("  TGA art loads: %s", table.concat(art, ", "))
    local tiled = Kit.UI.Tile(texture, "horde\\bg")
    addf("  tiling (SetHorizTile): %s", yes(tiled and texture.SetHorizTile ~= nil))
    frame:Hide()
end)

-- One kit's scenarios, as a chain of steps.
local results = {}
for index, kit in ipairs(KITS) do
    local run = {}
    results[index] = run
    step(kit.name .. ": build", function()
        local look = { theme = "midnight" }
        -- Timed builds, each a new UI and window.
        local total = 0
        for _ = 1, 3 do
            local ui = kit.make(look)
            local t0 = now()
            local win = newWindow(kit, ui)
            kit.screen(ui, win, {}, newItems(), {})
            kit.flush()
            total = total + now() - t0
            win:Hide()
        end
        run.build = total / 3
        -- Two more, kept, for memory (the lower of the two); the last one
        -- for the runs that follow.
        for _ = 1, 2 do
            local before = addonMemory()
            local ui = kit.make(look)
            local win = newWindow(kit, ui)
            run.ui, run.win, run.db, run.items, run.plus = ui, win, {}, newItems(), {}
            run.frames = counted(function()
                kit.screen(ui, win, run.db, run.items, run.plus)
                kit.flush()
            end)
            local after = addonMemory()
            local kept = before and after and (after - before) or nil
            if kept and (not run.kept or kept < run.kept) then run.kept = kept end
        end
    end)
    step(kit.name .. ": hover", function()
        local plus = run.plus
        run.hover = best(3, 600, function(count)
            for i = 1, count do
                local button = plus[(i % #plus) + 1]
                fire(button, "OnEnter")
                fire(button, "OnLeave")
            end
        end) * 1000
    end)
    step(kit.name .. ": click", function()
        local plus = run.plus
        run.click = best(3, 60, function(count)
            for i = 1, count do
                plus[(i % #plus) + 1]:Click()
                kit.flush()
            end
        end)
    end)
    step(kit.name .. ": look", function()
        run.look = best(3, 4, function(count)
            for i = 1, count do
                run.ui:SetLook({ theme = i % 2 == 0 and "midnight" or "slate", textSize = i % 4 == 1 and "large" or "normal" })
                kit.flush()
            end
        end)
        run.ui:SetLook({ theme = "midnight" })
        kit.flush()
    end)
    step(kit.name .. ": resize", function()
        run.resize = best(3, 10, function(count)
            for i = 1, count do
                run.win:SetWidth(i % 2 == 0 and 420 or 470)
                kit.resized(run.win)
                kit.flush()
            end
        end)
    end)
    step(kit.name .. ": rebuild", function()
        local before = addonMemory()
        local t0 = now()
        run.rebuildFrames = counted(function()
            for _ = 1, 10 do
                run.win:Clear()
                run.plus = {}
                kit.screen(run.ui, run.win, run.db, run.items, run.plus)
                kit.flush()
            end
        end)
        run.rebuildFrames = run.rebuildFrames and run.rebuildFrames / 10
        run.rebuild = (now() - t0) / 10
        local after = addonMemory()
        run.rebuildKept = before and after and (after - before) / 10 or nil
        run.win:Hide()
    end)
end

step("results", function()
    add("")
    -- Known once the benchmark has made widgets.
    local shared = Kit.UI and Kit.UI.sharedMethods
    addf("Kit methods: %s", shared == true and "shared through metatables"
        or (shared == false and "COPIED onto frames (the client refused a metatable)" or "not decided (no widget made)"))
    add("")
    addf("Benchmark: %d rows, the client's own costs (ms = milliseconds, us = microseconds)", ROWS)
    local function row(label, fmt, get)
        local cells = {}
        for index, kit in ipairs(KITS) do
            local value = get(results[index])
            cells[#cells + 1] = string.format("%16s", value ~= nil and string.format(fmt, value) or "n/a")
        end
        add(string.format("  %-30s", label) .. table.concat(cells, ""))
    end
    local header = {}
    for _, kit in ipairs(KITS) do header[#header + 1] = string.format("%16s", kit.name) end
    add(string.format("  %-30s", "") .. table.concat(header, ""))
    row("build, ms", "%.1f", function(r) return r.build end)
    row("build, frames made", "%d", function(r) return r.frames end)
    row("build, memory kept KB", "%.0f", function(r) return r.kept end)
    row("hover enter+leave, us", "%.1f", function(r) return r.hover end)
    row("click +1 and layout, ms", "%.3f", function(r) return r.click end)
    row("look change and layout, ms", "%.1f", function(r) return r.look end)
    row("resize and layout, ms", "%.2f", function(r) return r.resize end)
    row("clear and rebuild, ms", "%.1f", function(r) return r.rebuild end)
    row("rebuild, frames made", "%.0f", function(r) return r.rebuildFrames end)
    row("rebuild, memory kept KB", "%.0f", function(r) return r.rebuildKept end)
end)

-- Whole pixels: every shown widget of the open gallery.
step("pixels", function()
    add("")
    local gallery = Kit.UI and Kit.UI.gallery
    if not (gallery and gallery.ui and gallery.win and gallery.win:IsShown()) then
        add("Pixels: open /nuukit ui first to check the gallery's edges.")
        return
    end
    local scale = Kit.UI.PixelsPerUnit()
    local checked, off, example = 0, 0, nil
    local function fraction(value)
        local pixels = value * scale
        return math.abs(pixels - math.floor(pixels + 0.5))
    end
    local function whole(value) return fraction(value) < 0.02 end
    local win = gallery.win
    local winLeft, winTop = win:GetLeft() or 0, win:GetTop() or 0
    addf("Pixels: the gallery window's top left is %.3f, %.3f px off the grid", fraction(winLeft), fraction(winTop))
    local inside = 0
    for w in pairs(gallery.ui.widgets) do
        if not w.kitPooled and w.IsVisible and w:IsVisible() and w.GetLeft then
            local left, top, width, height = w:GetLeft(), w:GetTop(), w:GetWidth(), w:GetHeight()
            if left and top then
                checked = checked + 1
                if whole(left - winLeft) and whole(top - winTop) and whole(width) and whole(height) then inside = inside + 1 end
                if not (whole(left) and whole(top) and whole(width) and whole(height)) then
                    off = off + 1
                    example = example or string.format("%s at %.3f, %.3f size %.3f x %.3f", tostring(w.kitType or w.kitClass), left, top, width, height)
                end
            end
        end
    end
    addf("Pixels: %d of %d shown gallery widgets on whole screen pixels%s", checked - off, checked,
        example and (". First off the grid: " .. example) or "")
    addf("Pixels: %d of %d on whole pixels relative to the window (the layout's own snapping)", inside, checked)
end)

-- Running and showing --------------------------------------------------------------------

local box

local function show(text)
    Kit.lastReport = text
    if not box then
        local frame = CreateFrame("Frame", "NuuKitReportFrame", UIParent)
        frame:SetSize(760, 520)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.06, 0.08, 0.96)
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("NuuKit report: Ctrl+C copies the selected text")
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -34)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(700)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        scroll:SetScrollChild(edit)
        frame.edit = edit
        if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "NuuKitReportFrame") end
        box = frame
    end
    box.edit:SetText(text)
    box:Show()
    box.edit:SetFocus()
    box.edit:HighlightText()
end

local running = false

local function run()
    if running then return end
    running = true
    lines = {}
    local index = 0
    local function nextStep()
        index = index + 1
        local current = steps[index]
        if not current then
            running = false
            show(table.concat(lines, "\n"))
            print("|cff4cc9f0NuuKit|r: report ready. Ctrl+C in the window copies it.")
            return
        end
        show(table.concat(lines, "\n") .. "\n\nRunning: " .. current.label .. "...")
        local ok, err = xpcall(current.fn, debugstack or debug.traceback)
        if not ok then
            add("")
            addf("ERROR in %s: %s", current.label, tostring(err))
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.05, nextStep) else nextStep() end
    end
    nextStep()
end
Kit.RunReport = run

-- `/nuukit report`; anything else goes to the handlers before this one.
if type(SlashCmdList) == "table" then
    local before = SlashCmdList.NUUKIT
    SLASH_NUUKIT1 = SLASH_NUUKIT1 or "/nuukit"
    SlashCmdList.NUUKIT = function(message)
        if (message or ""):lower():match("^%s*report") then
            run()
        elseif before then
            before(message)
        end
    end
end
