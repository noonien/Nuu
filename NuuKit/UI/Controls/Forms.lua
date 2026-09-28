local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Settings rows and choice grids: the options screens and the guide editor
-- built these by hand in OpenRoad (PlannerOptions, the tracker's options,
-- the editor's step kinds).

-- Settings -------------------------------------------------------------------------------

-- One setting: its name and what it does on the left, the control on the
-- right, a hairline under it. Make the control in it (`setting:Select{…}`,
-- `setting:Slider{…}`). `opts`: help, labelWidth (260), onReset (a reset
-- after the control while SetChanged(true)). A Section's own reset stands
-- for "reset all".
UI.Define("Setting", function(ui, parent, caption, opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "row", { gap = 20, padding = 10, padLeft = 0, padRight = 0 })
    local about = frame:Column({ width = opts.labelWidth or 260, gap = 3 })
    frame.label = about:Text(caption or "", "body", { wrap = true })
    if opts.help then frame.help = about:Text(opts.help, "label", { wrap = true }) end
    frame.line = frame:CreateTexture(nil, "BACKGROUND")
    frame.line:SetPoint("BOTTOMLEFT")
    frame.line:SetPoint("BOTTOMRIGHT")
    UI.Hairline(frame.line, "height")

    -- Shows the reset while the setting differs from its default. Made the
    -- first time, so it lands after the control.
    function frame:SetChanged(changed)
        if not opts.onReset then return end
        if changed and not self.reset then
            self.reset = self:ResetButton({ onReset = function() opts.onReset(self) end })
        end
        if self.reset then self.reset:SetShown(changed and true or false) end
    end
    return ui:Finish(frame, opts, function(_, t) UI.TexColor(frame.line, t.hairline) end)
end)

-- Choices ----------------------------------------------------------------------------------

-- Buttons in even columns with one picked: the kind of a guide step, a bug
-- report's category. `options` are captions or { value, caption, tooltip,
-- disabled (a reason string) }. `opts`: columns (3), value, onChange(value).
UI.Define("Choices", function(ui, parent, options, opts)
    opts = opts or {}
    local columns = opts.columns or 3
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    UI.MakeContainer(ui, frame, "column", { gap = opts.gap or 6 })
    frame.buttons = {}
    local row
    for index, option in ipairs(options or {}) do
        if type(option) ~= "table" then option = { value = option, caption = tostring(option) } end
        if (index - 1) % columns == 0 then row = frame:Row({ gap = opts.gap or 6 }) end
        local button = row:Button(option.caption or tostring(option.value), {
            grow = true, tooltip = option.tooltip, disabled = option.disabled,
            onClick = function() frame:SetValue(option.value) end,
        })
        button.kitValue = option.value
        frame.buttons[#frame.buttons + 1] = button
    end
    -- The last row keeps the others' widths.
    local left = #frame.buttons % columns
    if row and left > 0 then
        for _ = left + 1, columns do row:Spacer() end
    end

    function frame:SetValue(value, silent)
        local changed = value ~= self.kitValue
        self.kitValue = value
        for _, button in ipairs(self.buttons) do button:SetActive(button.kitValue == value) end
        if changed and not silent and opts.onChange then opts.onChange(value) end
    end
    function frame:GetValue() return self.kitValue end
    frame:SetValue(opts.value, true)
    return ui:Finish(frame, opts)
end)
