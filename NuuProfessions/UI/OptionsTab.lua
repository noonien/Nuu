local _, ns = ...

-- The planner's Options tab: the tuning, in three sections (the route,
-- shopping, prices), the testing switch in a fourth, and the window's look
-- at the foot. Each option is a kit Setting: what it is and what it does on
-- the left, its control on the right, and a reset while the player's choice
-- is stored. Every choice goes through panel:Change, so the route is planned
-- again at once and the status strip offers Undo. The tab scrolls when the
-- window is too short for it.
--
-- An option is stored only once the player chooses it (Planner:Option).
-- Reset all at the foot forgets every choice on the tab.
--
-- Ported from OpenRoad's UI/PlannerOptions.lua; the Appearance section is
-- new, since the planner wears its own look (the kit keeps none).
local Tab = { key = "options", caption = "Options", hint = "Every change plans the route again at once." }

local LABEL_WIDTH = 420
local SELECT_WIDTH = 260

local function Planner() return ns.modules.ProfessionPlanner end
local function Client() return ns.modules.Client end

-- Auctionator is another addon; when it is loaded, the client adapter reads
-- the prices it scanned at the auction house (docs/api-compatibility.md).
local function hasAuctionator()
    local api = Client()
    return api and type(api.Has) == "function" and api:Has("auctionator") or false
end

local function default(key)
    local defaults = Planner().defaultOptions or {}
    return defaults[key]
end

-- The choices of each drop-down: the option's value, its caption, and a
-- second line saying what it does.
local CHOICES = {
    optimize = {
        { value = "cost", caption = "Lowest cost", desc = "What you sell is shown but never picks a recipe" },
        { value = "profit", caption = "Most profit", desc = "A recipe whose output pays back can win" },
    },
    sellOutput = {
        { value = "chosen", caption = "Only items I choose", desc = "Set per item in Materials, Sale" },
        { value = "all", caption = "Everything", desc = "All you make is sold, where it pays most" },
    },
    confidence = {
        { value = "typical", caption = "Typical, the expected count", desc = "Short about half the time" },
        { value = "safe", caption = "Safe, enough 9 runs in 10", desc = "Enough about 9 runs in 10" },
        { value = "sure", caption = "Sure, enough 99 runs in 100", desc = "Enough about 99 runs in 100" },
    },
    auction = {
        { value = "both", caption = "Buy and sell", desc = "Buy materials and sell what you make there" },
        { value = "buy", caption = "Buy only", desc = "Buy there; sell to vendors only" },
        { value = "sell", caption = "Sell only", desc = "Sell there; buy from vendors only" },
        { value = "none", caption = "No auction house", desc = "Vendors only, both ways" },
    },
}

-- The caption a drop-down's value wears, and what the status strip says.
local function captionOf(key, value)
    for _, entry in ipairs(CHOICES[key]) do
        if entry.value == value then return entry.caption end
    end
    return tostring(value)
end

-- The rows, section by section. `kind` is the control: a drop-down over
-- CHOICES[option], a checkbox, or the estimate field.
local SECTIONS = {
    { title = "The route", rows = {
        { kind = "select", option = "optimize", label = "Optimise for",
            help = "Lowest cost: what you sell is shown but never picks a recipe. Most profit: a recipe whose"
                .. " output pays back can win." },
        { kind = "select", option = "sellOutput", label = "Count as sold",
            help = "Which things you make earn money back. Each item can differ in Materials, Sale." },
    } },
    { title = "Shopping", rows = {
        { kind = "select", option = "confidence", label = "Confidence",
            help = "How many spare materials the shopping list carries." },
        { kind = "select", option = "auction", label = "Auction house",
            help = "Where materials may be bought and what you make sold." },
        { kind = "toggle", option = "useBags", label = "Bags", caption = "Use what I carry first",
            help = "What you carry is used before buying more, counted at what it would sell for." },
    } },
    { title = "Prices", rows = {
        { kind = "estimate", option = "estimateFactor", label = "Guess unpriced items at",
            help = "An item nobody priced is guessed from what a vendor pays for it." },
        { kind = "toggle", option = "useAuctionator", label = "Auctionator", caption = "Use Auctionator prices",
            help = "Prices it scanned this session stand in where you typed none. Yours always win." },
    } },
    -- One switch for the character, not a profession's option: it lives in
    -- the planner's character record (Panel:SetFullScope).
    { title = "Testing", rows = {
        { kind = "toggle", option = "fullScope", character = true, label = "Plan past the level cap",
            caption = "Plan past the beta's level cap",
            help = "Uses every recipe up to 300, Artisan training, and ignores the level trainers ask for. For"
                .. " testing long routes: the route can need materials this beta does not have yet." },
    } },
}

local AUCTIONATOR_MISSING = "Install the Auctionator addon and visit the auction house with it to use real auction"
    .. " prices here."
local SESSION_LINE = "These settings are kept for this character, one set per profession; the testing switch is"
    .. " one for every profession. Only what you change is kept: the rest follows the defaults."

-- A row's default in words, for its reset's tooltip.
local function defaultText(spec)
    local value = default(spec.option)
    if spec.kind == "select" then return captionOf(spec.option, value) end
    if spec.kind == "estimate" then return tostring(value) .. " x" end
    if spec.character then return "off" end
    return value and "on" or "off"
end

-- Whether the row's setting is stored: the player chose it.
local function isStored(panel, spec)
    if spec.character then return panel:FullScope() end
    return panel.inputs ~= nil and panel.inputs.options[spec.option] ~= nil
end

-- Forgets the choices of `rows`, as one change the strip can take back. The
-- testing switch is the character's, and goes off on its own.
function Tab:Reset(panel, rows, message)
    local options = {}
    for _, row in ipairs(rows) do
        if row.spec.character then
            if panel:FullScope() then panel:SetFullScope(false) end
        else
            table.insert(options, row.spec.option)
        end
    end
    if #options == 0 then return end
    panel:Change("reset", function(inputs)
        for _, option in ipairs(options) do inputs.options[option] = nil end
    end, function(before, after) return message .. panel:NetChange(before, after) end)
end

-- Building ---------------------------------------------------------------------------------

-- A change to one option, as the player made it.
function Tab:SetOption(spec, value)
    local panel = self.panel
    if not panel.inputs then return end
    local key = spec.option
    panel:Change(key, function(inputs) inputs.options[key] = value end, function(before, after)
        local said
        if spec.kind == "select" then
            said = spec.label .. ": " .. captionOf(key, value) .. "."
        elseif spec.kind == "estimate" then
            said = "Unpriced items are guessed at " .. tostring(value or default(key) or 4) .. " x the vendor price."
        else
            said = spec.caption .. ": " .. (value and "on" or "off") .. "."
        end
        return said .. panel:NetChange(before, after)
    end)
end

local function buildControl(self, row)
    local spec, setting = row.spec, row.setting
    if spec.kind == "select" then
        row.control = setting:Select{ boxWidth = SELECT_WIDTH, options = CHOICES[spec.option],
            onChange = function(value) self:SetOption(spec, value) end }
    elseif spec.kind == "toggle" then
        row.control = setting:Toggle{ spec.caption, onChange = function(on)
            if spec.character then
                self.panel:SetFullScope(on)
            else
                self:SetOption(spec, on)
            end
        end }
    elseif spec.kind == "estimate" then
        row.control = setting:Input{ width = 80, placeholder = tostring(default("estimateFactor") or 4),
            validate = function(text)
                local value = tonumber(text)
                if text:match("^%s*$") or (value and value > 0) then return nil end
                return "A number, such as 4 or 2.5; empty for the default."
            end,
            onChange = function(text) self:SetOption(spec, tonumber(text)) end }
        setting:Text{ "x the vendor price", style = "label" }
    end
end

function Tab:Build(panel, page)
    self.panel = panel
    local area = page:ScrollArea{ grow = true, gap = 14, padding = 4 }
    self.area = area
    self.rows = {}
    for _, section in ipairs(SECTIONS) do
        local box = area:Section{ section.title, gap = 0 }
        for _, spec in ipairs(section.rows) do
            local row = { spec = spec }
            row.setting = box:Setting{ spec.label, help = spec.help, labelWidth = LABEL_WIDTH, default = defaultText(spec),
                onReset = function() self:Reset(panel, { row }, spec.label .. ": back to the default ("
                    .. defaultText(spec) .. ").") end }
            buildControl(self, row)
            table.insert(self.rows, row)
        end
    end
    area:Text{ SESSION_LINE, style = "label", wrap = true }
    area:ConfirmButton{ "Reset all", tooltip = "Every option on this tab back to its default for this profession, and"
        .. " the testing switch off. What you chose is forgotten. Click twice to confirm.",
        onConfirm = function() self:Reset(panel, self.rows, "Every option back to its default.") end }

    -- The planner's look: its own, kept in NuuProfessionsDB.look.
    local looks = area:Section{ "Appearance", hint = "the planner window's theme, accent and text" }
    looks:LookPicker{ look = ns.db and ns.db.look, onChange = function(look)
        if ns.db then ns.db.look = look end
        panel:UI():SetLook(look)
    end }
end

-- Another profession: its own options, from the top.
function Tab:OnProfession()
    if self.area then self.area:ScrollToTop() end
end

-- Rendering --------------------------------------------------------------------------------

function Tab:Fill(panel, row)
    local spec, control = row.spec, row.control
    local options = panel.inputs.options
    if spec.kind == "select" then
        local current = options[spec.option]
        if current == nil then current = default(spec.option) end
        control:SetValue(current)
    elseif spec.kind == "toggle" then
        if spec.option == "useAuctionator" then
            local present = hasAuctionator()
            control:SetEnabled(present, AUCTIONATOR_MISSING)
            control:SetText(present and spec.caption or (spec.caption .. " (not installed)"))
            control:SetValue(present and options.useAuctionator ~= false)
            row.setting.help:SetText(present and spec.help or AUCTIONATOR_MISSING)
        elseif spec.character then
            control:SetValue(panel:FullScope())
        else
            control:SetValue(options[spec.option] ~= false)
        end
    elseif spec.kind == "estimate" then
        if not control:HasFocus() and not control:IsInvalid() then
            local value = options.estimateFactor
            control:SetText(value and tostring(value) or "")
        end
    end
    row.setting:SetChanged(isStored(panel, spec))
end

function Tab:Render(panel)
    if not panel.inputs then return end
    for _, row in ipairs(self.rows) do self:Fill(panel, row) end
end

ns:RegisterModule("PlannerTabOptions", Tab)
