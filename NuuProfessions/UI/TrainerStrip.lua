local _, ns = ...

-- Training from the plan at a trainer: a strip of ours under the game's
-- trainer window, while the trainer teaches something a plan needs. It says
-- which plan ("From your Tailoring plan"), has Train all with what
-- everything trainable now costs, and a row per service: the tier training
-- the route passes and the trainer recipes its steps use, each with its fee
-- and Train (Domain/TrainerTraining.lua), or, when the trainer will not teach
-- it yet, the skill or level it asks for. What the plan does not need is
-- not on the strip. The services the plan needs also wear a mark on the
-- trainer's own list: an accent edge down the row's left side.
--
-- The strip and the marks are our frames, parented to the trainer window's;
-- nothing of the game's is changed. The marks are painted after the game
-- draws its list (ClassTrainerFrame_Update and the list's ScrollBox Update,
-- hooked), so a scroll moves them with it.
local Strip = { badges = {} }

-- The Train button, or in its place when the trainer will not teach it yet
-- what it asks for ("at skill 125").
local TRAIN_WIDTH = 80

local function Client() return ns.modules.Client end
local function Training() return ns.modules.TrainerTraining end

local function after(seconds, callback)
    local timer = rawget(_G, "C_Timer")
    if type(timer) == "table" and type(timer.After) == "function" then timer.After(seconds, callback) else callback() end
end

local function money(copper) return ns.Kit.FormatMoney(math.floor(copper + 0.5)) end

-- The strip -----------------------------------------------------------------------------

local function trainClicked(button)
    local line = button.data
    if line and line.need then Strip:Train({ line.need }) end
end

local function trainAllClicked()
    if Strip.lines then Strip:Train(Strip.lines) end
end

function Strip:Train(lines)
    local ok, why = Training():StartAll(lines, function() Strip:Changed() end)
    if not ok and why then ns:Print(why) end
    self:Refresh()
end

function Strip:Create(trainer)
    if self.frame then return end
    local ui = ns:GetUI()
    local win = ui:Panel({ parent = trainer, width = math.floor(trainer:GetWidth() or 338), height = 60, hidden = true,
        point = { "TOPLEFT", trainer, "BOTTOMLEFT", 0, -2 } })
    self.body = win:Column{ padding = 8, gap = 4 }
    self.frame = win
    ui:OnLook(function() self.shape = nil; self:Refresh() end)
end

function Strip:Build(profession, lines)
    local body = self.body
    body:Clear()
    self.rows = {}
    local head = body:Row{ gap = 8 }
    head:Text{ "From your " .. profession .. " plan", style = "fine", grow = true, valign = "center" }
    self.trainAll = head:Button{ "Train all", tone = "accent", height = 22, onClick = trainAllClicked,
        tooltip = "Trains everything the plan needs that this trainer can teach now, one after the other" }
    for _, need in ipairs(lines) do
        local row = body:Row{ gap = 8 }
        local line = { need = need }
        line.name = row:Text{ "", grow = true, valign = "center" }
        line.cost = row:Text{ "", style = "number", valign = "center" }
        if need.available then
            line.train = row:Button{ "Train", width = TRAIN_WIDTH, height = 20, onClick = trainClicked, data = line,
                tooltip = function(tip) tip:SetText(line.tip or "", 1, 1, 1, 1, true) end }
        else
            line.why = row:Text{ "", color = "muted", width = TRAIN_WIDTH, valign = "center" }
        end
        table.insert(self.rows, line)
    end
end

-- As tall as what it holds.
function Strip:Fit()
    local win = self.frame
    ns.Kit.UI.LayoutNow()
    local inset = win.kitInset or 1
    local height = self.body:NaturalHeight((win:GetWidth() or 0) - 2 * inset) + 2 * inset
    win:SetHeight(math.ceil(height))
end

-- What a row's Train says it does.
local function tipOf(need)
    if need.kind == "tier" then
        return "Trains " .. need.name .. " for " .. money(need.cost) .. ": the skill can then go to " .. need.cap .. "."
    end
    return "Learns " .. need.name .. " for " .. money(need.cost) .. ". The plan makes it from skill " .. need.skill .. "."
end

function Strip:Refresh()
    local trainer = rawget(_G, "ClassTrainerFrame")
    local profession, lines = Training():AtTrainer()
    self.lines = lines
    self:HookList()
    self:PaintBadges()
    if type(trainer) ~= "table" or not profession or #lines == 0 then
        if self.frame then self.frame:Hide() end
        return
    end
    self:Create(trainer)
    local parts = { profession }
    for _, need in ipairs(lines) do parts[#parts + 1] = tostring(need.key) .. (need.available and "+" or "-") end
    local shape = table.concat(parts, ",")
    local rebuilt = shape ~= self.shape
    if rebuilt then
        self:Build(profession, lines)
        self.shape = shape
    end
    local training, have, total = Training(), Client():GetMoney(), 0
    for index, line in ipairs(self.rows) do
        local need = lines[index]
        line.need = need
        line.name:SetText(need.name)
        line.cost:SetText(money(need.cost))
        if line.train then
            total = total + need.cost
            line.tip = tipOf(need)
            local reason = (training:Busy() and "Training, one at a time")
                or (have < need.cost and ("You have " .. money(have))) or nil
            line.train:SetEnabled(reason == nil, reason)
        else
            line.why:SetText(need.why or "")
        end
    end
    self.trainAll:SetText(total > 0 and ("Train all " .. money(total)) or "Train all")
    local reason = (training:Busy() and "Training, one at a time")
        or (total == 0 and "Nothing the plan needs can be trained here yet")
        or (have < total and ("You have " .. money(have))) or nil
    self.trainAll:SetEnabled(reason == nil, reason)
    self.frame:Show()
    if rebuilt then self:Fit() end
end

-- The marks on the trainer's list ---------------------------------------------------------

-- The service a row of the trainer's list shows: the list's element data
-- (a ScrollBox list: the index, or a table holding it), else the row's ID
-- (the older list of ClassTrainerSkill buttons).
local function serviceIndex(row)
    if type(row.GetElementData) == "function" then
        local ok, data = pcall(row.GetElementData, row)
        if ok and type(data) == "number" then return data end
        if ok and type(data) == "table" then
            local index = tonumber(data.index or data.skillIndex or data.serviceIndex)
            if index then return index end
        end
    end
    local index = tonumber(row.skillIndex) or (type(row.GetID) == "function" and tonumber(row:GetID()))
    return index and index > 0 and index or nil
end

-- Every row the trainer's list shows now.
local function listRows()
    local rows = {}
    local trainer = rawget(_G, "ClassTrainerFrame")
    local box = type(trainer) == "table" and trainer.ScrollBox
    if type(box) == "table" and type(box.ForEachFrame) == "function" then
        pcall(box.ForEachFrame, box, function(row) table.insert(rows, row) end)
        return rows
    end
    local shown = tonumber(rawget(_G, "CLASS_TRAINER_SKILLS_DISPLAYED")) or 11
    for slot = 1, shown do
        local row = rawget(_G, "ClassTrainerSkill" .. slot)
        if type(row) == "table" then table.insert(rows, row) end
    end
    return rows
end

-- One mark per row of the list, made the first time: an accent edge down
-- its left side.
function Strip:Badge(row)
    local badge = self.badges[row]
    if badge then return badge end
    badge = CreateFrame("Frame", nil, row)
    badge:SetAllPoints(row)
    badge:SetFrameLevel((row:GetFrameLevel() or 0) + 5)
    badge.edge = badge:CreateTexture(nil, "OVERLAY")
    badge.edge:SetPoint("TOPLEFT", badge, "TOPLEFT", 0, 0)
    badge.edge:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 0, 0)
    badge.edge:SetWidth(3)
    self.badges[row] = badge
    return badge
end

function Strip:PaintBadges()
    local needed = {}
    local api = Client()
    if api and api.trainerOpen then
        for _, need in ipairs(self.lines or {}) do needed[need.index] = true end
    end
    local t = ns:GetUI().tokens
    for _, row in ipairs(listRows()) do
        local index = row.IsShown and row:IsShown() and serviceIndex(row)
        if index and needed[index] then
            local badge = self:Badge(row)
            ns.Kit.UI.TexColor(badge.edge, t.accent)
            badge:Show()
        elseif self.badges[row] then
            self.badges[row]:Hide()
        end
    end
end

-- The trainer's list is load on demand (Blizzard_TrainerUI): hooked the
-- first time its window is there.
function Strip:HookList()
    local hook = rawget(_G, "hooksecurefunc")
    if type(hook) ~= "function" then return end
    local paint = function() Strip:PaintBadges() end
    if not self.hookedUpdate and type(rawget(_G, "ClassTrainerFrame_Update")) == "function" then
        self.hookedUpdate = pcall(hook, "ClassTrainerFrame_Update", paint)
    end
    local trainer = rawget(_G, "ClassTrainerFrame")
    local box = type(trainer) == "table" and trainer.ScrollBox
    if not self.hookedBox and type(box) == "table" and type(box.Update) == "function" then
        self.hookedBox = pcall(hook, box, "Update", paint)
    end
end

-- Events -----------------------------------------------------------------------------------

-- A trainer opening, its list, the money, a skill, a recipe learned and a
-- new plan change the strip; a burst of them repaints once.
function Strip:Changed()
    if self.pending then return end
    self.pending = true
    after(0.2, function()
        self.pending = false
        self:Refresh()
    end)
end

function Strip:Initialize()
    if Training() then Training().onKeep = function() Strip:Changed() end end
    if type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_MONEY", "SKILL_LINES_CHANGED",
        "NEW_RECIPE_LEARNED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function() self:Changed() end)
    self.eventFrame = frame
end

ns:RegisterModule("TrainerStrip", Strip)
