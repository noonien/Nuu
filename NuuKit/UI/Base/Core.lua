local _, ns = ...

local Kit = ns.Kit or {}
ns.Kit = Kit
Kit.UI = Kit.UI or {}
local UI = Kit.UI

-- The UI kit's core. One UI per addon: `ns.UI = ns.Kit.NewUI(ns, look)`.
--
-- A widget is a frame with shared methods: each widget type is declared
-- once with UI.Define, and its methods reach every frame of that type
-- through one shared class (no closure per widget). A type splits its work
-- in three:
--   Build(w)        once per frame: regions, scripts (shared functions)
--   Init(w, spec)   each time it is made, from the pool too: every piece of
--                   state set again from the spec
--   Paint(w, t)     the look: fonts, colours, art; PaintState(w, t) the
--                   colours a hover, press or disable changes, and nothing
--                   that allocates or sets a font
-- Widgets are made two ways, the same spec behind both:
--   ui:Button(parent, { "Save", tone = "accent" })  -- placed by the caller
--   column:Button{ "Save", tone = "accent" }        -- made in the column and stacked
-- A cleared widget goes back to its type's pool and is made again from it;
-- the addon never sees the pools. Theme/ holds the colours, looks, text
-- styles and money code, which nothing here depends on.

UI.Widget = UI.Widget or {}   -- what every widget has
UI.Makers = UI.Makers or {}   -- a constructor per type, on stacks and on widgets that hold one
UI.types = UI.types or {}
UI.Proto = UI.Proto or {}     -- the methods of a UI
local Widget, Makers, types, Proto = UI.Widget, UI.Makers, UI.types, UI.Proto
-- Every UI made, for what reaches all widgets (a change of pixel scale).
UI.uis = UI.uis or setmetatable({}, { __mode = "k" })

-- Tokens ----------------------------------------------------------------------------------

-- The client's fonts: its own text face and its narrow number face.
function UI.FontFile(face)
    local object = face == "number" and _G.NumberFontNormal or _G.GameFontNormal
    local file = object and object.GetFont and object:GetFont()
    return file or (face == "number" and "Fonts\\ARIALN.TTF" or "Fonts\\FRIZQT__.TTF")
end

-- A look's colours (UI.LookTokens, Theme/Look.lua), plus what painting
-- needs worked out once per look: the font files, each text style's size,
-- and a cache for derived colours.
function UI.Tokens(look)
    local t = UI.LookTokens(look)
    t.fonts = { text = UI.FontFile(), number = UI.FontFile("number") }
    t.sizes = {}
    for style, spec in pairs(UI.textStyles) do
        t.sizes[style] = math.floor(spec.size * (t.textScale or 1) + 0.5)
    end
    t.cache = { color = {}, tone = {}, alpha = {}, mix = {}, button = {} }
    return t
end

-- Derived colours, made once per look and kept in its tokens, so painting
-- allocates nothing. Each caches the Theme/Look.lua function of the same idea.

-- A token name ("muted") or a colour ("#rrggbb", a table): TokenColor.
function UI.Colour(t, value)
    if value == nil then return nil end
    local cache = t.cache.color
    local color = cache[value]
    if color == nil then
        color = UI.TokenColor(t, value) or false
        cache[value] = color
    end
    return color or nil
end

-- A tone's base colour: ToneColor. nil for neutral.
function UI.Tone(t, tone)
    if tone == nil or tone == "neutral" then return nil end
    local cache = t.cache.tone
    local color = cache[tone]
    if color == nil then
        color = UI.ToneColor(t, tone) or false
        cache[tone] = color
    end
    return color or nil
end

-- `color` at `alpha`: Alpha.
function UI.Faded(t, color, alpha)
    if not color then return nil end
    local byColor = t.cache.alpha[color]
    if not byColor then
        byColor = {}
        t.cache.alpha[color] = byColor
    end
    local faded = byColor[alpha]
    if not faded then
        faded = UI.Alpha(color, alpha)
        byColor[alpha] = faded
    end
    return faded
end

-- `amount` of the way from `a` to `b`: Mix.
function UI.Mixed(t, a, b, amount)
    local byA = t.cache.mix[a]
    if not byA then
        byA = {}
        t.cache.mix[a] = byA
    end
    local byB = byA[b]
    if not byB then
        byB = {}
        byA[b] = byB
    end
    local mixed = byB[amount]
    if not mixed then
        mixed = UI.Mix(a, b, amount)
        byB[amount] = mixed
    end
    return mixed
end

-- A button's fill, edge and text colours: ButtonColors.
local NONE = {}
function UI.ButtonColorsOf(t, tone, style, state)
    local byTone = t.cache.button[tone or NONE]
    if not byTone then
        byTone = {}
        t.cache.button[tone or NONE] = byTone
    end
    local byStyle = byTone[style or NONE]
    if not byStyle then
        byStyle = {}
        byTone[style or NONE] = byStyle
    end
    local colors = byStyle[state]
    if not colors then
        local fill, edge, ink = UI.ButtonColors(t, tone, style, state)
        colors = { fill or false, edge or false, ink or false }
        byStyle[state] = colors
    end
    return colors[1] or nil, colors[2] or nil, colors[3] or nil
end

-- A UI ----------------------------------------------------------------------------------------

-- One per addon. It holds the look, the tokens made from it, every widget it
-- made (to repaint them) and the pools.
function Kit.NewUI(owner, look)
    local ui = setmetatable({
        owner = owner,
        widgets = setmetatable({}, { __mode = "k" }),
        painters = setmetatable({}, { __mode = "k" }),
        focusables = setmetatable({}, { __mode = "k" }),
        listeners = {},
        pools = {},
    }, { __index = Proto })
    ui.look = UI.ResolveLook(look)
    ui.tokens = UI.Tokens(ui.look)
    UI.uis[ui] = true
    return ui
end

-- Repaints every widget this UI made, open windows included. A new text
-- size also measures everything again.
function Proto:SetLook(look)
    local scale = self.tokens.textScale
    self.look = UI.ResolveLook(look)
    self.tokens = UI.Tokens(self.look)
    self:RepaintAll(self.tokens.textScale ~= scale)
    for _, fn in ipairs(self.listeners) do pcall(fn, self.look, self) end
end

function Proto:GetLook()
    local copy = {}
    for key, value in pairs(self.look) do copy[key] = value end
    return copy
end

-- `fn(tokens)` paints `object` now and after every look change: for what the
-- addon draws itself.
function Proto:Paint(object, fn)
    self.painters[object] = fn
    fn(self.tokens)
    return object
end

function Proto:Unpaint(object) self.painters[object] = nil end

-- `fn(look, ui)` after every look change and its repaint.
function Proto:OnLook(fn) table.insert(self.listeners, fn) end

function Proto:RepaintAll(resized)
    local t = self.tokens
    for w in pairs(self.widgets) do
        if not w.kitPooled then
            w:Paint(t)
            if resized then w:Changed() end
        end
    end
    for object, fn in pairs(self.painters) do fn(t) end
end

-- Defining and making widgets ------------------------------------------------------------------

-- Declares a widget type. `def`:
--   kind        the frame type: "Frame" (default), "Button", "EditBox",
--               "ScrollFrame", "Slider", "FontString"...; template
--   Create(ui, parent, spec)  makes the frame instead (a template chosen
--               per widget, a pcall)
--   Build(w), Init(w, spec), Release(w), methods (see the top of the file)
--   stack       true: the widget is a column or row; what is made in it
--               stacks in it
--   holds       true: the widget holds a stack of its own in w.kitInner
--               (a section's body, a card's); what is made on it goes there
--   stretch     false: not stretched across a column (buttons, toggles)
--   valign      where it sits across a row when the spec says nothing ("top")
--   wraps       true: its height depends on its width (wrapped text)
--   fills       true: grows to fill a window, pane or page it is made in
--   grow(spec, parent)  its grow weight when the spec gives none
--   fit         false: made by the caller, it is not sized to its natural
--               size (a column the caller anchors)
--   focusable   true, or "field": joins its window's Tab order
--   tooltip     true: hooks the tooltip whatever the spec says (it can be
--               disabled with a reason, or show an item)
--   pool        false: never reused (secure frames)
--   internal    true: a part the kit builds widgets from (a tab, a list's
--               row), made with UI.Make only: no ui: or stack constructor
function UI.Define(name, def)
    types[name] = def
    def.name = name
    if def.internal then return end
    -- Placed by the caller: `ui:Button(parent, spec)`.
    Proto[name] = function(ui, parent, spec)
        local w = UI.Make(ui, name, parent, spec)
        if def.fit ~= false then w.kitFree = true; UI.Fit(w) end
        return w
    end
    -- Made in a stack, or in the stack a widget holds.
    Makers[name] = function(self, spec)
        local target = self.kitInner or self
        local w = UI.Make(self.ui, name, target, spec)
        target:Append(w)
        return w
    end
    -- Stack classes made before this type was defined (a type an addon
    -- defines late, on a kit another addon already built with) take its
    -- maker too. Frames with copied methods (UI.sharedMethods false) do not.
    for _, byBase in pairs(UI.classes or {}) do
        for _, class in pairs(byBase) do
            local index = class.kitIndex
            if index and rawget(index, "kitMakers") then index[name] = Makers[name] end
        end
    end
end

local function copyInto(target, methods)
    for key, fn in pairs(methods) do target[key] = fn end
end

-- Methods a widget that holds a stack answers for it.
UI.Holder = UI.Holder or {}

-- Classes -------------------------------------------------------------------------------------

-- A frame's methods reach it through a metatable made once per class and
-- frame kind: the class's methods, then the client's own. Nothing is copied
-- onto the frame, so its table holds only its state (a Lua table doubles in
-- size at 16, 32, 64 keys, and copied methods pushed rows past 64). Should
-- the client refuse a frame a metatable, or the frame then miss its own
-- methods, every frame after has its methods copied on instead, as before;
-- UI.sharedMethods says which (nil until the first frame).
UI.sharedMethods = nil
local classes = {}
-- By class key, then by the client's metatable: for the audit (Dev/Audit.lua).
UI.classes = classes
local RAW = { "Show", "Hide", "IsShown", "SetAlpha", "SetScale" }

-- The client's own method `name` for frames of this metatable.
local function rawOf(index, name, frame)
    if type(index) == "table" then return index[name] end
    if type(index) == "function" then return index(frame, name) end
    return nil
end

local function classFor(key, frame, sources, extra)
    local base = getmetatable(frame)
    if type(base) ~= "table" then return nil end
    local byBase = classes[key]
    if not byBase then
        byBase = {}
        classes[key] = byBase
    end
    local class = byBase[base]
    if class then return class end
    local index = {}
    for _, source in ipairs(sources) do copyInto(index, source) end
    if extra then copyInto(index, extra) end
    for _, source in ipairs(sources) do
        if source == Makers then index.kitMakers = true end
    end
    local original = base.__index
    for _, name in ipairs(RAW) do index["kitRaw" .. name] = rawOf(original, name, frame) end
    index.kitClass = key
    setmetatable(index, { __index = original })
    class = {}
    for field, value in pairs(base) do class[field] = value end
    class.__index = index
    -- The method table, also while the audit answers __index (Dev/Audit.lua).
    class.kitIndex = index
    byBase[base] = class
    if UI.OnClass then UI.OnClass(class) end
    return class
end

-- Gives `frame` the methods of `sources` (tables, later ones winning) and
-- the fields of `extra`, as the class `key`.
function UI.Adopt(frame, key, sources, extra)
    if UI.sharedMethods ~= false then
        local base = getmetatable(frame)
        local class = classFor(key, frame, sources, extra)
        local ok = class and pcall(setmetatable, frame, class)
        if ok and frame.kitClass == key and frame.GetParent then
            UI.sharedMethods = true
            return frame
        end
        if ok then pcall(setmetatable, frame, base) end
        UI.sharedMethods = false
    end
    for _, source in ipairs(sources) do copyInto(frame, source) end
    if extra then copyInto(frame, extra) end
    local original = getmetatable(frame) and getmetatable(frame).__index
    for _, name in ipairs(RAW) do frame["kitRaw" .. name] = rawOf(original, name, frame) end
    frame.kitClass = key
    return frame
end

-- Resetting released frames -------------------------------------------------------------------

-- An addon that changes a widget with the plain API marks it, saying what
-- it changed (w:Customize, below), and on release only that is undone:
-- most widgets are never touched, and resetting every one cost about 9 us
-- a widget in build 70009. "marked" (the default); "always" resets every
-- widget in full; nil resets none, for measuring (Dev/Report.lua).
UI.resetMode = "marked"

-- SetToDefaults also takes away the kit's own setup of the frame, so the
-- setup calls a type's Build makes on its widget are recorded, the first
-- time the type is built, and made again after a reset. Build uses shared
-- functions only (see README.md), so one record serves every widget of the
-- type.
local NO_SPEC = {}
local SETUP = { "SetScript", "HookScript", "RegisterForClicks", "EnableMouse", "EnableMouseWheel",
    "SetMotionScriptsWhileDisabled", "SetMovable", "SetResizable", "SetClampedToScreen", "SetFrameStrata",
    "SetToplevel", "SetClipsChildren", "SetHitRectInsets", "EnableKeyboard", "SetPropagateKeyboardInput",
    "RegisterForDrag", "SetAttribute" }
local NO_SETUP = {}

local function buildRecorded(w, def)
    local log = {}
    local target = UI.sharedMethods and getmetatable(w).kitIndex or w
    local saved, original = {}, {}
    for _, name in ipairs(SETUP) do
        original[name] = w[name]
        saved[name] = rawget(target, name)
        local call = original[name]
        if call then
            target[name] = function(self, ...)
                if self == w then log[#log + 1] = { name, ... } end
                return call(self, ...)
            end
        end
    end
    local ok, err = pcall(def.Build, w)
    for _, name in ipairs(SETUP) do rawset(target, name, saved[name]) end
    if not ok then error(err, 0) end
    def.kitSetup = log
    def.kitMouse = w.IsMouseEnabled and w:IsMouseEnabled() or false
    def.kitWheel = w.IsMouseWheelEnabled and w:IsMouseWheelEnabled() or false
end

-- Which parts of a reset run, for measuring them apart: nil runs them all,
-- else { defaults = true, events = true, setup = true }. A reset without
-- its setup leaves a widget that does not work; only for timing.
UI.resetParts = nil

-- Back to the client's defaults, then the kit's own setup again. The frame
-- is left shown (SetToDefaults shows it); Release hides it after.
function UI.ResetFrame(w, def)
    if not w.SetToDefaults then return end
    local parts = UI.resetParts
    if not parts or parts.defaults then
        w:SetToDefaults()
        -- A font string without a font refuses text: that much goes with it.
        if def.kind == "FontString" then
            w:SetFont(UI.FontFile(), 11, "")
            w.kitFontFile, w.kitFontSize, w.kitShadowed, w.kitWrap, w.kitText = nil, nil, nil, nil, nil
        end
    end
    if not parts or parts.events then
        if w.UnregisterAllEvents then w:UnregisterAllEvents() end
        -- SetToDefaults keeps the keyboard (build 70009): a widget left
        -- taking it would stop the game's keybinds.
        if w.EnableKeyboard then w:EnableKeyboard(false) end
    end
    if parts and not parts.setup then return end
    if def.kind ~= "FontString" then
        if w.EnableMouse then w:EnableMouse(def.kitMouse) end
        if w.EnableMouseWheel then w:EnableMouseWheel(def.kitWheel) end
    end
    for _, call in ipairs(def.kitSetup or NO_SETUP) do w[call[1]](w, unpack(call, 2)) end
    -- The kit's hooks made after Build come back when next asked for.
    w.kitTooltipHooked, w.kitRightHooked = nil, nil
end

-- What a mark can ask to be undone, as flags (UI.Custom, also ui.Custom),
-- each undone by its cheapest call:
--   events  UnregisterAllEvents (widgets register none of their own)
--   parts   textures, texts and frames made on it with the plain API hidden
--   frame   everything about the frame: SetToDefaults, events, keyboard,
--           and the kit's setup made again (covers events)
-- Flags add up: Custom.frame + Custom.parts. Anchors, size, parent and
-- frame level need no mark: the kit sets them on every use. Nor do alpha
-- and scale: the widget's own SetAlpha and SetScale note a change, and
-- release puts it back.
local EVENTS, PARTS, FRAME = 1, 2, 4
local FLAGS = { EVENTS, PARTS, FRAME }
UI.Custom = { events = EVENTS, parts = PARTS, frame = FRAME }
Proto.Custom = UI.Custom

-- Whether `marks` holds `flag` (no bit library needed for three flags).
local function has(marks, flag) return marks % (flag + flag) >= flag end
UI.HasFlag = has

-- Marks the widget for a reset on release; returns it. Call it where the
-- addon changes the widget, e.g. w:Customize(ui.Custom.frame):HookScript(...);
-- no flags means frame and parts. The marks are one number on the widget.
-- In development the audit (Dev/Audit.lua) logs a change made without its
-- mark, and a mark that nothing needed; it keeps where each mark was made.
function Widget:Customize(flags)
    -- In development, wrong flags are an error (Dev/Audit.lua).
    if UI.audit then UI.AuditFlags(flags) end
    flags = flags or (FRAME + PARTS)
    local marks = self.kitCustom or 0
    local where = UI.audit and UI.AuditCaller()
    for _, flag in ipairs(FLAGS) do
        if has(flags, flag) and not has(marks, flag) then
            marks = marks + flag
            if where then
                local at = self.kitMarkedAt or {}
                at[flag] = where
                self.kitMarkedAt = at
            end
        end
    end
    self.kitCustom = marks
    return self
end

local releaseStrays

-- Undoes what the marks (flags) ask for; `marks` nil undoes everything.
function UI.ResetMarked(w, def, marks)
    if not marks or has(marks, FRAME) then
        -- SetToDefaults puts back alpha and scale too.
        UI.ResetFrame(w, def)
        w.kitFaded, w.kitScaled = nil, nil
    elseif has(marks, EVENTS) and w.UnregisterAllEvents then
        w:UnregisterAllEvents()
    end
    if (not marks or has(marks, PARTS)) and def.kind ~= "FontString" then releaseStrays(w) end
end

local function build(ui, name, def, parent, spec)
    local w
    if def.Create then
        w = def.Create(ui, parent, spec)
    elseif def.kind == "FontString" then
        w = parent:CreateFontString(nil, def.layer or "OVERLAY")
        -- The client refuses text on a font string with no font, and Init
        -- sets text before Paint sets the style's font.
        w:SetFont(UI.FontFile(), 11, "")
    else
        w = CreateFrame(def.kind or "Frame", nil, parent, def.template)
    end
    local sources = { Widget }
    if def.stack or def.holds then
        sources[#sources + 1] = UI.Stack
        sources[#sources + 1] = Makers
    end
    if def.holds then sources[#sources + 1] = UI.Holder end
    sources[#sources + 1] = def.methods or {}
    def.class = def.class or { kitType = name, kitWraps = def.wraps or def.stack or def.holds or nil }
    UI.Adopt(w, name, sources, def.class)
    w.ui = ui
    if def.Build then
        if def.kitSetup then def.Build(w) else buildRecorded(w, def) end
        -- Copied methods: the type's own win over what Build copied on.
        if UI.sharedMethods == false then copyInto(w, def.methods or {}) end
    end
    ui.widgets[w] = true
    return w
end

local serial = 0

-- Makes (or takes from the pool) a widget of type `name` in `parent`. The
-- spec is the widget's options; a string is short for { text }.
function UI.Make(ui, name, parent, spec)
    if type(spec) ~= "table" then spec = { spec } end
    local def = types[name]
    assert(def, "no widget type " .. tostring(name))
    local pool = def.pool ~= false and ui.pools[name]
    local w = pool and pool[#pool]
    local fresh = not w
    if w then
        pool[#pool] = nil
        w.kitPooled = nil
        if w:GetParent() ~= parent then w:SetParent(parent) end
        if w.SetFrameLevel and parent.GetFrameLevel then w:SetFrameLevel(parent:GetFrameLevel() + 1) end
        w:Show()
    else
        w = build(ui, name, def, parent, spec)
    end
    w.kitLayout = spec
    w.kitNatW, w.kitNatH = nil, nil
    local stretch = spec.stretch
    if stretch == nil then stretch = def.stretch end
    w.kitStretch = stretch
    local grow = spec.grow
    if grow == nil and def.grow then grow = def.grow(spec, parent) end
    w.kitGrow = (grow == true and 1) or (type(grow) == "number" and grow > 0 and grow) or nil
    w.hover, w.kitReason, w.kitRightClick, w.kitLinks = nil, nil, nil, nil
    w.tooltip, w.data = spec.tooltip, spec.data
    if def.focusable then UI.RegisterFocusable(ui, w, def.focusable == "field") end
    if UI.audit then w.kitMadeAt = UI.AuditCaller() end
    def.Init(w, spec)
    if spec.tooltip ~= nil or def.tooltip then UI.HookTooltip(w) end
    if spec.hidden then w:Hide() end
    w:Paint(ui.tokens)
    if fresh then UI.KitMade(w) end
    return w
end

-- The kit's own frames: marked, so a release that looks for an addon's
-- frames on a widget (the "parts" mark, the audit) passes over them.
function UI.NewFrame(kind, name, parent, template)
    local frame = CreateFrame(kind, name, parent, template)
    frame.kitOwn = true
    return frame
end

-- The textures, texts and child frames a new widget holds are the kit's:
-- marked, so that on release anything else (an addon's own, made with the
-- plain API) is found and hidden. Two client calls, once per frame. A
-- texture or text the kit makes later is hidden on release too, harmlessly:
-- the kit shows its parts again where it uses them (the audit marks those).
local function markAll(...)
    local count = select("#", ...)
    for index = 1, count do
        local part = select(index, ...)
        if part then part.kitOwn = true end
    end
    return count
end

function UI.KitMade(w)
    if types[w.kitType] and types[w.kitType].kind == "FontString" then return end
    w.kitOwnRegions = markAll(w:GetRegions())
    w.kitOwnChildren = markAll(w:GetChildren())
end

-- On release, for a widget marked "parts": what an addon made on it and the
-- kit did not (see KitMade) is hidden. `UI.stats.strays` counts them.
-- Widgets of the kit parented to it (a stack's texts and buttons) raise its
-- counts too, so the counts are taken again after a look: a widget looks
-- again only when it holds more than last time.
UI.stats = UI.stats or { strays = 0 }

local function isStray(part)
    return part and not part.kitOwn and not part.kitType and not part.kitClass and part:IsShown()
end

local function hideStrays(w, ...)
    for index = 1, select("#", ...) do
        local part = select(index, ...)
        if isStray(part) then
            part:Hide()
            UI.stats.strays = UI.stats.strays + 1
        end
    end
end

function releaseStrays(w)
    local regions, children = w:GetNumRegions() or 0, w:GetNumChildren() or 0
    if regions > (w.kitOwnRegions or 0) then
        hideStrays(w, w:GetRegions())
        w.kitOwnRegions = regions
    end
    if children > (w.kitOwnChildren or 0) then
        hideStrays(w, w:GetChildren())
        w.kitOwnChildren = children
    end
end

-- Whether an addon made a part on the widget, for the audit: looks without
-- hiding, and takes no counts.
local function anyStray(...)
    for index = 1, select("#", ...) do
        if isStray(select(index, ...)) then return true end
    end
    return false
end

function UI.HasStrays(w)
    if types[w.kitType].kind == "FontString" then return false end
    return anyStray(w:GetRegions()) or anyStray(w:GetChildren())
end

-- An addon's own texture, text or frame on a widget, which the kit keeps
-- with the widget: on release it is put back to defaults and hidden, and
-- the next Add of the same kind on that frame takes it again, so a
-- decoration made on every use costs nothing more.
local function added(w, key, make)
    local list = w.kitAdded
    if not list then
        list = {}
        w.kitAdded = list
    end
    for index = 1, #list do
        local item = list[index]
        if not item.kitInUse and item.kitAddKey == key then
            item.kitInUse = true
            item:Show()
            return item, false
        end
    end
    local item = make()
    item.kitAddKey, item.kitInUse, item.kitOwn = key, true, true
    list[#list + 1] = item
    return item, true
end

function Widget:AddTexture(layer, sublevel)
    local texture = added(self, "Texture", function() return self:CreateTexture(nil, layer or "ARTWORK") end)
    texture:SetDrawLayer(layer or "ARTWORK", sublevel or 0)
    return texture
end

-- A text in a kit text style (UI.ApplyStyle); `color` a token or a colour.
function Widget:AddText(style, color)
    local text = added(self, "Text", function() return UI.NewText(self) end)
    UI.ApplyStyle(text, style or "body", self.ui.tokens, color)
    return text
end

function Widget:AddFrame(kind, template)
    local key = "Frame:" .. (kind or "Frame") .. ":" .. (template or "")
    return (added(self, key, function() return CreateFrame(kind or "Frame", nil, self, template) end))
end

local function releaseAdded(w)
    local list = w.kitAdded
    if not list then return end
    for index = 1, #list do
        local item = list[index]
        if item.kitInUse then
            item.kitInUse = false
            if item.SetToDefaults then pcall(item.SetToDefaults, item) end
            if item.UnregisterAllEvents then item:UnregisterAllEvents() end
            if item.GetObjectType and item:GetObjectType() == "FontString" then
                item:SetFont(UI.FontFile(), 11, "")
                item.kitFontFile, item.kitFontSize, item.kitShadowed = nil, nil, nil
            end
            item:Hide()
            item:ClearAllPoints()
        end
    end
end

-- Widget methods -------------------------------------------------------------------------------

function Widget:Paint(t) end

-- Shown or hidden, a widget tells the stack it is in, whether or not the
-- client would fire OnShow / OnHide (it does not for a frame in a hidden
-- window).
function Widget:Show()
    if self:kitRawIsShown() then return end
    self:kitRawShow()
    if self.kitParent then UI.ChildToggled(self) end
end

function Widget:Hide()
    if not self:kitRawIsShown() then return end
    self:kitRawHide()
    if self.kitParent then UI.ChildToggled(self) end
end

function Widget:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

-- Alpha and scale remember whether they are off the default, so a release
-- puts back only what was changed, and an addon needs no mark for them.
function Widget:SetAlpha(alpha)
    self.kitFaded = alpha ~= 1 or nil
    self:kitRawSetAlpha(alpha)
end

function Widget:SetScale(scale)
    self.kitScaled = scale ~= 1 or nil
    if self.kitRawSetScale then self:kitRawSetScale(scale) end
end
function Widget:PaintState(t) self:Paint(t) end
function Widget:Repaint() self:Paint(self.ui.tokens) end

-- Its natural size: `Measure(width)` answers width, height: the natural
-- width whatever `width` is, and the height for `width` when the widget
-- wraps.
function Widget:Measure() return self:GetWidth() or 0, self:GetHeight() or 0 end

function Widget:NaturalWidth()
    local fixed = self.kitLayout.width
    if fixed then return fixed end
    local width = self.kitNatW
    if width == nil then
        local height
        width, height = self:Measure(nil)
        self.kitNatW = width
        if not self.kitWraps then self.kitNatH, self.kitNatFor = height, false end
    end
    return width
end

function Widget:NaturalHeight(width)
    local fixed = self.kitLayout.height
    if fixed then return fixed end
    local height = self.kitNatH
    if height == nil or (self.kitNatFor ~= false and self.kitNatFor ~= width) then
        local measured
        if self.kitWraps then
            measured, height = self:Measure(width)
            self.kitNatFor = width
            -- Measure answers the natural width whatever the width asked.
            if self.kitNatW == nil then self.kitNatW = measured end
        else
            measured, height = self:Measure(nil)
            self.kitNatFor = false
            if self.kitNatW == nil then self.kitNatW = measured end
        end
        self.kitNatH = height
    end
    return height
end

-- Tells the layout this widget's natural size may have changed.
function Widget:Changed() UI.Changed(self) end

-- Its frame, for SetPoint and the client's own calls.
function Widget:GetFrame() return self.kitInner or self end

function Widget:SetTooltip(tip)
    self.tooltip = tip
    UI.HookTooltip(self)
end

function Widget:OnRightClick(fn) return UI.OnRightClick(self, fn) end

-- Back to the pool: what it holds goes first, then it hides.
function Widget:Release()
    if self.kitPooled then return end
    local parent = self.kitParent
    if parent then parent:Remove(self) return end
    UI.Release(self)
end

-- What the addon made in it goes back too: a stack's children, or those of
-- the stack it holds. Its own parts (a section's heading) stay with it.
function UI.Release(w)
    local def = types[w.kitType]
    if def.stack then w:ReleaseChildren() end
    if w.kitInner and w.kitInner ~= w then w.kitInner:ReleaseChildren() end
    if def.Release then def.Release(w) end
    if w.kitAttractKind and UI.Attract then UI.Attract(w, nil) end
    -- What still points at it: the kit's tooltip for it, a menu by it, the
    -- focus ring on it.
    local ui = w.ui
    if UI.tipOwner == w then ui:HideTooltip() end
    if ui.kitMenu and ui.kitMenu.anchor == w then ui:CloseMenu() end
    local win = w.kitWindow
    if win and win.kitFocused == w then UI.FocusWidget(win, nil) end
    w.kitParent, w.kitWindow = nil, nil
    w.kitPX, w.kitPY, w.kitPW, w.kitPH, w.kitFree = nil, nil, nil, nil, nil
    if def.pool ~= false then
        local marks, mode = w.kitCustom, UI.resetMode
        if UI.audit then UI.AuditRelease(w, marks or 0) end
        if mode == "always" then
            UI.ResetMarked(w, def, nil)
        elseif mode and marks then
            UI.ResetMarked(w, def, marks)
        end
        w.kitCustom, w.kitMarkedAt = nil, nil
        if w.kitFaded then w:SetAlpha(1) end
        if w.kitScaled then w:SetScale(1) end
        releaseAdded(w)
    end
    -- Nothing of the addon's is kept alive by a widget in a pool.
    w.kitLayout, w.data, w.tooltip, w.kitLinks, w.kitRightClick = NO_SPEC, nil, nil, nil, nil
    w.kitClick, w.kitOnChange, w.kitBind, w.kitDefault = nil, nil, nil, nil
    w:Hide()
    w:ClearAllPoints()
    if def.pool == false then
        -- Never made again: out of the repaint and the Tab order.
        w.ui.widgets[w], w.ui.focusables[w] = nil, nil
        w.kitRetired = true
        return
    end
    w.kitPooled = true
    local pool = w.ui.pools[w.kitType]
    if not pool then
        pool = {}
        w.ui.pools[w.kitType] = pool
    end
    pool[#pool + 1] = w
end

-- Value widgets --------------------------------------------------------------------------------

-- A value widget's start, from its spec: `bind` ({ table, key }: the
-- addon's own table), `value`, `default`, `onChange`. Answers the value to
-- show: the table's, else `value`, else `default`.
function UI.InitValue(w, spec)
    w.kitBind, w.kitDefault, w.kitOnChange = spec.bind, spec.default, spec.onChange
    local value
    if spec.bind then value = spec.bind[1][spec.bind[2]] end
    if value == nil then value = spec.value end
    if value == nil then value = spec.default end
    return value
end

-- After the player changes a value: into the bound table, then onChange.
-- Code that sets a value never comes here.
function UI.Commit(w, value)
    local bind = w.kitBind
    if bind then bind[1][bind[2]] = value end
    if w.kitOnChange then w.kitOnChange(value, w) end
end

-- Whether the bound table holds the player's choice.
function Widget:IsStored()
    local bind = self.kitBind
    return bind ~= nil and bind[1][bind[2]] ~= nil
end

-- Forgets the player's choice: the default shows, and onChange hears it.
function Widget:Reset()
    local bind = self.kitBind
    if bind then bind[1][bind[2]] = nil end
    if self.SetValue then self:SetValue(self.kitDefault) end
    if self.kitOnChange then
        local value = self.kitDefault
        if self.GetValue then value = self:GetValue() end
        self.kitOnChange(value, self)
    end
end

-- Hover on a part of a widget (a tab, a row, a band): the part's `hover`
-- goes on and off and its owner (`part.kitOwner`, else the part) repaints
-- its colours. One pair of scripts for every such part.
local function hoverEnter(part)
    part.hover = true
    local owner = part.kitOwner or part
    owner:PaintState(owner.ui.tokens)
end

local function hoverLeave(part)
    part.hover = false
    local owner = part.kitOwner or part
    owner:PaintState(owner.ui.tokens)
end

function UI.Hover(part, owner)
    if owner then part.kitOwner = owner end
    part:SetScript("OnEnter", hoverEnter)
    part:SetScript("OnLeave", hoverLeave)
    return part
end

-- Right-click on any widget: `fn(widget)`.
local function rightClicked(w, button)
    if button == "RightButton" and w.kitRightClick then w.kitRightClick(w) end
end

function UI.OnRightClick(w, fn)
    w.kitRightClick = fn
    if w.kitRightHooked then return w end
    w.kitRightHooked = true
    if w.RegisterForClicks and w:GetObjectType() == "Button" then
        w:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        w:HookScript("OnClick", rightClicked)
    elseif w.HookScript then
        w:EnableMouse(true)
        w:HookScript("OnMouseUp", rightClicked)
    end
    return w
end

-- Keyboard focus: what joins a window's Tab order, in the order it was made.
function UI.RegisterFocusable(ui, w, isField)
    serial = serial + 1
    w.kitSerial = serial
    w.kitFocusable = true
    w.kitIsField = isField or nil
    ui.focusables[w] = true
end

-- The window a widget is in.
function UI.WindowOf(w)
    local frame = w
    while frame do
        if frame.kitIsWindow then return frame end
        if frame.kitWindow then return frame.kitWindow end
        frame = frame.kitParent or (frame.GetParent and frame:GetParent())
    end
    return nil
end

-- Painting helpers ------------------------------------------------------------------------------

function UI.TexColor(texture, color, alphaScale)
    if not color then
        texture:SetColorTexture(0, 0, 0, 0)
        return
    end
    texture:SetColorTexture(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

local WHITE = { 1, 1, 1, 1 }

function UI.TextColor(fontString, color, alphaScale)
    color = color or WHITE
    fontString:SetTextColor(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

function UI.VertexColor(texture, color, alphaScale)
    color = color or WHITE
    texture:SetVertexColor(color[1], color[2], color[3], (color[4] or 1) * (alphaScale or 1))
end

-- Sets a font string to a text style for the tokens `t`: face and size (only
-- when they change), the shadow (once), and the colour unless `keepColor`.
-- `color` a token name or a colour, else the style's.
function UI.ApplyStyle(fontString, style, t, color, keepColor)
    local spec = UI.textStyles[style] or UI.textStyles.body
    local file = t.fonts[spec.face == "number" and "number" or "text"]
    local size = t.sizes[style] or t.sizes.body
    if fontString.kitFontFile ~= file or fontString.kitFontSize ~= size then
        local ok = pcall(fontString.SetFont, fontString, file, size, "")
        if not ok then pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", size, "") end
        fontString.kitFontFile, fontString.kitFontSize = file, size
    end
    if not fontString.kitShadowed and fontString.SetShadowColor then
        fontString.kitShadowed = true
        -- Pale text holds over the world with its hard shadow.
        fontString:SetShadowColor(0, 0, 0, 0.9)
        fontString:SetShadowOffset(1, -1)
    end
    if not keepColor then UI.TextColor(fontString, UI.Colour(t, color or spec.color) or t.text) end
end

-- A plain font string: one line, left.
function UI.NewText(parent, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(UI.FontFile(), 11, "")
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

-- How wide a line of text wants to be, whatever width it is held to now.
function UI.StringWidth(label)
    if label.GetUnboundedStringWidth then
        local ok, width = pcall(label.GetUnboundedStringWidth, label)
        if ok and type(width) == "number" then return width end
    end
    return label:GetStringWidth() or 0
end

-- Whether a texture really took its file. Some clients answer SetTexture
-- with false for a path they do not have, others take it and leave the
-- texture empty; either way the caller draws flat instead.
function UI.LoadTexture(texture, path, wrapH, wrapV)
    local ok, set
    if wrapH then
        ok, set = pcall(texture.SetTexture, texture, path, wrapH, wrapV)
    else
        ok, set = pcall(texture.SetTexture, texture, path)
    end
    if not ok or set == false or texture:GetTexture() == nil then return false end
    return true
end

-- Moves a region by a pixel or two wherever it is anchored: the press nudge.
function UI.ShiftPoints(region, dx, dy)
    local count = region:GetNumPoints()
    if count == 0 then return end
    local points = {}
    for index = 1, count do points[index] = { region:GetPoint(index) } end
    region:ClearAllPoints()
    for _, point in ipairs(points) do
        region:SetPoint(point[1], point[2] or region:GetParent(), point[3] or point[1], (point[4] or 0) + dx, (point[5] or 0) + dy)
    end
end

-- The light tick of the chat scroll buttons.
function UI.ClickSound()
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    local sound = SOUNDKIT.U_CHAT_SCROLL_BUTTON or SOUNDKIT.IG_MAINMENU_OPTION
    if sound then pcall(PlaySound, sound) end
end

function UI.Now()
    return type(GetTime) == "function" and GetTime() or 0
end

-- WoW keeps a field focused through a click anywhere else, so keys go on
-- landing in it; taking the focus away lets a field commit before the click
-- that follows acts. Only the kit's own fields: a chat line stays open.
function UI.ClearTypingFocus(except)
    if type(GetCurrentKeyBoardFocus) ~= "function" then return end
    local focus = GetCurrentKeyBoardFocus()
    if focus and focus ~= except and focus.kitField then focus:ClearFocus() end
end

-- Screen pixels ---------------------------------------------------------------------------------

-- WoW lays the UI out in units, not screen pixels: one unit is
-- GetEffectiveScale() x (physical screen height / 768) pixels, 1.67 at 1440p
-- with a UI scale of 0.89. An edge at a fraction of a pixel is rounded when
-- drawn, so a 1 unit line comes out 1 or 2 pixels wide. So every place,
-- size and line is put on whole screen pixels. The pixels in a unit are read once, and again when the UI scale
-- or the resolution changes: the kit never scales its own frames, so every
-- frame under UIParent has UIParent's scale.
local pixelScale

local function readScale()
    local scale = 1
    if UIParent and UIParent.GetEffectiveScale then scale = UIParent:GetEffectiveScale() or 1 end
    if not scale or scale <= 0 then scale = 1 end
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, height = pcall(GetPhysicalScreenSize)
        if ok and type(height) == "number" and height > 0 then scale = scale * height / 768 end
    end
    pixelScale = scale
    return scale
end

-- Screen pixels in one unit. `frame` is ignored: every kit frame has
-- UIParent's scale.
function UI.PixelsPerUnit() return pixelScale or readScale() end

function UI.Snap(_, value)
    local scale = pixelScale or readScale()
    return math.floor(value * scale + 0.5) / scale
end

function UI.Pixels(_, count)
    return (count or 1) / (pixelScale or readScale())
end

local strokes = setmetatable({}, { __mode = "k" })
local function applyStroke(texture, pixels, units, axis)
    local scale = pixelScale or readScale()
    local size = (pixels or math.max(1, math.floor(units * scale + 0.5))) / scale
    if axis == "width" then texture:SetWidth(size) else texture:SetHeight(size) end
end

-- Exactly one screen pixel thick across `axis` ("height" or "width").
function UI.Hairline(texture, axis)
    strokes[texture] = axis == "width" and "w1" or "h1"
    applyStroke(texture, 1, nil, axis)
end

-- `units` thick across `axis`, in whole screen pixels, never under one.
local strokeUnits = setmetatable({}, { __mode = "k" })
function UI.Stroke(texture, axis, units)
    strokes[texture] = axis == "width" and "w" or "h"
    strokeUnits[texture] = units or 1
    applyStroke(texture, nil, units or 1, axis)
end

local scaleListeners = setmetatable({}, { __mode = "k" })
function UI.OnPixelScale(owner, fn) scaleListeners[owner] = fn end

function UI.PixelScaleChanged()
    readScale()
    for texture, kind in pairs(strokes) do
        if kind == "h1" or kind == "w1" then
            applyStroke(texture, 1, nil, kind == "w1" and "width" or "height")
        else
            applyStroke(texture, nil, strokeUnits[texture], kind == "w" and "width" or "height")
        end
    end
    UI.PlacedAgain()
    for owner, fn in pairs(scaleListeners) do fn(owner) end
end

if type(CreateFrame) == "function" then
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", function() UI.PixelScaleChanged() end)
end
