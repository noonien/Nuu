-- C: B's core with a props schema over it. Every widget declares its
-- properties; the addon changes any of them the same way, `w:Set{ text = v }`
-- or `w:Set("text", v)`, reads them with `w:Get(key)`, and `bind` can tie any
-- prop to its table. Set compares, stores, applies through the schema and
-- marks the widget changed or repaints it. Everything else is B, so the
-- difference from B is what the props layer costs.

local C = dofile(BENCH .. "Common.lua")
local M = dofile(BENCH .. "B.lua")
local Widget = M.Widget

-- What each prop does: `apply(w, value)` sets the frame; `size` means it can
-- change the widget's size, `paint` that it changes colours only.
local fontStringSetText = UIParent:CreateFontString().SetText
local schemas = {
    Text = {
        text = { size = true, apply = function(w, v) fontStringSetText(w, v == nil and "" or tostring(v)) end },
        style = { size = true, apply = function(w, v) w.style = v; w:Paint(w.ui.tokens) end },
    },
    Button = {
        text = { size = true, apply = function(w, v) w.label:SetText(v == nil and "" or tostring(v)) end },
        tone = { paint = true, apply = function(w, v) w.tone = v or "neutral" end },
        onClick = { apply = function(w, v) w.onClick = v end },
    },
    Toggle = {
        value = { paint = true, apply = function(w, v) w.value = v and true or false end },
    },
}

function Widget:Set(key, value)
    if type(key) == "table" then
        for k, v in pairs(key) do self:Set(k, v) end
        return self
    end
    local props = self.props
    if not props then
        props = {}
        self.props = props
    end
    if props[key] == value then return self end
    props[key] = value
    local prop = schemas[self.kitType][key]
    prop.apply(self, value)
    if prop.size then self:Changed() end
    if prop.paint then self:PaintState(self.ui.tokens) end
    return self
end

function Widget:Get(key) return self.props and self.props[key] end

-- The widgets' own setters go through Set, so there is one path.
local types = M.types
types.Text.methods.SetText = function(self, v) return self:Set("text", v) end
types.Button.methods.SetText = function(self, v) return self:Set("text", v) end
types.Toggle.methods.SetValue = function(self, v) return self:Set("value", v and true or false) end
-- A binding writes its prop back to the addon's table.
types.Toggle.methods.Activate = function(self)
    self:Set("value", not self.value)
    if self.bind then self.bind[1][self.bind[2]] = self.value end
    if self.onChange then self.onChange(self.value, self) end
end
-- A widget made again from the pool starts with no props.
for _, def in pairs(types) do
    local init = def.Init
    def.Init = function(w, spec)
        w.props = nil
        init(w, spec)
    end
end

-- The sample screen: the same build as B, changes through Set.
-- screen:begin
function M.Screen(ui, win, db, items)
    local body = win:Column{ gap = 6, padding = 10 }
    local head = body:Row{ gap = 8 }
    head:Text{ "Settings", style = "title" }
    head:Spacer{}
    local toggles, counts = {}, {}
    head:Button{ "Reset", onClick = function()
        for i, key in ipairs(C.KEYS) do
            db[key] = nil
            toggles[i]:Set{ value = false }
        end
        for i, item in ipairs(items) do
            item.count = 0
            counts[i]:Set{ text = 0 }
        end
    end }
    for _, key in ipairs(C.KEYS) do
        toggles[#toggles + 1] = body:Toggle{ key, bind = { db, key } }
    end
    for i, item in ipairs(items) do
        local row = body:Row{ gap = 8 }
        row:Text{ item.name, grow = true }
        counts[i] = row:Text{ item.count, style = "number" }
        row:Button{ "+1", onClick = function()
            item.count = item.count + 1
            counts[i]:Set{ text = item.count }
        end }
    end
    return body
end
-- screen:end

return M
