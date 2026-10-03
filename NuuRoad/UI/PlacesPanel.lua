local _, ns = ...

-- The editor's Places tab: the guide's caves, tunnels and one-door
-- buildings, each a handful of points and the connections between them,
-- which the travel arrow follows instead of walking through rock (TRAVEL.md,
-- "Guide places"). Walking a cave into a place is the place recorder's job
-- (UI/PlaceRecorder.lua, Record here); this tab is for fixing what it made
-- and for places built by hand: Add point here drops a point where the author
-- stands, two selected points are joined, parted, or made a one-way drop, and
-- each point is an entrance, an exit, or inside, with a label and an ID. The
-- place is drawn on the world map while the tab is open, so a bad point shows.
--
-- The edits themselves are Domain/PlaceEditing.lua; this file is the controls,
-- built from NuuKit's widgets into the editor's Places page. The world map drawing is plain frames on the
-- map's canvas, which no kit widget covers.
local PlacesPanel = { pins = {}, lines = {} }

local function editing() return ns.modules.PlaceEditing end

local function kindWord(kind)
    if kind == "entrance" then return "Entrance" end
    if kind == "exit" then return "Exit" end
    return "Inside"
end

local function pointText(place, index)
    local point = place.points[index]
    local out, into = editing().Neighbours(place, index)
    local parts = {}
    if point.label then table.insert(parts, point.label) end
    if point.id then table.insert(parts, "[" .. point.id .. "]") end
    if point.kind then table.insert(parts, point.kind) end
    table.insert(parts, string.format("%.1f, %.1f", point.at[1], point.at[2]))
    if #out > 0 then table.insert(parts, "> " .. table.concat(out, ", ")) end
    if #into > 0 then table.insert(parts, "< " .. table.concat(into, ", ") .. " (one-way)") end
    return table.concat(parts, "  ")
end

-- The widgets' callbacks ------------------------------------------------------------------

local function pointMake(row)
    row.marker = row:Text{ "", style = "label", width = 14 }
    row.words = row:Text{ "", grow = true }
end

local function pointDraw(row, item)
    local panel = PlacesPanel
    local place = panel:Place()
    if not place or not place.points[item.index] then
        row.marker:SetText("")
        row.words:SetText("")
        return
    end
    local index = item.index
    row.marker:SetText((index == panel.selected and "A") or (index == panel.second and "B") or "")
    row.words:SetText(pointText(place, index))
end

local function pointPicked(item) PlacesPanel:ClickPoint(item.index) end
local function placePaged(at) PlacesPanel:SelectPlace(at) end
local function placeAdded() PlacesPanel:AddPlace() end
local function placeDeleted() PlacesPanel:DeletePlace() end
local function fieldCommitted() PlacesPanel:ApplyFields(); PlacesPanel:Render() end
local function kindClicked() PlacesPanel:CycleKind() end
local function addHere() PlacesPanel:AddPointHere() end
local function recordClicked() PlacesPanel:OpenRecorder() end
local function deletePoint() PlacesPanel:DeletePoint() end
local function connectBoth() PlacesPanel:Connect(false) end
local function connectOneWay() PlacesPanel:Connect(true) end
local function disconnect() PlacesPanel:Disconnect() end
local function redraw() PlacesPanel:DrawMap() end

-- Builds the tab's controls into the editor's Places page.
function PlacesPanel:Build(editor, page)
    self.editor, self.frame, self.page = editor, editor.win, page
    page:Text{ "Places the arrow finds its way through", style = "label" }
    page:Text{ "A cave or tunnel as points joined by connections. Steps inside are led in by an entrance and out by"
        .. " the best way, and a step can stand on a point by its ID in the Destination tab.",
        style = "fine", color = "muted", wrap = true }

    self.pager = page:Pager{ caption = "Place", count = 0, onChange = placePaged, onAdd = placeAdded,
        onDelete = placeDeleted }

    local ids = page:Row{ gap = 8 }
    self.placeID = ids:Input{ label = "ID (one word)", width = 130, placeholder = "windfury", onChange = fieldCommitted }
    self.placeName = ids:Input{ label = "Name in the tracker", grow = true, placeholder = "Windfury cave",
        onChange = fieldCommitted }
    self.placeWidth = ids:Input{ label = "Width (yd)", width = 90, placeholder = "20", onChange = fieldCommitted }

    page:Text{ "Points: click to select, shift-click a second", style = "label" }
    self.list = page:List{ grow = true, rows = 5, rowHeight = 20, numbers = true, make = pointMake, draw = pointDraw,
        onPick = pointPicked, empty = "No points yet." }

    local point = page:Row{ gap = 8, valign = "bottom" }
    self.pointLabel = point:Input{ label = "Label (\"Go to ...\")", width = 190, placeholder = "the gallery",
        onChange = fieldCommitted }
    self.pointID = point:Input{ label = "ID (for steps)", width = 130, placeholder = "chamber", onChange = fieldCommitted }
    self.kindButton = point:Button{ "Inside", width = 100, onClick = kindClicked,
        tooltip = "Inside, an entrance (walk in or out), or an exit (out only: a hole, a drop - put it where the player lands)." }

    local make = page:Row{ gap = 4 }
    make:Button{ "Add point here", onClick = addHere, tooltip = "A point where you stand, joined to the selected point." }
    self.recordButton = make:Button{ "Record", onClick = recordClicked,
        tooltip = "Walk this place with the place recorder, a window of its own, and the editor put away. A selected"
            .. " point is where the walk starts from." }
    make:Button{ "Delete point", onClick = deletePoint, tooltip = "Remove the selected point and its connections." }

    local join = page:Row{ gap = 4 }
    join:Button{ "Connect", onClick = connectBoth, tooltip = "Join the two selected points, both ways." }
    join:Button{ "One-way", onClick = connectOneWay,
        tooltip = "Join them from the first selected to the second only, like a drop off a ledge." }
    join:Button{ "Disconnect", onClick = disconnect, tooltip = "Part the two selected points." }

    self.problems = page:Text{ "", style = "fine", color = "muted", wrap = true }

    -- The map drawing follows the world map: shown, or another map on it.
    if not self.mapHooked then
        local map = rawget(_G, "WorldMapFrame")
        if map and map.HookScript then
            self.mapHooked = true
            map:HookScript("OnShow", redraw)
            local secureHook = rawget(_G, "hooksecurefunc")
            if map.OnMapChanged and type(secureHook) == "function" then
                pcall(secureHook, map, "OnMapChanged", redraw)
            end
        end
    end
end

function PlacesPanel:Guide() return self.editor and self.editor.working end

-- Another guide opened in the editor: start from its first place.
function PlacesPanel:Reset()
    self.placeIndex, self.selected, self.second, self.renderedPlace, self.renderedPoint = 1, nil, nil, nil, nil
end

function PlacesPanel:Place()
    local guide = self:Guide()
    return guide and guide.places and guide.places[self.placeIndex or 1]
end

function PlacesPanel:SetStatus(text, isError)
    if self.editor then
        self.editor:SetStatus(text, isError)
        self.editor.statusPinned = isError and true or self.editor.statusPinned
    end
end

-- Stores what the author typed into the selected place and point.
function PlacesPanel:ApplyFields()
    local place = self:Place()
    -- The fields hold what was last drawn; after the editor opens another
    -- guide they belong to nothing until the tab draws again.
    if not place or not self.placeID or place ~= self.renderedPlace then return end
    local id = self.placeID:GetText()
    if id ~= place.place then
        local ok, problem = editing().RenamePlace(self:Guide(), place, id)
        if not ok then self:SetStatus(problem, true) end
    end
    local name = self.placeName:GetText()
    place.name = (name ~= nil and name:match("%S")) and name or nil
    local width = tonumber(self.placeWidth:GetText())
    place.width = width and math.floor(width + 0.5) or nil
    local point = self.selected and place.points[self.selected]
    if point and point == self.renderedPoint then
        local text = self.pointLabel:GetText()
        point.label = (text ~= nil and text:match("%S")) and text or nil
        local pointID = self.pointID:GetText()
        if pointID ~= nil and pointID:match("%S") then
            if pointID:find("[%.%s]") or tonumber(pointID) then
                self:SetStatus("A point ID is one word, without a dot, and not a number.", true)
            else
                point.id = pointID
            end
        else
            point.id = nil
        end
    end
end

function PlacesPanel:SelectPlace(index)
    local guide = self:Guide()
    local count = guide and guide.places and #guide.places or 0
    if count == 0 then self.placeIndex = 1; return self:Render() end
    self:ApplyFields()
    self.placeIndex = math.max(1, math.min(count, index))
    self.selected, self.second = nil, nil
    self:Render()
end

function PlacesPanel:AddPlace()
    self:ApplyFields()
    local guide = self:Guide()
    if not guide then return end
    local map = ns.modules.Client:GetCurrentMapID()
    editing().AddPlace(guide, map)
    self.placeIndex, self.selected, self.second = #guide.places, nil, nil
    self:Render()
end

function PlacesPanel:DeletePlace()
    local place = self:Place()
    if not place then return end
    local ok, problem = editing().DeletePlace(self:Guide(), place.place)
    if not ok then return self:SetStatus(problem, true) end
    self.placeIndex, self.selected, self.second = 1, nil, nil
    self:Render()
end

-- The player's position as map percentages, and in world yards for the
-- recorder.
local function playerSpot()
    local Client = ns.modules.Client
    local map = Client:GetCurrentMapID()
    if not map then return nil end
    local x, y = Client:GetPlayerMapPosition(map)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local _, wx, wy = Client:GetWorldPosition(map, x, y)
    return map, x * 100, y * 100, wx, wy
end

function PlacesPanel:AddPointHere()
    self:ApplyFields()
    if not self:Guide() then return end
    local place = self:Place()
    if not place then self:AddPlace(); place = self:Place() end
    local map, x, y = playerSpot()
    if not map then return self:SetStatus("The game does not say where you are standing.", true) end
    place.map = place.map or map
    self.selected = editing().AddPoint(place, map, x, y, self.selected)
    if #place.points == 1 then place.points[1].kind = "entrance" end
    self.second = nil
    self:Render()
end

-- The recorder extends this place in this guide, from the selected point.
function PlacesPanel:OpenRecorder()
    self:ApplyFields()
    if not self:Guide() then return end
    if not self:Place() then self:AddPlace() end
    local Recorder = ns.modules.PlaceRecorder
    if not Recorder then return end
    Recorder:Open({ guide = self:Guide(), place = self:Place(), from = self.selected })
    self.editor:Hide()
end

function PlacesPanel:DeletePoint()
    local place = self:Place()
    if not place or not self.selected then return end
    local ok, problem = editing().DeletePoint(self:Guide(), place, self.selected)
    if not ok then return self:SetStatus(problem, true) end
    self.selected, self.second = nil, nil
    self:Render()
end

function PlacesPanel:CycleKind()
    local place = self:Place()
    local point = place and self.selected and place.points[self.selected]
    if not point then return end
    self:ApplyFields()
    editing().CycleKind(point)
    self:Render()
end

function PlacesPanel:Connect(oneWay)
    local place = self:Place()
    if not place or not self.selected or not self.second then
        return self:SetStatus("Select a point, then shift-click a second one.", true)
    end
    local ok, problem = editing().Connect(place, self.selected, self.second, oneWay)
    if not ok then self:SetStatus(problem, true) end
    self:Render()
end

function PlacesPanel:Disconnect()
    local place = self:Place()
    if not place or not self.selected or not self.second then
        return self:SetStatus("Select a point, then shift-click a second one.", true)
    end
    local ok, problem = editing().Disconnect(place, self.selected, self.second)
    if not ok then self:SetStatus(problem, true) end
    self:Render()
end

-- A click selects a point; a shift-click adds a second to the first.
function PlacesPanel:ClickPoint(index)
    self:ApplyFields()
    local shift = ns.modules.Client:IsShiftDown()
    if shift and self.selected and self.selected ~= index then
        self.second = index
    else
        self.selected, self.second = index, nil
    end
    self:Render()
end

-- What the schema says about this place, and the repeated connections it
-- will merge, in the tab's footer.
function PlacesPanel:Problems(place)
    local errors = {}
    ns.modules.Schema:ValidatePlaces({ places = { place }, nodes = {} }, errors)
    local _, _, duplicates = ns.modules.Schema:PlaceConnections(place)
    local lines = {}
    for index = 1, math.min(3, #errors) do
        table.insert(lines, (errors[index]:gsub("^guide%.places%[1%]%.?", "")))
    end
    if #duplicates > 0 then table.insert(lines, #duplicates .. " connection(s) repeat another; they are merged.") end
    return lines, #errors
end

function PlacesPanel:Render()
    if not self.list then return end
    local guide = self:Guide()
    local count = guide and guide.places and #guide.places or 0
    self.placeIndex = math.max(1, math.min(count, self.placeIndex or 1))
    local place = self:Place()
    self.renderedPlace = place
    self.pager:SetCount(count)
    self.pager:SetAt(self.placeIndex)
    self.placeID:SetText(place and place.place or "")
    self.placeName:SetText(place and place.name or "")
    self.placeWidth:SetText(place and place.width and tostring(place.width) or "")
    local points = place and place.points or {}
    if self.selected and not points[self.selected] then self.selected = nil end
    if self.second and not points[self.second] then self.second = nil end
    local items = self.items or {}
    self.items = items
    for index = 1, #points do
        local item = items[index] or {}
        item.index = index
        items[index] = item
    end
    for index = #items, #points + 1, -1 do items[index] = nil end
    self.list:SetItems(items, true)
    self.list:Select(self.selected and items[self.selected] or nil)
    local point = self.selected and points[self.selected]
    self.renderedPoint = point
    self.pointLabel:SetText(point and point.label or "")
    self.pointID:SetText(point and point.id or "")
    self.kindButton:SetText(point and kindWord(point.kind) or "Inside")
    self.kindButton:SetEnabled(point ~= nil, "Select a point first.")
    if place then
        local lines, errors = self:Problems(place)
        self.problems:SetColor(errors > 0 and "danger" or "muted")
        self.problems:SetText(#lines > 0 and table.concat(lines, "\n")
            or (#points .. " points. Steps inside it are led in and out through its entrances."))
    else
        self.problems:SetColor("muted")
        self.problems:SetText("Add a place, or press Add point here at a cave mouth to start one.")
    end
    self:DrawMap()
end

------------------------------------------------------------------------------
-- The place on the world map, while the tab or the recorder is open.

function PlacesPanel:HideMap()
    for _, pin in ipairs(self.pins) do pin:Hide() end
    for _, line in ipairs(self.lines) do if line then line:Hide() end end
end

local function acquireLine(self, canvas, index)
    local line = self.lines[index]
    if line == false then return nil end
    if not line then
        if type(canvas.CreateLine) ~= "function" then self.lines[index] = false; return nil end
        local ok, created = pcall(canvas.CreateLine, canvas, nil, "OVERLAY")
        if not ok or not created then return nil end
        line = created
        line:SetThickness(2)
        line:SetColorTexture(1, 1, 1, 1)
        self.lines[index] = line
    end
    return line
end

-- The place on the map: the one the recorder is walking while it is open,
-- else the one on this tab while the tab is open.
function PlacesPanel:MapPlace()
    local Recorder = ns.modules.PlaceRecorder
    local recorded = Recorder and Recorder:ShownPlace()
    if recorded then return recorded end
    if self.frame and self.frame:IsShown() and self.editor and self.editor.activeTab == "places" then return self:Place() end
    return nil
end

function PlacesPanel:DrawMap()
    local map = rawget(_G, "WorldMapFrame")
    local place = self:MapPlace()
    if not map or not map:IsShown() or not map.GetCanvas or not place then
        return self:HideMap()
    end
    local canvas = map:GetCanvas()
    local mapID = map:GetMapID()
    local width, height = canvas:GetSize()
    if not canvas or not width or width <= 0 then return self:HideMap() end
    local tokens = ns:GetUI().tokens
    local accent, danger, plain = tokens.accent, tokens.danger, tokens.text
    local spots = {}
    local pinCount = 0
    for index, point in ipairs(place.points) do
        if (point.map or place.map) == mapID then
            local x, y = point.at[1] / 100 * width, point.at[2] / 100 * height
            spots[index] = { x = x, y = y }
            pinCount = pinCount + 1
            local pin = self.pins[pinCount]
            if not pin or pin:GetParent() ~= canvas then
                pin = CreateFrame("Frame", nil, canvas)
                pin:SetSize(14, 14)
                pin.dot = pin:CreateTexture(nil, "ARTWORK")
                pin.dot:SetAllPoints()
                pin.dot:SetColorTexture(1, 1, 1, 1)
                pin.text = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                pin.text:SetPoint("LEFT", pin, "RIGHT", 3, 0)
                self.pins[pinCount] = pin
            end
            pin:SetFrameLevel(canvas:GetFrameLevel() + 130)
            local color = point.kind == "entrance" and accent or (point.kind == "exit" and danger or plain)
            pin.dot:SetVertexColor(color[1], color[2], color[3], 1)
            pin.text:SetTextColor(plain[1], plain[2], plain[3], 1)
            local words = { tostring(index) }
            if point.id then table.insert(words, "[" .. point.id .. "]") end
            if point.label then table.insert(words, point.label) end
            pin.text:SetText(table.concat(words, " "))
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
            pin:Show()
        end
    end
    for index = pinCount + 1, #self.pins do self.pins[index]:Hide() end
    local lineCount = 0
    local function draw(from, to, r, g, b)
        lineCount = lineCount + 1
        local line = acquireLine(self, canvas, lineCount)
        if not line then return end
        line:SetStartPoint("TOPLEFT", canvas, from.x, -from.y)
        line:SetEndPoint("TOPLEFT", canvas, to.x, -to.y)
        line:SetVertexColor(r, g, b, 0.9)
        line:Show()
    end
    local P = editing().PointIndex
    for _, connection in ipairs(place.connections) do
        local a, b = spots[P(place, connection[1])], spots[P(place, connection[2])]
        if a and b then
            draw(a, b, accent[1], accent[2], accent[3])
            if connection[3] == true then
                -- An arrowhead two thirds along, pointing the way it may be walked.
                local dx, dy = b.x - a.x, b.y - a.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    local ux, uy = dx / length, dy / length
                    local tip = { x = a.x + dx * 0.66, y = a.y + dy * 0.66 }
                    local size = 6
                    draw(tip, { x = tip.x - ux * size + uy * size, y = tip.y - uy * size - ux * size }, danger[1], danger[2], danger[3])
                    draw(tip, { x = tip.x - ux * size - uy * size, y = tip.y - uy * size + ux * size }, danger[1], danger[2], danger[3])
                end
            end
        end
    end
    for index = lineCount + 1, #self.lines do
        if self.lines[index] then self.lines[index]:Hide() end
    end
end

ns:RegisterModule("PlacesPanel", PlacesPanel)
