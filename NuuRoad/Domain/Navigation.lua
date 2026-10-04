local _, ns = ...

-- Map-local navigation. A location remains useful prose when the client
-- cannot expose player position or facing.
local Navigation = { updateInterval = 0.25, poiInterval = 0.1 }
local fallbackAspectRatio = 0.66 -- Used only when the client cannot report a map's world size.

-- Conventions (WoW API):
--   * Normalized map X grows east, Y grows south.
--   * GetPlayerFacing() is radians counter-clockwise from north.
--   * The arrow angle is radians counter-clockwise, zero being dead ahead.
-- So the arrow angle is the counter-clockwise bearing to the target minus
-- the player's facing. `east` and `north` are already in comparable units.
local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    return math.atan(y, x)
end

Navigation.Atan2 = atan2

-- Eight-point compass bearing of a north-up delta, for prose like "320 yd NE".
function Navigation.CompassBearing(east, north)
    if east == 0 and north == 0 then return nil end
    local degrees = (math.deg(atan2(east, north)) + 360) % 360
    local points = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    return points[math.floor((degrees + 22.5) / 45) % 8 + 1]
end

function Navigation.RelativeAngle(east, north, facing)
    return atan2(-east, north) - (facing or 0)
end

function Navigation.ShortestAngle(from, to)
    return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- Converts a normalized-map delta into yards when the client can size the map.
-- Falls back to normalized units with the conventional aspect correction.
-- The arrow is a pre-rendered turn on a sprite sheet rather than one flat
-- texture spun in place: every frame is the solid arrow lit from a fixed
-- light, so the highlights slide across it as it turns, which is what makes it
-- read as an object rather than a shape. The sheet holds a half turn only; the
-- other half is the same frames mirrored, which is exact because both the
-- arrow and its light are symmetric about the arrow's long axis. That leaves
-- about 1.2 degrees per frame. See Tools/GenerateArrowSprites.js.
local arrowSheet = { columns = 10, rows = 15, spriteWidth = 102, spriteHeight = 68, sheetSize = 1024 }
arrowSheet.frames = arrowSheet.columns * arrowSheet.rows
Navigation.arrowSheet = arrowSheet

-- The sprite is a perspective view of the arrow, so it is wider than it is
-- tall. The centre stays where the old square arrow's centre was, which keeps
-- the window's layout and the player's muscle memory intact.
local arrowWidth, arrowHeight = 60, 40
local arrowCentreX, arrowCentreY = 32, 32

-- Frame index for a rotation, 0-based, and whether it is a mirrored one.
function Navigation.SpriteFrame(angle)
    local degrees = math.deg(angle) % 360
    local mirrored = degrees > 180
    if mirrored then degrees = 360 - degrees end
    return math.floor(degrees / 180 * (arrowSheet.frames - 1) + 0.5), mirrored
end

-- Texture coordinates in the order SetTexCoord(left, right, top, bottom) takes
-- them; a mirrored frame comes back with left and right swapped.
function Navigation.SpriteCoords(angle)
    local index, mirrored = Navigation.SpriteFrame(angle)
    local column = index % arrowSheet.columns
    local row = math.floor(index / arrowSheet.columns)
    local left = column * arrowSheet.spriteWidth / arrowSheet.sheetSize
    local right = (column + 1) * arrowSheet.spriteWidth / arrowSheet.sheetSize
    local top = row * arrowSheet.spriteHeight / arrowSheet.sheetSize
    local bottom = (row + 1) * arrowSheet.spriteHeight / arrowSheet.sheetSize
    if mirrored then return right, left, top, bottom end
    return left, right, top, bottom
end

-- The window swaps the arrow out for an icon whenever pointing somewhere is
-- not the useful answer, rather than leaving the arrow spinning or hiding the
-- window: that is what the established guide addons do, and an icon that says
-- "you are here" reads faster than an arrow pointing at the player's feet.
-- Only the states NuuRoad can actually detect are here. Some guide addons
-- also have boat, pathfinding-wait, stairs, and instance-preview icons; a
-- boat has no API to detect it, we do no pathfinding, the schema carries no
-- floor for a step, and we show no instance preview, so those would be icons
-- nothing could ever set.
-- See Tools/GenerateArrowSpecials.js.
local specialSheet = { cell = 64, width = 256, height = 64 }
local specialCells = { arrived = 0, taxi = 1, unreachable = 2 }
local specialSize = 34

function Navigation.SpecialCoords(state)
    local cell = specialCells[state]
    if not cell then return nil end
    local left = cell * specialSheet.cell / specialSheet.width
    return left, left + specialSheet.cell / specialSheet.width, 0, specialSheet.cell / specialSheet.height
end

-- Which face the window shows. The order is the point: on a taxi the player is
-- not steering, so the arrow has nothing to say even with the destination in
-- reach; with no comparable position there is nothing to point at; and arrival
-- beats travel.
function Navigation.ArrowState(context)
    if not context.hasLocation then return "none" end
    if context.onTaxi then return "taxi" end
    if not context.hasBearing then return "unreachable" end
    if context.arrived then return "arrived" end
    return "traveling"
end

-- Heading colour, the signal the established guide addons settled on: red when
-- the target is behind, amber across, green when it is ahead, plus a flat
-- bright snap over the last few degrees so "dead on" is unmistakable without
-- reading the distance line.
local arrowGradient = {
    { at = 0, 0.90, 0.22, 0.18 },
    { at = 0.5, 0.95, 0.72, 0.22 },
    { at = 1, 0.35, 0.85, 0.35 },
}
local arrowSnapColor = { 0.45, 1.00, 0.40 }
local arrowSnapAngle = math.rad(4)

function Navigation.ArrowColor(angle)
    local off = math.abs(Navigation.ShortestAngle(0, angle))
    if off <= arrowSnapAngle then
        return arrowSnapColor[1], arrowSnapColor[2], arrowSnapColor[3]
    end
    local position = 1 - off / math.pi -- 0 behind, 1 ahead.
    for index = 2, #arrowGradient do
        local from, to = arrowGradient[index - 1], arrowGradient[index]
        if position <= to.at then
            local span = to.at - from.at
            local blend = span > 0 and (position - from.at) / span or 0
            return from[1] + (to[1] - from[1]) * blend,
                from[2] + (to[2] - from[2]) * blend,
                from[3] + (to[3] - from[3]) * blend
        end
    end
    local last = arrowGradient[#arrowGradient]
    return last[1], last[2], last[3]
end

function Navigation.WorldDelta(dx, dy, worldWidth, worldHeight)
    if worldWidth and worldHeight then
        return dx * worldWidth, dy * worldHeight, true
    end
    return dx, dy * fallbackAspectRatio, false
end

-- A step's radius is authored as a fraction of the map, which is the unit the
-- map pin and the audit want, but far too generous for "Arrived" on a
-- zone-sized map: 5% of the Barrens is over 300 yards. Once the map's size is
-- known, arrival means being within 7 yards of the spot, a little past the
-- game's own interaction range so the pin appears as the player walks up
-- rather than only once they stop on the exact spot; an authored radius
-- tighter than that is kept.
local maxArrivalYards = 7

function Navigation.ArrivalRadius(normalized, worldWidth, worldHeight)
    local radius = tonumber(normalized)
    if not radius then return nil end
    if not worldWidth or not worldHeight then return radius end
    return math.min(maxArrivalYards, radius * math.max(worldWidth, worldHeight))
end

-- Reclaiming a corpse works from some way off (about forty yards in the
-- classic game), so that is where the corpse arrow says it has arrived.
local corpseArrivalYards = 40
-- A typed-in waypoint is reached, and put away, within this many yards, the
-- way TomTom clears one on arrival.
local waypointArrivalYards = 10

-- The arrow's stand-in step while the player is a ghost: a plain travel node
-- at the corpse, shaped like a guide step so the tracker code needs no
-- special case. Nil without a position.
function Navigation.CorpseNode(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return {
        kind = "travel",
        title = "Your corpse",
        location = { mapID = mapID, x = x, y = y, arrivalYards = corpseArrivalYards },
    }
end

-- A place typed after `/nr way`, the way TomTom's /way takes one: two numbers
-- are X and Y as map percentages ("45.2 60.1", "45.2, 60.1"), and a third in
-- front of them is a map ID ("1413 45.2 60.1"). Returns the map ID or nil,
-- then X and Y normalized; or nil, nil, nil and why not.
function Navigation.ParseWaypoint(text)
    local numbers = {}
    for number in tostring(text or ""):gmatch("%d+%.?%d*") do numbers[#numbers + 1] = tonumber(number) end
    local mapID, x, y
    if #numbers == 2 then
        x, y = numbers[1], numbers[2]
    elseif #numbers == 3 then
        mapID, x, y = math.floor(numbers[1]), numbers[2], numbers[3]
    else
        return nil, nil, nil, "Usage: /nr way [mapID] <x> <y>, for example /nr way 45.2 60.1"
    end
    if x > 100 or y > 100 then return nil, nil, nil, "X and Y are percentages, 0 to 100" end
    return mapID, x / 100, y / 100
end

-- The typed-in place as a node, shaped like a guide step the way the corpse
-- is. No index, so its map pin is a bead rather than a step number.
function Navigation.WaypointNode(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return {
        kind = "travel",
        title = string.format("Waypoint %.1f, %.1f", x * 100, y * 100),
        bead = "accent",
        location = { mapID = mapID, x = x, y = y, arrivalYards = waypointArrivalYards },
    }
end

-- Sets the waypoint from what the player typed, on the map they are on unless
-- the text names one. Returns true, or false and why not.
function Navigation:SetWaypointFromText(text)
    local mapID, x, y, problem = Navigation.ParseWaypoint(text)
    if not x then return false, problem end
    local Client = ns.modules.Client
    mapID = mapID or (Client and Client:GetCurrentMapID())
    if not mapID then return false, "The game does not say which map you are on; put its map ID first" end
    self.waypoint = Navigation.WaypointNode(mapID, x, y)
    self:Retarget()
    return true
end

-- Sets the waypoint from code (the travel test panel), with its own title.
function Navigation:SetWaypoint(mapID, x, y, title)
    local node = Navigation.WaypointNode(mapID, x, y)
    if not node then return false end
    if title then node.title = title end
    self.waypoint = node
    self:Retarget()
    return true
end

function Navigation:ClearWaypoint()
    if not self.waypoint then return end
    -- A route RouteTo asked for is put away with it.
    local Route = ns.modules.TravelRoute
    if Route and Route.requested == self.waypoint then Route.requested = nil end
    self.waypoint = nil
    self:Retarget()
end

-- What the arrow points at: the corpse while the player is a ghost (the guide
-- can wait, so the arrow swaps to a corpse arrow first), then a waypoint the
-- player typed in, else the tracked step. A ghost whose corpse
-- the client cannot place keeps the waypoint or the step.
function Navigation:Target()
    if self.ghost then
        local corpse = self:FindCorpse()
        if corpse then return corpse end
    end
    return self.waypoint or self.activeNode
end

-- The corpse as a node, looked up once per death: on the map the player is
-- on, then on the map they died on (a ghost may run through another zone).
function Navigation:FindCorpse()
    if self.corpse then return self.corpse end
    local Client = ns.modules.Client
    if not Client or not Client.GetCorpseMapPosition then return nil end
    local tried = {}
    for _, mapID in ipairs({ Client:GetCurrentMapID(), self.deathMap }) do
        if mapID and not tried[mapID] then
            tried[mapID] = true
            local x, y = Client:GetCorpseMapPosition(mapID)
            local node = Navigation.CorpseNode(mapID, x, y)
            if node then
                self.corpse = node
                return node
            end
        end
    end
    return nil
end

-- Re-reads whether the player is a ghost and re-aims the arrow and pins at
-- whatever that makes the target. Called from the death and life events.
function Navigation:RefreshLifeState()
    local Client = ns.modules.Client
    self.ghost = Client and Client.IsPlayerGhost and Client:IsPlayerGhost() or false
    if not self.ghost then self.corpse = nil end
    self:Retarget()
end

function Navigation:Retarget()
    self.forceAngleUpdate = true
    local node = self:Target()
    -- The travel route follows the step or the typed-in waypoint, never the
    -- corpse: a ghost takes no flight.
    local Route = ns.modules.TravelRoute
    if Route then
        local routed = (node == self.waypoint or node == self.activeNode) and node or nil
        Route:Sync(routed, routed and self.activeGuide or nil)
    end
    self:Update(node)
    self:UpdateWorldMapPOI(node)
    self:UpdateMinimapPOI(node)
end

-- The leg of the travel route the arrow shows for `node`, or nil when it
-- points at the step itself. Watching the leg first lets a leg that has just
-- been walked hand over to the next one in the same beat.
function Navigation:CurrentLeg(node)
    local Route = ns.modules.TravelRoute
    if not Route or not node then return nil end
    local leg = Route:Leg(node)
    if leg then
        Route:Watch(leg)
        leg = Route:Leg(node)
    end
    return leg
end

-- A leg as something the pins can draw: a bead in the accent colour at the
-- leg's end, titled with what the leg says.
function Navigation.LegNode(leg)
    local location = leg and (leg.at or leg.dest)
    if not location then return nil end
    return { kind = "travel", title = leg.text or "Route", bead = "accent", location = location }
end

local function mapWorldSize(mapID)
    if not C_Map or not C_Map.GetMapWorldSize or not mapID then return nil end
    local ok, width, height = pcall(C_Map.GetMapWorldSize, mapID)
    if ok and type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
        return width, height
    end
    return nil
end

local function playerFacing()
    if not GetPlayerFacing then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    if ok then return facing end
    return nil
end

local DOT_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- A pin is a small round bead: a soft shadow underneath, a dark border, a
-- solid red fill, and a small highlight up and to the left so it reads as a
-- raised dot rather than a flat disc. The circle is a stock Blizzard texture;
-- if the client refuses it the dot degrades to a flat square rather than
-- disappearing.
local function createDot(parent, layer, size, r, g, b, a, dx, dy)
    local dot = parent:CreateTexture(nil, layer)
    dot:SetSize(size, size)
    dot:SetPoint("CENTER", dx or 0, dy or 0)
    local set = dot:SetTexture(DOT_TEXTURE)
    if set == false or not dot:GetTexture() then dot:SetTexture("Interface/Buttons/WHITE8x8") end
    dot:SetVertexColor(r, g, b, a)
    return dot
end

-- Map pins are numbered with the step's own index, the number the guide list
-- beside the tracker prints, kept small so they mark a spot without covering
-- the map: the current step is a dark disc with a thin accent ring, the steps
-- after it a smaller translucent disc with no ring, and on the minimap only
-- the outlined number with no backing. A label wider than the disc
-- stretches it into a pill rather than growing a bigger circle. A pin with no
-- number (the corpse) is a small red bead. The discs are the stock round
-- mask, so a client that refuses it gets squares rather than nothing.
-- Sizes are screen pixels: world map pins are held at that size whatever the
-- map's zoom (see LayoutWorldMapPins), the way HereBeDragons' pins are.
local PIN_STYLE = {
    current = { size = 13, font = 9, ring = true, fillAlpha = 0.9, alpha = 1 },
    ahead = { size = 11, font = 8, fillAlpha = 0.6, alpha = 0.9 },
    minimap = { size = 10, font = 9, bare = true, alpha = 1, edgeAlpha = 0.7 },
}
local RING_WIDTH = 1.5

-- A colour of the look the player chose (the kit's tokens), or `fallback`
-- before the UI is made or outside the client.
local function themeColor(name, fallback)
    local ok, ui = pcall(ns.GetUI, ns)
    local color = ok and ui and ui.tokens and ui.tokens[name]
    return color or fallback
end

local function showPinTooltip(pin)
    if not pin.nodes or not GameTooltip then return end
    local Steps = ns.modules.Steps
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText("NuuRoad")
    local accent = themeColor("accent", { 0.3, 0.79, 0.94 })
    for _, node in ipairs(pin.nodes) do
        local title = (Steps and Steps:Title(node)) or node.title or "Guide destination"
        local line = node.index and (node.index .. "  " .. title) or title
        if pin.currentNodes[node] then
            GameTooltip:AddLine(line, accent[1], accent[2], accent[3], true)
        else
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    if #pin.nodes > 1 then
        GameTooltip:AddLine("These steps are close together here.", 0.56, 0.62, 0.7, true)
    end
    if pin.onEdge then
        GameTooltip:AddLine("Beyond the minimap, this way.", 0.56, 0.62, 0.7, true)
    end
    GameTooltip:Show()
end

local function createPin(parent)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetFrameStrata("HIGH")
    -- Hover shows the tooltip; a click goes through to the map underneath,
    -- so a pin never stops the player zooming or pinging.
    pcall(pin.SetMouseClickEnabled, pin, false)
    pin.ring = createDot(pin, "BORDER", 1, 0, 0, 0, 1)
    pin.fill = createDot(pin, "ARTWORK", 1, 0, 0, 0, 1)
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pin.label:SetPoint("CENTER", 0.5, 0)
    pin.label:SetJustifyH("CENTER")
    pin.font = pin.label:GetFont()
    pin.currentNodes = {}
    pin:SetScript("OnEnter", showPinTooltip)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:Hide()
    return pin
end

-- Paints a pin for a cluster from `Navigation.ClusterPins`.
local function paintPin(pin, cluster, style, alpha)
    pin.nodes, pin.currentNodes, pin.onEdge = cluster.nodes, cluster.currentNodes, cluster.onEdge
    local label = Navigation.PinLabel(cluster)
    local accent = themeColor("accent", { 0.3, 0.79, 0.94 })
    local width, height = style.size, style.size
    if label == "" then
        -- The bead: a solid dot with a dark edge, no number. Red for the
        -- corpse, the accent colour for a typed-in waypoint.
        pin.label:Hide()
        width, height = 9, 9
        local node = cluster.nodes[1]
        if node and node.bead == "accent" then
            pin.ring:SetVertexColor(0.02, 0.06, 0.1, 1)
            pin.fill:SetVertexColor(accent[1], accent[2], accent[3], 1)
        else
            pin.ring:SetVertexColor(0.12, 0.02, 0.02, 1)
            pin.fill:SetVertexColor(0.92, 0.12, 0.1, 1)
        end
        pin.ring:Show(); pin.fill:Show()
        pin.ring:SetSize(width, height)
        pin.fill:SetSize(width - 2, height - 2)
    else
        -- The outline keeps the number readable over any map art; a client
        -- that refuses the flag keeps the plain font.
        if not pcall(pin.label.SetFont, pin.label, pin.font, style.font, "OUTLINE") then
            pin.label:SetFont(pin.font, style.font)
        end
        pin.label:SetText(label)
        pin.label:Show()
        width = math.max(width, math.ceil(pin.label:GetStringWidth() or 0) + 4)
        if style.bare then
            pin.ring:Hide(); pin.fill:Hide()
            local color = cluster.current and accent or { 0.9, 0.9, 0.86 }
            pin.label:SetTextColor(color[1], color[2], color[3])
        else
            pin.fill:SetVertexColor(0.04, 0.05, 0.07, style.fillAlpha)
            pin.fill:Show()
            if style.ring then
                pin.ring:SetVertexColor(accent[1], accent[2], accent[3], 1)
                pin.ring:SetSize(width, height)
                pin.ring:Show()
                pin.fill:SetSize(width - 2 * RING_WIDTH, height - 2 * RING_WIDTH)
                pin.label:SetTextColor(1, 1, 1)
            else
                pin.ring:Hide()
                pin.fill:SetSize(width, height)
                pin.label:SetTextColor(0.88, 0.88, 0.84)
            end
        end
    end
    pin:SetSize(width, height)
    pin:SetAlpha(alpha)
end

-- Animations are built in Lua because NuuRoad ships no XML. A client without
-- animation groups still shows the icon, it just sits still.
local function translation(group, order, x, y, duration, smoothing)
    local animation = group:CreateAnimation("Translation")
    animation:SetOrder(order)
    animation:SetOffset(x, y)
    animation:SetDuration(duration)
    animation:SetSmoothing(smoothing)
    return animation
end

local function createAnimation(texture, build)
    if type(texture.CreateAnimationGroup) ~= "function" then return nil end
    local ok, group = pcall(texture.CreateAnimationGroup, texture)
    if not ok or not group then return nil end
    if not pcall(group.SetLooping, group, "REPEAT") then return nil end
    if not pcall(build, group) then return nil end
    return group
end

-- A text on the arrow window: a plain font string the look paints (see
-- paintArrowWindow), in one of the kit's text styles.
local function newText(parent)
    local Kit = ns.Kit
    return Kit.UI.NewText(parent)
end

-- The arrow window's look: the texts in the kit's text styles and colours,
-- and the colour of a special state's icon. Run when the window is made and
-- on every look change (ui:Paint).
local specialColors = { arrived = "done", taxi = "accent", unreachable = "muted" }

local function paintArrowWindow(frame, t)
    local ApplyStyle = ns.Kit.UI.ApplyStyle
    ApplyStyle(frame.destination, "body", t)
    ApplyStyle(frame.status, "body", t, "accent")
    local color = t[specialColors[frame.arrowState or ""] or "text"]
    if color then frame.special:SetVertexColor(color[1], color[2], color[3], 1) end
end

-- Where it stands, as the kit keeps its windows' places
-- (NuuRoadDB.windows.arrow = { x, y }, the top-left corner): saved only once
-- the player drags it, and always anchored by that corner, so a change in
-- height never shifts the arrow.
local function arrowMoved(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    local windows = ns.db and ns.db.windows
    if left and top and windows then
        local entry = windows.arrow or {}
        entry.x, entry.y = math.floor(left + 0.5), math.floor(top + 0.5)
        windows.arrow = entry
    end
    local Route = ns.modules.TravelRoute
    if Route then Route:SyncTeleportButton() end
end

-- Only a shift-held left button moves the arrow.
local function shiftHeld() return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false end
local dragOpts = { can = shiftHeld, onStop = arrowMoved }

-- The window takes the mouse only while shift is down, so a click on it
-- otherwise lands in the world underneath; with shift the whole window is the
-- drag handle. Watched each frame while it shows, since a modifier event may
-- not reach an addon on the beta client.
local function watchShift(watcher)
    local held = shiftHeld()
    if held == watcher.held then return end
    watcher.held = held
    watcher:GetParent():EnableMouse(held)
end

-- The arrow window is the kit's in-play panel (UI:Panel) with no plate or
-- border, so the arrow and its texts float over the world, and no band. The
-- arrow art and its fixed geometry (250 wide, the arrow's centre at 32, 32)
-- are drawn on the panel itself, not in its body.
function Navigation:CreateFrame()
    local ui = ns:GetUI()
    local frame = ui:Panel({ key = "arrow", place = ns.db and ns.db.windows, width = 250, height = 64,
        plate = false, point = { "CENTER", UIParent, "CENTER", 0, 95 } })
    frame:EnableMouse(false)
    ns.Kit.UI.DragFrame(frame, frame, "move", dragOpts)
    local watcher = CreateFrame("Frame", nil, frame)
    watcher.held = false
    watcher:SetScript("OnUpdate", watchShift)
    frame.shiftWatcher = watcher
    frame.arrowGraphic = frame:CreateTexture(nil, "ARTWORK")
    frame.arrowGraphic:SetSize(arrowWidth, arrowHeight)
    frame.arrowGraphic:SetPoint("TOPLEFT", arrowCentreX - arrowWidth / 2, -(arrowCentreY - arrowHeight / 2))
    frame.arrowGraphic:SetTexture("Interface\\AddOns\\NuuRoad\\Art\\ArrowSprites.tga")
    -- The specular pass, added over the base. The base carries the heading
    -- colour and the sheen stays white, so the arrow reads as lit metal rather
    -- than a tinted silhouette. OVERLAY rather than an ARTWORK sub-level so the
    -- draw order does not depend on a texture sub-level argument the beta
    -- client may not honour; nothing else in the window overlaps it.
    frame.arrowSheen = frame:CreateTexture(nil, "OVERLAY")
    frame.arrowSheen:SetAllPoints(frame.arrowGraphic)
    frame.arrowSheen:SetTexture("Interface\\AddOns\\NuuRoad\\Art\\ArrowSpritesSpecular.tga")
    frame.arrowSheen:SetBlendMode("ADD")
    frame.arrowSheen:SetAlpha(0.7)
    -- Shown in place of the arrow for the states above, on the same centre.
    frame.special = frame:CreateTexture(nil, "ARTWORK")
    frame.special:SetSize(specialSize, specialSize)
    -- Anchored to the window, not to the arrow, since the arrow is hidden
    -- whenever this shows.
    frame.special:SetPoint("CENTER", frame, "TOPLEFT", arrowCentreX, -arrowCentreY)
    frame.special:SetTexture("Interface\\AddOns\\NuuRoad\\Art\\ArrowSpecials.tga")
    frame.special:Hide()
    -- The hearthstone or teleport spell, shown in the arrow's place on a
    -- teleport leg; the click is a secure button over it.
    frame.teleportIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.teleportIcon:SetSize(36, 36)
    frame.teleportIcon:SetPoint("CENTER", frame, "TOPLEFT", arrowCentreX, -arrowCentreY)
    frame.teleportIcon:Hide()
    frame.specialAnimations = {
        -- The pin hops the way a dropped marker settles; the wing bobs slowly,
        -- rising quicker than it falls.
        arrived = createAnimation(frame.special, function(group)
            translation(group, 1, 0, 9, 0.3, "OUT")
            translation(group, 2, 0, -9, 0.3, "IN")
        end),
        taxi = createAnimation(frame.special, function(group)
            translation(group, 1, 0, 3, 0.3, "OUT")
            translation(group, 2, 0, -3, 1.0, "IN")
        end),
    }
    -- Label wraps to the right of the arrow inside the fixed width; the
    -- distance sits under the arrow. The arrow itself never moves.
    frame.destination = newText(frame)
    frame.destination:SetPoint("LEFT", frame.arrowGraphic, "RIGHT", 8, 0)
    frame.destination:SetPoint("RIGHT", -8, 0)
    frame.destination:SetWordWrap(true)
    frame.destination:SetMaxLines(3)
    -- Distance column under the arrow, centered on the arrow's axis. It takes
    -- its text's natural width up to a cap, then wraps rather than spilling.
    frame.status = newText(frame)
    frame.status:SetPoint("TOP", frame.arrowGraphic, "BOTTOM", 0, -2)
    frame.statusMaxWidth = 80
    frame.status:SetWordWrap(true)
    frame.status:SetMaxLines(3)
    frame.status:SetJustifyH("CENTER")
    -- A right-click on the arrow opens its menu: the routes on offer, and a
    -- typed-in waypoint to put away. The route itself is not written out;
    -- the arrow shows it one leg at a time. The arrow's patch lets the left
    -- button through (to the world, or with shift to the window under it);
    -- where the client cannot, it takes the shift drag itself.
    local hit = CreateFrame("Frame", nil, frame)
    hit:SetSize(arrowWidth, arrowHeight)
    hit:SetPoint("CENTER", frame, "TOPLEFT", arrowCentreX, -arrowCentreY)
    hit:EnableMouse(true)
    if not (hit.SetPassThroughButtons and pcall(hit.SetPassThroughButtons, hit, "LeftButton")) then
        ns.Kit.UI.DragFrame(hit, frame, "move", dragOpts)
    end
    ns.Kit.UI.OnRightClick(hit, function() self:OpenMenu() end)
    frame.menuHit = hit
    frame:Hide()
    self.frame = frame
    -- The texts and the special icon follow the look. Keyed on a text, not
    -- the window: the window's own chrome is already painted under its name.
    ui:Paint(frame.destination, function(t) paintArrowWindow(frame, t) end)

    -- The driver is never hidden, so pins and the tracker distance keep
    -- updating even when the standalone arrow window is turned off.
    local driver = CreateFrame("Frame")
    driver.sinceUpdate, driver.sincePOI = 0, 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        if not self.activeNode and not self.ghost and not self.waypoint then return end
        driver.sinceUpdate = driver.sinceUpdate + elapsed
        driver.sincePOI = driver.sincePOI + elapsed
        if driver.sinceUpdate >= self.updateInterval then
            driver.sinceUpdate = 0
            self:Update(self:Target())
        end
        if driver.sincePOI >= self.poiInterval then
            driver.sincePOI = 0
            self:UpdateMinimapPOI(self:Target())
        end
        if frame:IsShown() then self:AnimateArrow(elapsed) end
    end)
    self.driver = driver
end

-- The arrow's menu: the routes on offer to pick between (or a greyed line
-- saying there is none, so a right-click always answers), and a way to put a
-- typed-in waypoint away.
function Navigation:MenuItems()
    local node = self:Target()
    local items = {}
    local Route, Travel = ns.modules.TravelRoute, ns.modules.Travel
    local choices, current
    if Route then choices, current = Route:Choices(node) end
    for _, choice in ipairs(choices or {}) do
        table.insert(items, { caption = choice.outline, group = "route", value = choice.id, checked = choice.id == current,
            desc = Travel and ("~" .. Travel.FormatSeconds(choice.cost)) or nil })
    end
    if not choices then table.insert(items, { caption = "No other route to pick", disabled = true }) end
    if self.waypoint then
        table.insert(items, { separator = true })
        table.insert(items, { caption = "Clear waypoint", onClick = function() self:ClearWaypoint() end })
    end
    return items
end

local function routePicked(_, id)
    local Route = ns.modules.TravelRoute
    if not Route then return end
    Route:PickChoice(Navigation:Target(), id)
    Navigation.forceAngleUpdate = true
    Navigation:Update(Navigation:Target())
end

local menuOpts = { at = "cursor", onChange = routePicked }

function Navigation:OpenMenu()
    ns:GetUI():OpenMenu(self:MenuItems(), menuOpts)
end

-- The steps that get a pin on the world map, in the order the guide reaches
-- them: the step the player is on and the rest of its authored group, then up
-- to `ahead` more steps that name a place, showing the next few steps ahead.
-- Steps already done are left off; one waiting on a quest the player
-- does not have keeps its pin, since the guide stops there. The walk stops at a choice: which way the
-- route goes from there is the player's call, so no branch is drawn for them.
function Navigation:PinSteps(guide, node, ahead)
    local steps, seen = {}, {}
    if not node then return steps end
    local function add(candidate, current)
        if not candidate or seen[candidate] or not candidate.location then return false end
        seen[candidate] = true
        steps[#steps + 1] = { node = candidate, current = current }
        return true
    end
    add(node, true)
    local Progress, GuideScan = ns.modules.Progress, ns.modules.GuideScan
    if not guide or not guide.nodes or not Progress then return steps end
    local state = Progress:PeekState(guide)
    local function passedOver(candidate)
        if not GuideScan then return false end
        return GuideScan:IsStepDone(guide, candidate, state)
    end
    for _, member in ipairs(Progress:QuestGroup(guide, node)) do
        if member ~= node and not passedOver(member) then add(member, true) end
    end
    local found, candidate = 0, node
    for _ = 1, #guide.nodes do
        if found >= (ahead or 0) or (candidate.choices and #candidate.choices > 0) then break end
        local nextIndex = Progress:NextIndex(guide, candidate)
        candidate = nextIndex and guide.nodes[nextIndex]
        if not candidate then break end
        if not seen[candidate] and not passedOver(candidate) and add(candidate, false) then found = found + 1 end
    end
    return steps
end

-- Every point of a step is a pin with the step's number: they are equal
-- places to go. `points` arrive in guide order, so the step the player is on
-- always leads. A point within `radius` of an earlier pin joins it instead of
-- drawing over it; a pin carrying more than one step reads "12+" for a
-- crowded spot, and its tooltip lists them all. Distances
-- are in whatever units the caller placed the points in. A `solo` point (the
-- corpse) neither joins nor takes in another.
function Navigation.ClusterPins(points, radius)
    local clusters = {}
    local limit = (radius or 0) * (radius or 0)
    for _, point in ipairs(points) do
        local home
        if not point.solo then
            for _, cluster in ipairs(clusters) do
                local dx, dy = point.x - cluster.x, point.y - cluster.y
                if not cluster.solo and dx * dx + dy * dy < limit then home = cluster; break end
            end
        end
        if not home then
            home = { x = point.x, y = point.y, rank = point.rank or 0, onEdge = point.onEdge, nodes = {}, seen = {}, currentNodes = {}, solo = point.solo }
            clusters[#clusters + 1] = home
        end
        if not home.seen[point.node] then
            home.seen[point.node] = true
            home.nodes[#home.nodes + 1] = point.node
        end
        if point.current then
            home.current = true
            home.currentNodes[point.node] = true
        end
    end
    return clusters
end

-- The earliest step's number, with "+" when the pin carries more steps.
function Navigation.PinLabel(cluster)
    local label = ""
    for _, node in ipairs(cluster.nodes) do
        if node.index then label = tostring(node.index); break end
    end
    if label ~= "" and #cluster.nodes > 1 then label = label .. "+" end
    return label
end

-- Pins further down the route fade a little, so the eye finds the next one.
function Navigation.PinAlpha(rank, current)
    if current then return 1 end
    return math.max(0.5, 0.95 - (rank or 0) * 0.07)
end

-- The points of a location in order: the arrow target, then its spots.
local function eachPoint(location, visit)
    visit(location.x, location.y)
    for _, spot in ipairs(location.spots or {}) do visit(spot.x, spot.y) end
end

local function acquirePin(pool, index, parent)
    local pin = pool[index]
    if not pin or pin:GetParent() ~= parent then
        if pin then pin:Hide() end
        pin = createPin(parent)
        pool[index] = pin
    end
    return pin
end

local function hidePins(pool, first)
    for index = first or 1, #pool do pool[index]:Hide() end
end

function Navigation:HideWorldMapPins()
    hidePins(self.worldMapPins or {})
end

-- How many steps past the current one get a pin on the world map.
function Navigation:PinsAhead()
    return math.floor(tonumber(ns.modules.Config:Get("navigation.mapPinsAhead")) or 0)
end

-- The map canvas's current magnification. Pins are children of the canvas,
-- so without undoing this they would swell with every step of zoom.
local function canvasScale(canvas)
    local ok, scale = pcall(canvas.GetScale, canvas)
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

-- Config tells every module of a setting changed (Config:Changed): how many
-- steps ahead get a pin redraws the pins.
function Navigation:OnSettingChanged(path)
    if path == "navigation.mapPinsAhead" then self:UpdateWorldMapPOI() end
end

-- Pins go on whatever map the player has open, for every step placed on it;
-- the steps on other maps simply have none there. This gathers the points;
-- LayoutWorldMapPins places them, and runs again whenever the map zooms.
function Navigation:UpdateWorldMapPOI()
    self.worldMapLayout = nil
    local map = _G.WorldMapFrame
    if not map or not map.GetCanvas or not map.GetMapID or not map:IsShown() then return self:HideWorldMapPins() end
    local canvas = map:GetCanvas()
    local currentMapID = map:GetMapID()
    if not canvas or not currentMapID then return self:HideWorldMapPins() end
    local Client = ns.modules.Client
    local points = {}
    local function addLocation(node, current, rank, solo)
        local location = node.location
        if not location or Client:ResolveMapID(location.mapID) ~= currentMapID then return end
        eachPoint(location, function(x, y)
            if type(x) == "number" and type(y) == "number" then
                points[#points + 1] = { x = x, y = y, node = node, current = current, rank = rank, solo = solo }
            end
        end)
    end
    local corpse = self.ghost and self:FindCorpse()
    if corpse then addLocation(corpse, true, 0, true) end
    -- Every waypoint of the travel route still ahead, the one the arrow
    -- follows as current.
    local Route = ns.modules.TravelRoute
    if not corpse and Route then
        for index, leg in ipairs(Route:Waypoints(self:Target())) do
            local legNode = Navigation.LegNode(leg)
            if legNode then addLocation(legNode, index == 1, index - 1, true) end
        end
    end
    if self.waypoint then addLocation(self.waypoint, not corpse, 0, true) end
    for rank, step in ipairs(self:PinSteps(self.activeGuide, self.activeNode, self:PinsAhead())) do
        addLocation(step.node, step.current, rank - 1)
    end
    self.worldMapLayout = { canvas = canvas, points = points }
    self:LayoutWorldMapPins()
end

-- Places the gathered points at a fixed size on screen: each pin is scaled by
-- the inverse of the canvas's zoom, so its offsets are canvas units times the
-- zoom. Clustering is done in those same screen units, so pins merge only
-- where they would really overlap, and zooming in pulls a "12+" apart.
function Navigation:LayoutWorldMapPins()
    self.worldMapPins = self.worldMapPins or {}
    local pool, layout = self.worldMapPins, self.worldMapLayout
    local map = _G.WorldMapFrame
    if not layout or not map or not map:IsShown() then return hidePins(pool) end
    local canvas = layout.canvas
    local width, height = canvas:GetSize()
    if not width or not height or width <= 0 or height <= 0 then return hidePins(pool) end
    local scale = canvasScale(canvas)
    layout.scale, layout.width = scale, width
    local points = {}
    for index, point in ipairs(layout.points) do
        points[index] = {
            x = point.x * width * scale, y = point.y * height * scale,
            node = point.node, current = point.current, rank = point.rank, solo = point.solo,
        }
    end
    local clusters = Navigation.ClusterPins(points, PIN_STYLE.ahead.size)
    local base = canvas:GetFrameLevel()
    for index, cluster in ipairs(clusters) do
        local pin = acquirePin(pool, index, canvas)
        pin:SetScale(1 / scale)
        -- Later steps sit under earlier ones, and the current step on top.
        pin:SetFrameLevel(math.max(1, base + (cluster.current and 120 or 100 - math.min(cluster.rank, 90))))
        paintPin(pin, cluster, cluster.current and PIN_STYLE.current or PIN_STYLE.ahead, Navigation.PinAlpha(cluster.rank, cluster.current))
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", cluster.x, -cluster.y)
        pin:Show()
    end
    hidePins(pool, #clusters + 1)
end

-- Called every frame the map is open; cheap unless the zoom or the canvas
-- size moved since the last layout.
function Navigation:WatchWorldMapZoom()
    local layout = self.worldMapLayout
    if not layout then return end
    if canvasScale(layout.canvas) ~= layout.scale or layout.canvas:GetWidth() ~= layout.width then
        self:LayoutWorldMapPins()
    end
end

-- Minimap offset for a map point relative to the player, as a fraction of the
-- minimap half-size. Returns nil when the point is off the minimap, unless
-- `clampToEdge` holds it on the rim, which the third value reports. Without
-- the map's size nothing can be said to be in range, so only the rim is left.
local function minimapOffset(pointX, pointY, playerX, playerY, mapID, viewRadius, clampToEdge)
    local east, north, inYards = Navigation.WorldDelta(pointX - playerX, playerY - pointY, mapWorldSize(mapID))
    if GetCVar and GetCVar("rotateMinimap") == "1" then
        local facing = playerFacing()
        if facing then
            local cosine, sine = math.cos(facing), math.sin(facing)
            east, north = east * cosine + north * sine, north * cosine - east * sine
        end
    end
    local distance = math.sqrt(east * east + north * north)
    if distance == 0 then return 0, 0 end
    local edge = 0.82
    if inYards and viewRadius then
        local scale = distance / viewRadius * edge
        if scale <= edge then return east / distance * scale, north / distance * scale, false end
    end
    if not clampToEdge then return nil end
    return east / distance * edge, north / distance * edge, true
end

-- Minimap radius in yards. The client API is preferred; older clients only
-- expose the zoom level, whose radii are the long-established values the
-- other guide addons rely on (outdoors and indoors differ).
local ZOOM_RADII_OUTDOOR = { [0] = 233.33, 200, 166.67, 133.33, 100, 66.67 }
local ZOOM_RADII_INDOOR = { [0] = 150, 120, 90, 60, 40, 25 }

local function minimapViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, radius = pcall(C_Minimap.GetViewRadius)
        if ok and type(radius) == "number" and radius > 0 then return radius end
    end
    if not Minimap or type(Minimap.GetZoom) ~= "function" then return nil end
    local ok, zoom = pcall(Minimap.GetZoom, Minimap)
    if not ok or type(zoom) ~= "number" then return nil end
    local indoors = false
    if GetCVar then
        local okCVar, value = pcall(GetCVar, "minimapZoom")
        local okIndoor, indoorValue = pcall(GetCVar, "minimapInsideZoom")
        if okCVar and okIndoor and value and indoorValue and tonumber(indoorValue) == zoom and tonumber(value) ~= zoom then
            indoors = true
        end
    end
    local radii = indoors and ZOOM_RADII_INDOOR or ZOOM_RADII_OUTDOOR
    return radii[math.floor(zoom)]
end

-- The points of a location to draw on the minimap: every one inside its
-- range, or, when none is, the nearest held on the rim in its direction, as
-- a far pin floats on the minimap's edge. Only the nearest goes
-- to the rim because that is the one the arrow points at; a step's other
-- points would only scatter pins round the edge. `offset(x, y, clamp)` places
-- a map point on the minimap and returns nil when it is not drawn.
function Navigation.MinimapPoints(location, playerX, playerY, offset)
    local points = {}
    eachPoint(location, function(x, y)
        local px, py = offset(x, y, false)
        if px then points[#points + 1] = { x = px, y = py } end
    end)
    if #points == 0 then
        local nearX, nearY = Navigation.NearestPoint(location, playerX, playerY)
        local px, py = offset(nearX, nearY, true)
        if px then points[1] = { x = px, y = py, onEdge = true } end
    end
    return points
end

-- The minimap carries only what the arrow points at (the current step, or the
-- corpse), numbered like its world map pin. See `Navigation.MinimapPoints` for
-- which of its points are drawn and when one sits on the rim.
function Navigation:UpdateMinimapPOI(node)
    local Route = ns.modules.TravelRoute
    local legNode = Route and Navigation.LegNode(Route:Leg(node))
    if legNode then node = legNode end
    local location = node and node.location
    local Client = ns.modules.Client
    self.minimapPins = self.minimapPins or {}
    local pool = self.minimapPins
    if not location or not Minimap then return hidePins(pool) end
    local mapID = Client:GetCurrentMapID()
    if not mapID or mapID ~= Client:ResolveMapID(location.mapID) then return hidePins(pool) end
    local playerX, playerY = Client:GetPlayerMapPosition(mapID)
    if not playerX or not playerY then return hidePins(pool) end
    -- Without a radius there is no telling whether the destination is in
    -- range, so a pin inside could be one that belongs on the rim, and the
    -- other way round: show neither.
    local viewRadius = minimapViewRadius()
    if not viewRadius then return hidePins(pool) end
    -- With the minimap rotating, screen-up is the facing direction, so the
    -- north-up offset turns clockwise by the facing angle (inside minimapOffset).
    local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local points = Navigation.MinimapPoints(location, playerX, playerY, function(x, y, clamp)
        local xOffset, yOffset, onEdge = minimapOffset(x, y, playerX, playerY, mapID, viewRadius, clamp)
        if xOffset then return xOffset * halfWidth, yOffset * halfHeight, onEdge end
    end)
    for _, point in ipairs(points) do point.node, point.current, point.rank = node, true, 0 end
    local clusters = Navigation.ClusterPins(points, PIN_STYLE.minimap.size)
    for index, cluster in ipairs(clusters) do
        local pin = acquirePin(pool, index, Minimap)
        paintPin(pin, cluster, PIN_STYLE.minimap, cluster.onEdge and PIN_STYLE.minimap.edgeAlpha or PIN_STYLE.minimap.alpha)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", Minimap, "CENTER", cluster.x, cluster.y)
        pin:Show()
    end
    hidePins(pool, #clusters + 1)
end

-- Runs every frame. The bearing to the target is measured on the slower
-- update beat and eased here, so a new position does not snap the arrow; the
-- player's facing is read fresh each frame and applied as is, so turning the
-- camera turns the arrow with no lag behind it.
function Navigation:AnimateArrow(elapsed)
    local frame = self.frame
    if frame.arrowState ~= "traveling" or not frame.targetBearing then return end
    local current = frame.displayBearing or frame.targetBearing
    local difference = Navigation.ShortestAngle(current, frame.targetBearing)
    frame.displayBearing = current + difference * math.min(1, elapsed * 9)
    frame.displayAngle = frame.displayBearing - (playerFacing() or 0)
    self:ApplyArrowSprite(frame.displayAngle)
end

-- Picks the frame for an angle and colours it. Both layers show the same
-- frame; only the base is tinted, so the sheen stays white.
function Navigation:ApplyArrowSprite(angle)
    local frame = self.frame
    local left, right, top, bottom = Navigation.SpriteCoords(angle)
    frame.arrowGraphic:SetTexCoord(left, right, top, bottom)
    frame.arrowSheen:SetTexCoord(left, right, top, bottom)
    frame.arrowGraphic:SetVertexColor(Navigation.ArrowColor(angle))
end

-- Swaps between the arrow and an icon. Everything but the arrow's own frame is
-- only touched when the state changes, so an animation is never restarted by
-- the quarter-second refresh.
function Navigation:ShowState(state, angle)
    local frame = self.frame
    local changed = frame.arrowState ~= state
    if state ~= "teleport" and frame.teleportIcon:IsShown() then
        frame.teleportIcon:Hide()
        local Route = ns.modules.TravelRoute
        if Route then Route:SyncTeleportButton() end
    end
    if state == "traveling" then
        if changed then
            self:StopSpecialAnimation()
            frame.special:Hide()
            frame.arrowGraphic:Show()
            frame.arrowSheen:Show()
        end
        self:ApplyArrowSprite(angle)
    elseif changed then
        self:StopSpecialAnimation()
        frame.arrowGraphic:Hide()
        frame.arrowSheen:Hide()
        local left, right, top, bottom = Navigation.SpecialCoords(state)
        if left then
            frame.special:SetTexCoord(left, right, top, bottom)
            local color = themeColor(specialColors[state], { 1, 1, 1 })
            frame.special:SetVertexColor(color[1], color[2], color[3], 1)
            frame.special:Show()
            local animation = frame.specialAnimations[state]
            if animation then pcall(animation.Play, animation) end
            frame.playingAnimation = animation
        else
            frame.special:Hide()
        end
    end
    frame.arrowState = state
end

function Navigation:StopSpecialAnimation()
    local frame = self.frame
    local animation = frame.playingAnimation
    if animation then pcall(animation.Stop, animation) end
    frame.playingAnimation = nil
end

local function distanceText(distance, radius, inYards, east, north)
    if radius and distance <= radius then
        if inYards then return string.format("Arrived (%d yd)", math.floor(distance + 0.5)) end
        return "Arrived"
    end
    local bearing = Navigation.CompassBearing(east, north)
    local suffix = bearing and (" " .. bearing) or ""
    if inYards then return string.format("%d yd%s", math.floor(distance + 0.5), suffix) end
    return string.format("%.1f%% of the map%s", distance * 100, suffix)
end

-- East/north yards from a player to a target given both as world coordinates
-- (X grows north, Y grows west).
function Navigation.CrossMapDelta(playerX, playerY, targetX, targetY)
    return playerY - targetY, targetX - playerX
end

-- The player's delta to a step on another map, via world coordinates, to
-- whichever of the step's points is nearest. Nil when either side cannot be
-- placed or they are on different continents.
local function crossMapDelta(Client, currentMap, location, mapID)
    local px, py = Client:GetPlayerMapPosition(currentMap)
    if not px or not py then return nil end
    local playerContinent, playerWorldX, playerWorldY = Client:GetWorldPosition(currentMap, px, py)
    if not playerContinent then return nil end
    local bestEast, bestNorth, best
    local function consider(x, y)
        local continent, worldX, worldY = Client:GetWorldPosition(mapID, x, y)
        if not continent or continent ~= playerContinent then return end
        local east, north = Navigation.CrossMapDelta(playerWorldX, playerWorldY, worldX, worldY)
        local distance = east * east + north * north
        if not best or distance < best then best, bestEast, bestNorth = distance, east, north end
    end
    consider(location.x, location.y)
    for _, spot in ipairs(location.spots or {}) do consider(spot.x, spot.y) end
    return bestEast, bestNorth
end

-- A step with several points sends the arrow to whichever is nearest: the
-- points are equal places to go, and a player who
-- is already beside the second one is not sent back to the first.
function Navigation.NearestPoint(location, x, y)
    if not location then return nil, nil end
    if not location.spots or not x or not y then return location.x, location.y end
    local bestX, bestY = location.x, location.y
    local dx, dy = bestX - x, bestY - y
    local best = dx * dx + dy * dy
    for _, spot in ipairs(location.spots) do
        local sx, sy = spot.x - x, spot.y - y
        local distance = sx * sx + sy * sy
        if distance < best then best, bestX, bestY = distance, spot.x, spot.y end
    end
    return bestX, bestY
end

-- Where a place is from here. The first value is the short label the arrow
-- and the tracker both print ("180 yd NE", "Arrived"); then the distance,
-- whether that distance is in yards, whether the player has arrived, the
-- east/north components the arrow needs, and the name of the map when the
-- place is on a different one. Everything after the label is nil when the
-- client cannot place the player, the target, or both, which is a real
-- answer: the step is still the right one, it just cannot be pointed at.
function Navigation:Measure(location)
    if not location or type(location.mapID) ~= "number"
        or type(location.x) ~= "number" or type(location.y) ~= "number" then return nil end
    local Client = ns.modules.Client
    if not Client then return nil end
    local mapID = Client:ResolveMapID(location.mapID)
    local currentMap = Client:GetCurrentMapID()
    local east, north, inYards, radius, elsewhere
    if mapID and mapID == currentMap then
        local x, y = Client:GetPlayerMapPosition(mapID)
        if x and y then
            local worldWidth, worldHeight = mapWorldSize(mapID)
            local targetX, targetY = Navigation.NearestPoint(location, x, y)
            local dx, dy = targetX - x, y - targetY -- dy grows north
            east, north, inYards = Navigation.WorldDelta(dx, dy, worldWidth, worldHeight)
            if inYards then
                radius = location.arrivalYards or Navigation.ArrivalRadius(location.arrivalRadiusNormalized, worldWidth, worldHeight)
            else
                radius = tonumber(location.arrivalRadiusNormalized)
            end
        end
    elseif mapID and currentMap then
        -- Another map on the same continent: measured through world
        -- coordinates, which are yards. The client often names a city or a
        -- cave while the step is authored on the zone around it, so a player
        -- standing on the spot has arrived whichever map the client picked.
        east, north = crossMapDelta(Client, currentMap, location, mapID)
        inYards = east ~= nil
        if inYards then
            local worldWidth, worldHeight = mapWorldSize(mapID)
            radius = location.arrivalYards
                or (worldWidth and Navigation.ArrivalRadius(location.arrivalRadiusNormalized, worldWidth, worldHeight))
        end
        elsewhere = Client:GetMapName(mapID)
    end
    if east == nil or north == nil then return nil, nil, nil, nil, nil, nil, elsewhere end
    local distance = math.sqrt(east * east + north * north)
    local arrived = radius ~= nil and distance <= radius
    return distanceText(distance, radius, inYards, east, north), distance, inYards, arrived, east, north, elsewhere
end

-- The same measurement said in the width of a tracker column: no bearing, no
-- map name, just how far. The arrow window carries the full reading; a step
-- line only has room for the number, and thousands of yards read better as
-- "1.4k" than as four digits.
function Navigation.ShortDistance(distance, inYards, arrived)
    if distance == nil then return nil end
    if arrived then return "here" end
    if not inYards then return string.format("%.0f%%", distance * 100) end
    if distance >= 1000 then return string.format("%.1fk yd", distance / 1000) end
    return string.format("%d yd", math.floor(distance + 0.5))
end

-- How far a step's place is from the player, in the short form above, or nil
-- when the client cannot place one end of it.
function Navigation:ShortAway(location)
    local _, distance, inYards, arrived = self:Measure(location)
    return Navigation.ShortDistance(distance, inYards, arrived)
end

function Navigation:Update(node)
    local frame = self.frame
    local stepLocation = node and node.location
    if not stepLocation or type(stepLocation.mapID) ~= "number" or type(stepLocation.x) ~= "number" or type(stepLocation.y) ~= "number" then
        -- Nothing to point at at all: no window, per Navigation.ArrowState.
        self:StopSpecialAnimation()
        frame.arrowState = "none"
        frame:Hide()
        return
    end
    local label = ns.modules.Steps:Title(node) or "Destination"
    local stepTitle = label
    -- A travel leg takes the arrow: it points at the leg's end and says the
    -- leg ("Fly to Ratchet"), with the step under it.
    local leg = self:CurrentLeg(node)
    if leg then label = leg.text .. "\n" .. label end
    -- On a taxi the flight is what matters, whatever the route's next leg
    -- is: where it lands, how far, how long. The route takes over again on
    -- landing.
    local Route = ns.modules.TravelRoute
    if ns.modules.Client:IsOnTaxi() then return self:ShowFlight(node, Route and Route:CurrentFlight(), stepTitle) end
    frame.destination:SetText(label)
    if leg and leg.kind == "teleport" then return self:ShowTeleportLeg(node, leg) end
    local location = leg and leg.at or stepLocation
    local Client = ns.modules.Client
    -- Aboard a boat the leg's start is behind the player: the distance is to
    -- where it lands. (A taxi is shown by ShowFlight.)
    if leg and leg.dest and leg.kind == "link" and Route and Route.frozen and Route.carried then
        location = leg.dest
    end
    -- No usable position (other continent, instance, or no map data): the
    -- window stays up with the barred ring and the destination, since the step
    -- is still the right one; it just cannot be pointed at from here.
    local measured, away, inYards, arrived, east, north, elsewhere = self:Measure(location)
    -- A typed-in waypoint is done with once reached: the arrow goes back to
    -- the guide.
    if arrived and node == self.waypoint and not leg then
        self.waypoint = nil
        return self:Retarget()
    end
    local hasBearing = east ~= nil and north ~= nil
    local angle
    if hasBearing then
        -- North-up bearing only; facing is applied per frame in AnimateArrow.
        frame.targetBearing = Navigation.RelativeAngle(east, north, 0)
        if not frame.displayBearing or self.forceAngleUpdate then frame.displayBearing = frame.targetBearing end
        angle = frame.displayBearing - (playerFacing() or 0)
        frame.displayAngle = angle
    else
        frame.targetBearing, frame.displayBearing, frame.displayAngle = nil, nil, nil
    end
    self.forceAngleUpdate = false
    local state = Navigation.ArrowState({
        hasLocation = true,
        onTaxi = Client:IsOnTaxi(),
        hasBearing = hasBearing,
        arrived = arrived,
    })
    self:ShowState(state, frame.displayAngle or angle or 0)
    local text = measured or "No route from here"
    if elsewhere then text = text .. "\n" .. elsewhere end
    -- Measure unconstrained, then fit: natural width when it is under the
    -- cap, the cap (with wrapping) otherwise.
    frame.status:SetWidth(0)
    frame.status:SetText(text)
    frame.status:SetWidth(math.min(math.ceil(frame.status:GetStringWidth()) + 2, frame.statusMaxWidth))
    local towards = "target"
    if leg then towards = location == leg.dest and "landing" or "leg start" end
    self:NoteDisplay({ state = state, leg = leg and leg.text or nil, status = text, towards = towards,
        spot = location and { map = location.mapID, at = { math.floor(location.x * 10000 + 0.5) / 100,
            math.floor(location.y * 10000 + 0.5) / 100 } } or nil,
        yards = inYards and away and math.floor(away + 0.5) or nil })
    self:FitArrowWindow(node)
end

-- What the arrow window shows, on the recorder's `travel` channel: a row
-- whenever its state, its leg or the point it measures to changes, and on a
-- taxi or a boat every fifteen seconds as well, so a distance that grows
-- when it should shrink is in the log. `self.display` is what the travel
-- test panel checks.
function Navigation:NoteDisplay(display)
    self.display = display
    local key = tostring(display.state) .. "|" .. tostring(display.leg) .. "|" .. tostring(display.towards)
        .. "|" .. tostring(display.clickable)
        .. "|" .. (display.spot and (display.spot.map .. ":" .. display.spot.at[1] .. "," .. display.spot.at[2]) or "")
    local Client = ns.modules.Client
    local aboard = display.state == "taxi" or (ns.modules.TravelRoute and ns.modules.TravelRoute.carried
        and ns.modules.TravelRoute.frozen)
    local now = GetTime and GetTime() or 0
    if key == self.displayKey and not (aboard and now >= (self.displayAt or 0)) then return end
    self.displayKey, self.displayAt = key, now + 15
    local row = { event = "arrow" }
    for field, value in pairs(display) do row[field] = value end
    if Client and not Client:IsOnTaxi() and display.state == "taxi" then row.note = "taxi state off a taxi" end
    ns:RecordHere("travel", row)
end

-- Fixed width; the height covers the arrow column and the distance row, or
-- a label centered on the arrow if that runs lower. Growth is downward.
function Navigation:FitArrowWindow(node)
    local frame = self.frame
    local column = (arrowCentreY - arrowHeight / 2) + arrowHeight + 2 + frame.status:GetStringHeight() + 6
    local label = arrowCentreY + frame.destination:GetStringHeight() / 2 + 8
    frame:SetHeight(math.ceil(math.max(column, label)))
    self:ShowArrowWindow(node)
end

-- On a taxi: the wing, "Flying to Crossroads" with the step under it,
-- and the distance and time left to the landing when they are known.
function Navigation:ShowFlight(node, flight, stepLabel)
    local frame = self.frame
    local name = flight and flight.name
    frame.destination:SetText((name and ("Flying to " .. name) or "Flying") .. "\n" .. stepLabel)
    self:ShowState("taxi")
    local measured, away, inYards
    if flight and flight.spot then measured, away, inYards = self:Measure(flight.spot) end
    local Route, Travel = ns.modules.TravelRoute, ns.modules.Travel
    local left = flight and Route and Route:FlightRemaining(flight, inYards and away or nil)
    local parts = {}
    if measured then table.insert(parts, measured) end
    if left and Travel then table.insert(parts, "~" .. Travel.FormatSeconds(left)) end
    local text = #parts > 0 and table.concat(parts, "\n") or "In flight"
    frame.status:SetWidth(0)
    frame.status:SetText(text)
    frame.status:SetWidth(math.min(math.ceil(frame.status:GetStringWidth()) + 2, frame.statusMaxWidth))
    local spot = flight and flight.spot
    self:NoteDisplay({ state = "taxi", leg = name and ("Flying to " .. name) or "Flying", status = text,
        towards = spot and "landing" or "none",
        spot = spot and { map = spot.mapID, at = { math.floor(spot.x * 10000 + 0.5) / 100, math.floor(spot.y * 10000 + 0.5) / 100 } } or nil,
        yards = inYards and away and math.floor(away + 0.5) or nil, left = left and math.floor(left + 0.5) or nil })
    self:FitArrowWindow(node)
end

-- A teleport leg has nowhere to point: the arrow gives way to the hearthstone
-- or the spell itself, which the player clicks (a secure button laid over it
-- by UI/TravelRoute.lua). NuuRoad never casts it.
function Navigation:ShowTeleportLeg(node, leg)
    local frame = self.frame
    self:ShowState("teleport")
    local Route = ns.modules.TravelRoute
    local action = Route and Route:TeleportAction(leg)
    frame.teleportIcon:SetTexture(action and action.icon or "Interface/Icons/INV_Misc_QuestionMark")
    frame.teleportIcon:Show()
    local wait = Route and Route:TeleportWait(leg)
    local text
    if wait and wait > 1 then
        local Travel = ns.modules.Travel
        text = "Ready in " .. (Travel and Travel.FormatSeconds(wait) or (math.floor(wait) .. "s"))
    elseif not action then
        text = "Not in your bags"
    elseif Route and not Route:TeleportButtonReady() then
        text = "Click after combat"
    else
        text = "Click to use"
    end
    frame.status:SetWidth(0)
    frame.status:SetText(text)
    frame.status:SetWidth(math.min(math.ceil(frame.status:GetStringWidth()) + 2, frame.statusMaxWidth))
    self:NoteDisplay({ state = "teleport", leg = leg.text, status = text, towards = "none",
        clickable = Route and Route:TeleportButtonReady() or false })
    self:FitArrowWindow(node)
end

-- The arrow window follows the tracker: closing the tracker closes the arrow,
-- and showing it again brings the arrow back (when the option is on). A
-- typed-in waypoint is travel, not the guide: its arrow shows with the
-- tracker closed too, since the player may not have a guide open at all.
function Navigation:ShowArrowWindow(node)
    local tracker = ns.modules.MainWindow
    local trackerShown = tracker and tracker.frame and tracker.frame:IsShown()
    local ownWaypoint = node ~= nil and node == self.waypoint
    local wanted = (ns.modules.Config:Get("navigation.standalone") and trackerShown) or ownWaypoint
    if wanted then self.frame:Show() else self.frame:Hide() end
    local Route = ns.modules.TravelRoute
    if Route then Route:SyncTeleportButton() end
end

-- Called when the tracked step changes, not on a timer. The guide is what the
-- world map walks for the pins of the steps after this one.
function Navigation:Refresh(node, guide)
    self.activeNode = node and node.location and node or nil
    self.activeGuide = guide
    self:Retarget()
end

-- Raw client answers behind the arrow, for `/nuuroad where`. Every call is
-- pcall'd and the error text kept, so a client that throws still reports.
local function describe(value)
    if type(value) == "table" then
        if type(value.GetXY) ~= "function" then return "table" end
        local ok, x, y = pcall(function() return value:GetXY() end)
        if ok then return string.format("table with GetXY -> %s, %s", tostring(x), tostring(y)) end
        return string.format("table (x=%s, y=%s) GetXY error: %s", tostring(value.x), tostring(value.y), tostring(x))
    end
    return type(value) .. " " .. tostring(value)
end

local function try(label, fn, ...)
    if type(fn) ~= "function" then return label .. ": API missing" end
    local results = { pcall(fn, ...) }
    if not results[1] then return label .. ": ERROR " .. tostring(results[2]) end
    local parts = {}
    for index = 2, math.max(#results, 2) do parts[#parts + 1] = describe(results[index]) end
    return label .. ": " .. table.concat(parts, ", ")
end

function Navigation:DiagnosticLines()
    local Client = ns.modules.Client
    local lines = { "Navigation diagnostics (" .. date("%Y-%m-%d %H:%M:%S") .. ")" }
    local add = function(line) lines[#lines + 1] = line end
    add(try("IsInInstance", IsInInstance))
    add(try("GetRealZoneText", GetRealZoneText))
    add(try("GetSubZoneText", GetSubZoneText))
    add(try("GetPlayerFacing", GetPlayerFacing))
    add("C_Map: " .. tostring(C_Map ~= nil) .. "; GetBestMapForUnit: " .. tostring(C_Map and C_Map.GetBestMapForUnit ~= nil)
        .. "; GetPlayerMapPosition: " .. tostring(C_Map and C_Map.GetPlayerMapPosition ~= nil))
    add(try("C_Map.GetBestMapForUnit(player)", C_Map and C_Map.GetBestMapForUnit, "player"))
    local currentMap = Client:GetCurrentMapID()
    add("Client:GetCurrentMapID -> " .. tostring(currentMap))
    if currentMap then
        add(try("C_Map.GetMapInfo(current)", C_Map and C_Map.GetMapInfo, currentMap))
        local ok, info = pcall(C_Map.GetMapInfo, currentMap)
        if ok and type(info) == "table" then
            add(string.format("  name=%s mapType=%s parentMapID=%s", tostring(info.name), tostring(info.mapType), tostring(info.parentMapID)))
        end
        add(try("C_Map.GetPlayerMapPosition(current)", C_Map and C_Map.GetPlayerMapPosition, currentMap, "player"))
        add(try("C_Map.GetMapWorldSize(current)", C_Map and C_Map.GetMapWorldSize, currentMap))
        local x, y = Client:GetPlayerMapPosition(currentMap)
        add("Client:GetPlayerMapPosition(current) -> " .. tostring(x) .. ", " .. tostring(y))
    end
    local Progress = ns.modules.Progress
    local guide = Progress and Progress:GetActiveGuide()
    local current = guide and Progress:GetCurrentNode(guide)
    add("Active guide: " .. (guide and (tostring(guide.meta and guide.meta.title) .. " (" .. tostring(guide.id) .. ")") or "none"))
    if current then
        add(string.format("Current step: '%s' (step %s, kind %s) has location: %s",
            tostring(ns.modules.Steps:Title(current)), tostring(current.index), tostring(current.kind), tostring(current.location ~= nil)))
    elseif guide then
        add("Current step: none (guide complete)")
    end
    add(string.format("Ghost: %s; death map: %s; corpse: %s", tostring(self.ghost), tostring(self.deathMap),
        self.corpse and string.format("map %s x=%.4f y=%.4f", tostring(self.corpse.location.mapID), self.corpse.location.x, self.corpse.location.y) or "none"))
    if currentMap then
        add(try("C_DeathInfo.GetCorpseMapPosition(current)", C_DeathInfo and C_DeathInfo.GetCorpseMapPosition, currentMap))
    end
    local node = self:Target()
    local location = node and node.location
    if not node then
        add("Tracked step: none with a location (arrow has nothing to point at)")
        if current and current.location then add("  VERDICT: the current step has a location but Navigation was not refreshed with it.") end
        if current and not current.location then add("  VERDICT: the current step has no coordinates, so there is nothing to point at.") end
    else
        local stepMap = Client:ResolveMapID(location.mapID)
        add(string.format("Tracked step: '%s' (step %s)", tostring(ns.modules.Steps:Title(node)), tostring(node.index)))
        add(string.format("  step mapID=%s (resolved %s) x=%s y=%s", tostring(location.mapID), tostring(stepMap), tostring(location.x), tostring(location.y)))
        if stepMap then
            add(try("  C_Map.GetMapInfo(step)", C_Map and C_Map.GetMapInfo, stepMap))
            add(try("  C_Map.GetPlayerMapPosition(step)", C_Map and C_Map.GetPlayerMapPosition, stepMap, "player"))
        end
        if stepMap ~= currentMap then
            local px, py = Client:GetPlayerMapPosition(currentMap)
            local function world(map, x, y)
                if not x or not y then return "no position" end
                local continent, wx, wy = Client:GetWorldPosition(map, x, y)
                return string.format("continent %s, x %s, y %s", tostring(continent), tostring(wx), tostring(wy))
            end
            add("  world(player): " .. world(currentMap, px, py))
            add("  world(step): " .. world(stepMap, location.x, location.y))
            local east, north = crossMapDelta(Client, currentMap, location, stepMap)
            if east then
                add(string.format("  VERDICT: step is on another map; pointing across maps, %d yd east, %d yd north.", east, north))
            else
                add("  VERDICT: step is on another map and world coordinates are unavailable or on another continent; the arrow hides.")
            end
        else
            local x, y = Client:GetPlayerMapPosition(stepMap)
            if x and y then
                add("  VERDICT: position available; the arrow should be showing.")
            else
                add("  VERDICT: same map, but the client returned no position; the arrow hides.")
            end
        end
    end
    local Route = ns.modules.TravelRoute
    if Route then for _, line in ipairs(Route:DiagnosticLines()) do add(line) end end
    add("Arrow window setting (standalone): " .. tostring(ns.modules.Config:Get("navigation.standalone")))
    add("Arrow state: " .. tostring(self.frame and self.frame.arrowState))
    add("On a taxi: " .. tostring(ns.modules.Client:IsOnTaxi()))
    local angle = self.frame and self.frame.displayAngle
    if angle then
        local index, mirrored = Navigation.SpriteFrame(angle)
        add(string.format("Arrow angle: %.1f deg, sprite frame %d%s", math.deg(angle) % 360, index, mirrored and " (mirrored)" or ""))
    end
    add("Arrow frame shown: " .. tostring(self.frame and self.frame:IsShown()))
    return lines
end

function Navigation:Initialize()
    self:CreateFrame()
    -- PLAYER_DEAD fires while the corpse is still underfoot: remember its map
    -- for the walk back. Release and resurrection both come as PLAYER_ALIVE
    -- (and PLAYER_UNGHOST), so those re-read the ghost state rather than assume.
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_DEAD" then self.deathMap = ns.modules.Client:GetCurrentMapID() end
        self:RefreshLifeState()
    end)
    self.lifeEvents = events
    if _G.WorldMapFrame then
        _G.WorldMapFrame:HookScript("OnShow", function() self:UpdateWorldMapPOI(self:Target()) end)
        _G.WorldMapFrame:HookScript("OnHide", function() self:HideWorldMapPins() end)
        _G.WorldMapFrame:HookScript("OnUpdate", function() self:WatchWorldMapZoom() end)
        if _G.WorldMapFrame.OnMapChanged then
            hooksecurefunc(_G.WorldMapFrame, "OnMapChanged", function() self:UpdateWorldMapPOI(self:Target()) end)
        end
    end
end

ns:RegisterModule("Navigation", Navigation)
