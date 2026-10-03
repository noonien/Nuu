local _, ns = ...

-- The guide's shopping list, beside the tracker: everything the steps from
-- here to the end ask the player to bring (or to the end of the section, for
-- a guide listed by section), grouped by where it comes from, with what is
-- still missing from their bags. A material the player already carries
-- enough of stays on the list, ticked, so a glance says the whole trip is
-- covered rather than leaving the reader to wonder what dropped off.
--
-- It is a list and nothing more. No price is read, no auction is searched or
-- posted, and no vendor is bought from: the player does the shopping.
--
-- An in-play kit panel (UI:Panel), as tall as its list. Until the player
-- drags it by its band it follows the tracker, at its right; once moved it
-- stays where it was put (NuuRoadDB.windows.materials).
local MaterialsPanel = { rows = {} }

local WIDTH = 240
local groupWords = {
    gather = "Gather", drop = "From drops", craft = "Craft yourself", vendor = "From a vendor", ah = "Auction house",
}

local function Config() return ns.modules.Config end

function MaterialsPanel:Enabled()
    return Config():Get("materials.shown") == true and Config():Get("tracker.shown") == true
end

function MaterialsPanel:Create()
    if self.frame then return end
    local ui = ns:GetUI()
    local win = ui:Panel({ key = "materials", place = ns.db.windows, title = "Materials",
        width = WIDTH, height = 60, hidden = true })
    self.summary = win.header:Text{ "", style = "fine" }
    self.list = win:Column{ padding = 8, gap = 2 }
    self.frame = win
end

function MaterialsPanel:Initialize()
    self:Create()
    self:Anchor()
end

-- Beside the tracker, following it, until the player places it. The tracker
-- grows (down, or up) as a step changes, so the list sits to its right
-- rather than past it, level with the edge that stays put.
function MaterialsPanel:Anchor()
    local tracker = ns.modules.MainWindow and ns.modules.MainWindow.frame
    if not self.frame or not tracker then return end
    local placed = ns.db.windows and ns.db.windows.materials
    if placed and placed.x then return end
    self.frame:ClearAllPoints()
    if tracker.IsUpward and tracker:IsUpward() then
        self.frame:SetPoint("BOTTOMLEFT", tracker, "BOTTOMRIGHT", 6, 0)
    else
        self.frame:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 6, 0)
    end
end

-- The shape of the list: its groups and items in order. The same shape is
-- repainted in place; another is built again.
local function shapeOf(entries)
    local parts = {}
    for _, entry in ipairs(entries) do parts[#parts + 1] = tostring(entry.source) .. ":" .. tostring(entry.itemID) end
    return table.concat(parts, ",")
end

function MaterialsPanel:Build(entries)
    local list = self.list
    list:Clear()
    self.rows = {}
    local group
    for index, entry in ipairs(entries) do
        if entry.source ~= group then
            group = entry.source
            list:Text{ groupWords[group] or "Gather", style = "fine" }
        end
        local row = list:Row{ gap = 6 }
        self.rows[index] = {
            row = row,
            check = row:Text{ "", style = "fine", width = 16 },
            name = row:Text{ "", grow = true },
            count = row:Text{ "", style = "fine" },
        }
    end
    self.shape = shapeOf(entries)
end

-- As tall as the list, under the band.
function MaterialsPanel:Fit()
    local win = self.frame
    ns.Kit.UI.LayoutNow()
    local inset = win.kitInset or 1
    local band = win.band:IsShown() and win.band:GetHeight() or 0
    local height = self.list:NaturalHeight(WIDTH - 2 * inset) + band + 2 * inset
    win:SetHeight(math.ceil(height))
end

function MaterialsPanel:Refresh()
    if not self.frame then return end
    local Progress = ns.modules.Progress
    local guide = Progress and Progress.store and Progress:GetActiveGuide()
    if not self:Enabled() or not guide then self:HideAll(); return end
    local Materials, Names = ns.modules.Materials, ns.modules.Names
    -- Nothing is outstanding past the end of the guide.
    local from = Progress:GetCurrentIndex(guide)
    local entries = from and Materials:Outstanding(guide, from) or {}
    if #entries == 0 then self:HideAll(); return end
    self:Anchor()
    local _, section = Materials:ListEnd(guide, from)
    self.frame:SetTitle(section and section.title or "Materials")
    local rebuilt = shapeOf(entries) ~= self.shape
    if rebuilt then self:Build(entries) end
    local missing = 0
    for index, entry in ipairs(entries) do
        local row = self.rows[index]
        local enough = entry.short == 0
        if not enough then missing = missing + 1 end
        row.check:SetText(enough and "[x]" or "[ ]")
        row.name:SetText(Names:DescribeItem(entry.itemID))
        row.name:SetColor(enough and "done" or "text")
        row.count:SetText(math.min(entry.have, entry.count) .. "/" .. entry.count)
        row.row:SetAlpha(enough and 0.6 or 1)
    end
    self.summary:SetText(missing == 0 and "all carried" or (missing .. " still needed"))
    self.frame:SetScale(Config():Get("tracker.scale") or 1)
    self.frame:Show()
    if rebuilt then self:Fit() end
end

function MaterialsPanel:HideAll()
    if self.frame then self.frame:Hide() end
end

-- What these settings refresh, and the tracker's own: the list follows the tracker's visibility and scale.
function MaterialsPanel:OnSettingChanged(path)
    if path == "tracker.upward" then self:Anchor() end
    if path:sub(1, 10) == "materials." or path == "tracker.shown" or path == "tracker.scale" then
        self:Refresh()
    end
end

ns:RegisterModule("MaterialsPanel", MaterialsPanel)
