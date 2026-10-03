local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- Settings rows and choice grids, for the options screens and the guide
-- editor (the planner's options, the tracker's options, the editor's step
-- kinds).

-- Settings -------------------------------------------------------------------------------

-- One setting: its name and what it does on the left, the control on the
-- right, a hairline under it. Make the control in it
-- (`setting:Select{ ... }`, `setting:Toggle{ ... }`). Spec: [1] the name,
-- help, labelWidth (260), gap (between controls, 8), default (words for the
-- reset's tooltip), onReset(setting).
--
-- The reset at the right shows while the setting differs from its default:
-- - a control made in it with `bind` is watched: the reset shows while the
--   control IsStored(), and a click calls the control's Reset();
-- - with onReset, `setting:SetChanged(changed)` shows it, and a click calls
--   onReset(setting), which says SetChanged(false) when it is done.
-- A Section's own reset stands for "reset all".

-- The first bound control made in the setting, while it is still there.
local function controlOf(w)
    local control = w.kitControl
    if control and (control.kitPooled or control.kitParent ~= w.controls) then
        w.kitControl = nil
        return nil
    end
    return control
end

local function settingReset(button)
    local w = button.kitSetting
    local control = controlOf(w)
    if control then control:Reset() end
    if w.kitOnReset then w.kitOnReset(w) end
    w:Refresh()
end

-- A bound control's onChange, standing in for the addon's: it passes the
-- change on, then the setting shows or hides its reset.
local function controlChanged(value, control)
    if control.kitSettingOnChange then control.kitSettingOnChange(value, control) end
    local controls = control.kitParent
    local w = controls and controls.kitSetting
    if w then w:Refresh() end
end

-- What is made in the setting goes in its controls row; the first bound
-- one is watched.
local function settingAppend(controls, child)
    UI.Stack.Append(controls, child)
    local w = controls.kitSetting
    if child.kitBind and child.IsStored and not controlOf(w) then
        w.kitControl = child
        child.kitSettingOnChange = child.kitOnChange
        child.kitOnChange = controlChanged
        w:Refresh()
    end
    return child
end

local SETTING_ROW = { gap = 20, padding = 10, padLeft = 0, padRight = 0 }

UI.Define("Setting", {
    holds = true,
    Build = function(w)
        local ui = w.ui
        w:SetSize(1, 1)
        UI.MakeStack(ui, w, "row", SETTING_ROW)

        local about = UI.Part(ui, w, "column", { gap = 3 }, { width = 260 })
        w.label = UI.Make(ui, "Text", about, { "", wrap = true })
        about:Append(w.label)
        w.help = UI.Make(ui, "Text", about, { "", style = "label", wrap = true })
        about:Append(w.help)
        w:Append(about)
        w.about = about

        -- The controls take the room between the name and the reset, so
        -- the resets of a page of settings line up at the right.
        local controls = UI.Part(ui, w, "row", { gap = 8 })
        controls.kitGrow = 1
        controls.kitSetting = w
        controls.Append = settingAppend
        w:Append(controls)
        w.controls = controls
        w.kitInner = controls

        local reset = UI.Make(ui, "ResetButton", w, { onReset = settingReset })
        reset.kitSetting = w
        w:Append(reset)
        w.reset = reset

        w.line = w:CreateTexture(nil, "BACKGROUND")
        w.line:SetPoint("BOTTOMLEFT")
        w.line:SetPoint("BOTTOMRIGHT")
        UI.Hairline(w.line, "height")
    end,
    Init = function(w, spec)
        UI.SetStack(w, "row", SETTING_ROW)
        UI.SetStack(w.controls, "row", { gap = spec.gap or 8 })
        local labelWidth = spec.labelWidth or 260
        if w.about.kitLayout.width ~= labelWidth then
            w.about.kitLayout.width = labelWidth
            UI.Changed(w.about)
        end
        w.label:SetText(spec[1] or "")
        w.help:SetText(spec.help or "")
        w.help:SetShown(spec.help ~= nil)
        w.kitOnReset, w.kitChanged, w.kitControl = spec.onReset, false, nil
        w.kitDefaultText = spec.default
        w:Refresh()
    end,
    Release = function(w)
        w.kitControl = nil
    end,
    methods = {
        -- With onReset: shows the reset while the setting differs from its
        -- default.
        SetChanged = function(self, changed)
            if not self.kitOnReset then return end
            self.kitChanged = changed and true or false
            self:Refresh()
        end,
        -- Shows or hides the reset again: after code changed the bound
        -- table itself.
        Refresh = function(self)
            local control = controlOf(self)
            local shown = (control and control:IsStored()) or (self.kitOnReset and self.kitChanged)
            self.reset:SetStored(shown and true or false, self.kitDefaultText)
        end,
        -- The control being watched, if any.
        GetControl = function(self) return controlOf(self) end,
        Paint = function(self, t) UI.TexColor(self.line, t.hairline) end,
    },
})

-- Choices ----------------------------------------------------------------------------------

-- Buttons in even columns with one picked: the kind of a guide step, a bug
-- report's category. The spec's array part is the options: captions, or
-- { value =, caption =, tooltip =, disabled = (a reason string) }. Spec:
-- columns (3), gap (6), value, bind, default, onChange(value, choices) when
-- the player picks another. `choices.buttons` are the buttons, in order.
local function choiceClick(button)
    local w = button.kitChoices
    if w then w:Choose(button.kitChoiceValue) end
end

UI.Define("Choices", {
    stack = true, fills = false,
    Build = function(w)
        w:SetSize(1, 1)
        UI.MakeStack(w.ui, w, "column", {})
        w.buttons = {}
    end,
    Init = function(w, spec)
        local gap = spec.gap or 6
        UI.SetStack(w, "column", { gap = gap })
        local columns = spec.columns or 3
        local buttons = w.buttons
        for index = #buttons, 1, -1 do buttons[index] = nil end
        local row
        for index, option in ipairs(spec) do
            local value, caption, tooltip, disabled
            if type(option) == "table" then
                value, caption, tooltip, disabled = option.value, option.caption, option.tooltip, option.disabled
            else
                value, caption = option, tostring(option)
            end
            if (index - 1) % columns == 0 then row = w:Row{ gap = gap } end
            local button = row:Button{ caption or tostring(value), grow = true, tooltip = tooltip, disabled = disabled,
                onClick = choiceClick }
            button.kitChoices, button.kitChoiceValue = w, value
            buttons[#buttons + 1] = button
        end
        -- The last row keeps the others' widths.
        local left = #buttons % columns
        if row and left > 0 then
            for _ = left + 1, columns do row:Spacer{} end
        end
        w:SetValue(UI.InitValue(w, spec))
    end,
    Release = function(w)
        for index = #w.buttons, 1, -1 do
            w.buttons[index].kitChoices = nil
            w.buttons[index] = nil
        end
    end,
    methods = {
        SetValue = function(self, value)
            self.kitValue = value
            for _, button in ipairs(self.buttons) do button:SetActive(button.kitChoiceValue == value) end
        end,
        GetValue = function(self) return self.kitValue end,
        -- The player's pick: onChange only when it is another.
        Choose = function(self, value)
            if value == self.kitValue then return end
            self:SetValue(value)
            UI.Commit(self, value)
        end,
    },
})
