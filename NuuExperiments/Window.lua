local _, ns = ...

-- The experiments window (/nuux): every loaded experiment and how it last
-- went on the left, the chosen one's results on the right, with Run, Copy
-- and Clear. Results of retired experiments (kept until /nuux prune) are
-- listed after the loaded ones. Like the copy window, it is the kit's
-- (Show.lua's ns:UI()); the experiments never see it.

local Window = {}
ns.Window = Window

local TONES = {
    ok = "success", error = "danger", timeout = "warning", replaced = "warning", running = "accent",
}

-- One entry per loaded experiment, then one per retired result.
local function items()
    local results, list = ns:DB().results, {}
    for _, id in ipairs(ns.order) do
        list[#list + 1] = { id = id, name = id, experiment = ns.experiments[id], result = results[id] }
    end
    local retired = {}
    for id in pairs(results) do
        if not ns.experiments[id] then retired[#retired + 1] = id end
    end
    table.sort(retired)
    for _, id in ipairs(retired) do
        list[#list + 1] = { id = id, name = id, result = results[id], retired = true }
    end
    return list
end

local function statusOf(item)
    if item.retired then return "retired", nil end
    if not item.result then return "not run", nil end
    local status = tostring(item.result.status)
    return status, TONES[status]
end

local function autoOf(experiment)
    if not experiment then return "retired" end
    if experiment.auto == false then return "only by hand" end
    if experiment.auto == "login" then return "runs at every login" end
    return "runs once per client build"
end

-- The list --------------------------------------------------------------------------------

local function makeRow(row)
    row.name = row:Text{ "", grow = true }
    row.status = row:Tag{ "" }
end

local function drawRow(row, item)
    row.name:SetText(item.id)
    local status, tone = statusOf(item)
    row.status:SetText(status)
    row.status:SetTone(tone)
end

local function rowTooltip(item)
    local title = item.experiment and item.experiment.title or (item.result and item.result.title)
    return title and tostring(title) or nil
end

local function picked(item)
    Window.selected = item.id
    Window:Draw()
end

-- The buttons -----------------------------------------------------------------------------

local function runClicked()
    local id = Window.selected
    if id and ns.experiments[id] then ns:Run(id) end
end

local function copyClicked()
    if Window.selected then ns:ShowResults({ Window.selected }) end
end

local function clearClicked()
    local id = Window.selected
    if not id then return end
    ns:DB().results[id] = nil
    Window:Refresh()
    Window.win:Status("Forgot the results of " .. id .. ".")
end

local function runAllClicked()
    for _, id in ipairs(ns.order) do ns:Run(id) end
end

local function pruneClicked()
    local count = ns:Prune()
    Window.win:Status(count == 0 and "No retired results to forget."
        or ("Forgot " .. count .. " retired result" .. (count == 1 and "" or "s") .. "."))
end

-- Building --------------------------------------------------------------------------------

function Window:Build()
    local ui = ns:UI()
    if not ui then return false end
    local db = ns:DB()
    db.windows = db.windows or {}
    local win = ui:Window({
        key = "experiments", place = db.windows, title = "Experiments",
        width = 780, height = 540, resizable = true, minWidth = 560, minHeight = 340,
        status = true, hidden = true,
    })
    self.win = win
    win.header:Button{ "Run all", tooltip = "Runs every loaded experiment now", onClick = runAllClicked }
    win.header:Button{ "Prune", tooltip = "Forgets the results of experiments no longer loaded",
        onClick = pruneClicked }

    local panes = win:SplitPanes{
        { key = "list", width = 250, min = 180, padding = 8 },
        { key = "details", grow = true, min = 300, padding = 12, gap = 8 },
        place = db.windows, key = "experiments.panes",
    }
    self.list = panes.list:List{
        grow = true, rowHeight = 26, make = makeRow, draw = drawRow, onPick = picked,
        tooltip = rowTooltip, empty = "No experiments loaded.",
    }

    local details = panes.details
    self.details = details
    self.title = details:Text{ "", style = "heading", wrap = true }
    self.meta = details:Text{ "", style = "label", wrap = true }
    local buttons = details:Row{ gap = 8 }
    self.run = buttons:Button{ "Run", tone = "accent", onClick = runClicked }
    self.copy = buttons:Button{ "Copy", tooltip = "Opens the results selected, to copy with Ctrl-C",
        onClick = copyClicked }
    self.clear = buttons:ConfirmButton{ "Clear", onConfirm = clearClicked }
    details:Rule{}
    self.area = details:ScrollArea{ grow = true, gap = 4 }
    self.body = self.area:Text{ "", wrap = true }
    return true
end

-- Drawing ---------------------------------------------------------------------------------

-- The list again, keeping its place and the experiment chosen.
function Window:Refresh()
    if not self.win then return end
    local list = items()
    self.list:SetItems(list, true)
    local chosen
    for _, item in ipairs(list) do
        if item.id == self.selected then chosen = item end
    end
    if not chosen then chosen = list[1] end
    self.selected = chosen and chosen.id
    if chosen then self.list:Select(chosen) end
    self:Draw()
end

function Window:Draw()
    local item = self.list:GetSelected()
    if not item then
        self.details:SetState("empty", "No experiments loaded and no results kept.")
        return
    end
    self.details:SetState(nil)
    local experiment, result = item.experiment, item.result
    self.title:SetText((experiment and experiment.title) or (result and result.title) or item.id)

    local status = statusOf(item)
    local meta = item.id .. ", " .. autoOf(experiment) .. (experiment and experiment.combat and ", in combat too" or "")
    if result then
        meta = meta .. "\n" .. string.format("%s: build %s, interface %s, %s, %s, %sms%s", status,
            tostring(result.build), tostring(result.interface), tostring(result.date), tostring(result.character),
            tostring(result.ms), result.inCombat and ", in combat" or "")
        if result.errors then
            meta = meta .. ", " .. #result.errors .. " error" .. (#result.errors == 1 and "" or "s")
        end
    end
    self.meta:SetText(meta)

    self.run:SetEnabled(experiment ~= nil and not ns.running[item.id],
        experiment and "Running now." or "Retired: put its file back in the TOC to run it.")
    self.copy:SetEnabled(result ~= nil, "Not run yet.")
    self.clear:SetEnabled(result ~= nil and not ns.running[item.id], "Nothing to clear.")
    self.body:SetText(result and table.concat(ns.WriteResult({}, result), "\n") or "Not run yet.")
    -- Back to the top for another experiment, not when this one changes.
    if self.drawn ~= item.id then self.area:ScrollToTop() end
    self.drawn = item.id
end

-- Opening ---------------------------------------------------------------------------------

-- Opens the window, on `id` when given; false when the kit is not loaded.
function ns:OpenWindow(id)
    if not Window.win and not Window:Build() then return false end
    if id then Window.selected = id end
    Window:Refresh()
    Window.win:Show()
    return true
end

-- Something changed (a run started or ended, results forgotten): an open
-- window shows it.
function ns:Changed()
    if Window.win and Window.win:IsShown() then Window:Refresh() end
end
