local _, ns = ...

-- The Plan changes panel: the change history of the plan on screen
-- (Domain/PlanChanges.lua), newest first, in a small panel of its own. Each
-- entry is when, why (the player's change, a price, the skill, a recipe
-- learned, the bags) and what it did to the plan. The history only tells:
-- nothing here takes a change back. Opened by the planner's Changes button;
-- it follows the profession the planner shows.
local View = {}

local WIDTH, MAX_HEIGHT = 380, 520

local function Changes() return ns.modules.PlanChanges end
local function Planner() return ns.modules.PlannerPanel end

-- When an entry was made: the time today, the day too before that.
local function when(at)
    local date = rawget(_G, "date")
    local clock = rawget(_G, "time")
    if type(date) ~= "function" or not at or at == 0 then return "" end
    local today = type(clock) == "function" and date("%Y-%m-%d", clock()) or nil
    if today and date("%Y-%m-%d", at) ~= today then return date("%d %b %H:%M", at) end
    return date("%H:%M", at)
end

function View:Create()
    if self.frame then return end
    local ui = ns:GetUI()
    local places = ns.db and ns.db.windows
    local win = ui:Panel({ key = "planChanges", place = places, title = "Plan changes", width = WIDTH, height = 80,
        collapsible = true, close = true, hidden = true,
        point = { "RIGHT", rawget(_G, "UIParent"), "RIGHT", -440, 60 } })
    -- The planner's Changes button shows whether the panel is up.
    local function told() if Planner() and Planner().ChangesShown then Planner():ChangesShown(win:IsShown()) end end
    win:HookScript("OnShow", told)
    win:HookScript("OnHide", told)
    self.area = win:ScrollArea{ padding = 12, padRight = 12 - (ns.Kit.UI.SCROLLBAR or 10), gap = 10 }
    self.frame = win
    ui:OnLook(function() self:Refresh() end)
end

-- As tall as the entries, up to MAX_HEIGHT, past which it scrolls.
function View:Fit()
    local win = self.frame
    ns.Kit.UI.LayoutNow()
    if win:IsCollapsed() then return end
    local inset = win.kitInset or 1
    local band = win.band:IsShown() and win.band:GetHeight() or 0
    local inner = WIDTH - 2 * inset - (ns.Kit.UI.SCROLLBAR or 0)
    local _, tall = self.area.kitInner:Measure(inner)
    local strip = win.statusStrip and win.statusStrip:IsShown() and win.statusStrip:GetHeight() or 0
    win:SetHeight(math.ceil(math.min(MAX_HEIGHT, (tall or 0) + band + strip + 2 * inset)))
end

-- Draws the history of the planner's profession again.
function View:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local panel = Planner()
    local profession = panel and panel.profession
    local store = panel and panel:Store()
    local entries = (profession and store and Changes()) and Changes():Entries(store, profession) or {}
    local names = panel:ChangeNames()
    local area = self.area
    area:Clear()
    area:Text{ profession or "No profession planned yet", style = "label" }
    if #entries == 0 then
        area:Text{ "No changes yet. Each time the plan changes, what changed and why is listed here.",
            color = "muted", wrap = true }
    end
    for _, entry in ipairs(entries) do
        local cause, lines = Changes():Words(entry, names)
        -- The time leads the cause in one paragraph: a row measures its
        -- texts unwrapped, so a wrapping one stays in a column.
        local block = area:Column{ gap = 3 }
        local stamp = when(entry.at)
        block:Text{ (stamp ~= "" and (panel:Tint(stamp, "muted") .. "  ") or "") .. cause, wrap = true }
        local list = block:Column{ gap = 2, padLeft = 12 }
        for _, line in ipairs(lines) do list:Text{ line, style = "fine", wrap = true } end
    end
    self.frame:Status(#entries > 0 and (#entries .. " of the last " .. Changes().limit .. " changes kept") or nil)
    self:Fit()
end

function View:SetShown(shown)
    self:Create()
    if shown then
        self.frame:Show()
        self:Refresh()
    else
        self.frame:Hide()
    end
end

function View:Toggle()
    self:SetShown(not self:IsShown())
end

function View:IsShown()
    return self.frame ~= nil and self.frame:IsShown() or false
end

ns:RegisterModule("PlanChangesView", View)
