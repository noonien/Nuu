-- The in-play strips beside the tracker (UI/NPCPanel.lua, UI/ItemPanel.lua,
-- UI/MaterialsPanel.lua) and the arrow window (Navigation:CreateFrame), on
-- the kit's stand-in for the client. Guides from the packaged fixtures are
-- started and walked to steps with creatures, items and materials; each
-- strip is refreshed and read, its settings are turned off and on, the
-- arrow window is shown for a waypoint, and the look is changed under all
-- of them. The client calls the stand-in lacks (bags, faction, secure
-- attributes, frame names) are stubbed here and put back at the end.
local ctx = dofile("Tests/UI/Harness.lua")
local ns, check, settle, UI, frames = ctx.ns, ctx.check, ctx.settle, ctx.UI, ctx.frames
local modules = ns.modules
local NPCPanel, ItemPanel, MaterialsPanel = modules.NPCPanel, modules.ItemPanel, modules.MaterialsPanel
local Navigation, Config, Progress, Repository = modules.Navigation, modules.Config, modules.Progress, modules.GuideRepository
check(NPCPanel and ItemPanel and MaterialsPanel and Navigation, "the panels are loaded")
check(NPCPanel.frame and ItemPanel.frame and MaterialsPanel.frame and Navigation.frame, "the panels were made at login")

-- Stubs ---------------------------------------------------------------------------------------

local STUBS = { "GetItemCount", "GetItemSpell", "UnitFactionGroup", "UnitClass", "UnitRace", "GetBindingKey", "CreateFrame" }
local saved = {}
for _, name in ipairs(STUBS) do saved[name] = rawget(_G, name) end
local Object = frames.Object
local savedAttribute, savedGetAttribute = rawget(Object, "SetAttribute"), rawget(Object, "GetAttribute")

local bags = {}
_G.GetItemCount = function(id) return bags[id] or 0 end
_G.GetItemSpell = function(id) if id == 4702 then return "Use" end end
_G.UnitFactionGroup = function() return "Horde", "Horde" end
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitRace = function() return "Orc", "Orc", 2 end
_G.GetBindingKey = function(binding)
    if binding == "CLICK NuuRoadTargetButton1:LeftButton" then return "SHIFT-1" end
    if binding == "CLICK NuuRoadItemButton1:LeftButton" then return "CTRL-5" end
end
-- The secure macro text a slot carries, and the names frames are made with.
if not savedAttribute then
    function Object:SetAttribute(key, value)
        local attributes = rawget(self, "attributes") or {}
        attributes[key] = value
        rawset(self, "attributes", attributes)
    end
    function Object:GetAttribute(key) return (rawget(self, "attributes") or {})[key] end
end
local function fixture(id)
    local guide = Repository:Get(id)
    check(guide, id .. " is packaged")
    Progress:Select(guide)
    return Progress:GetActiveGuide() or guide
end

-- Walks the current guide to step `index` and tells the modules the tracker
-- would (it is someone else's screen, and may not be built here).
local function goTo(guide, index)
    Progress:GoTo(guide, index)
    local node = Progress:GetCurrentNode(guide)
    modules.NPCTracking:Refresh(Progress:QuestGroup(guide, node))
    NPCPanel:OnStepChanged()
    ItemPanel:Refresh()
    MaterialsPanel:Refresh()
    settle()
    return node
end

local function shownSlots(panel)
    local count = 0
    for _, slot in ipairs(panel.slots) do if slot:IsShown() then count = count + 1 end end
    return count
end

-- The NPC strip --------------------------------------------------------------------------------

local guide = fixture("nuuroad:fixture:npc-tracking")
local node = goTo(guide, 2)
check(node and node.kind == "kill", "the NPC fixture's second step is its kill group: " .. tostring(node and node.kind))
local strip = NPCPanel.frame
check(strip:IsShown(), "the NPC strip shows for a kill step")
check(shownSlots(NPCPanel) == 3, "three plainstriders, three slots: " .. shownSlots(NPCPanel))
local first = NPCPanel.slots[1]
check(first:IsSecure(), "a target slot is secure")
check(_G.NuuRoadTargetButton1 == first and first:GetName() == "NuuRoadTargetButton1", "the first target slot has its binding's name")
check(first.data.entry and first.data.entry.kind == "kill", "the first slot is a kill target")
check((first:GetAttribute("macrotext") or ""):match("/tar"), "the slot's macro targets its creature: "
    .. tostring(first:GetAttribute("macrotext")))
check(first.keyText:GetText() ~= "", "the bound key shows in the slot's corner")
check(first.countText:GetText():match("x$"), "a kill target says how many are left: " .. first.countText:GetText())
check(strip.header.summary:GetText():match("^kills "), "the header counts the kills: " .. strip.header.summary:GetText())
check(strip.header.title:GetText() == "Targets", "the strip is titled in sentence case")
-- The slot's tooltip, then a click: the macro ran (nothing to see on the
-- stand-in) and the slot's own click refreshes the macros.
first:Fire("OnEnter")
check(GameTooltip:GetText() == first.data.entry.name, "the tooltip names the creature: " .. tostring(GameTooltip:GetText()))
first:Fire("OnLeave")
first:Click()
NPCPanel.markAll:Fire("OnEnter")
NPCPanel.markAll:Fire("OnLeave")
NPCPanel.markAll:Click()

-- The quest givers' group: three NPCs to talk to.
node = goTo(guide, 4)
check(node and node.kind == "acceptQuest", "the fixture's fourth step accepts a quest: " .. tostring(node and node.kind))
local talkers = shownSlots(NPCPanel)
check(talkers >= 1, "the quest givers take the slots: " .. talkers)
check(NPCPanel.slots[1].data.entry.kind == "talk", "a quest giver is a talk slot")
check(NPCPanel.slots[1].countText:GetText() == "talk", "a talk slot says so")
check(#NPCPanel.slots == 3, "no new slot is made for a shorter step: " .. #NPCPanel.slots)
-- A creature seen: its slot takes the unit (nothing to draw on the stand-in).
NPCPanel:OnUnitSeen(NPCPanel.slots[1].data.entry.id, "target")

-- In view only: nothing is in view on the stand-in, so the strip goes.
Config:Set("npcPanel.inViewOnly", true)
settle()
check(not strip:IsShown(), "with nothing in view the in-view-only strip hides")
Config:Reset("npcPanel.inViewOnly")
check(strip:IsShown(), "back to every creature, the strip shows again")
Config:Set("npcPanel.shown", false)
check(not strip:IsShown(), "the setting off hides the strip")
Config:Reset("npcPanel.shown")
check(strip:IsShown(), "the setting on shows it")
-- The tracker hidden takes the strips with it.
Config:Set("tracker.shown", false)
check(not strip:IsShown(), "the NPC strip follows the tracker away")
Config:Reset("tracker.shown")
check(strip:IsShown(), "and back")
-- A combat refresh waits for the combat's end.
local savedCombat = rawget(_G, "InCombatLockdown")
_G.InCombatLockdown = function() return true end
NPCPanel:Refresh()
check(NPCPanel.pending, "a refresh in combat waits")
_G.InCombatLockdown = savedCombat
NPCPanel:OnCombatEnded()
check(not NPCPanel.pending, "and is applied when combat ends")
ctx.noErrors("the NPC strip")

-- The item strip ------------------------------------------------------------------------------

guide = fixture("nuuroad:fixture:quest-items")
check(not NPCPanel.frame:IsShown() or shownSlots(NPCPanel) > 0, "the NPC strip follows the new guide")
bags[4926] = 1 -- Chen's Empty Keg, which begins a quest
node = goTo(guide, 1)
local items = ItemPanel.frame
check(items:IsShown(), "the item strip shows the keg in the bags")
check(shownSlots(ItemPanel) == 1, "one item, one slot: " .. shownSlots(ItemPanel))
local keg = ItemPanel.slots[1]
check(keg:IsSecure() and _G.NuuRoadItemButton1 == keg, "the item slot is secure and named for its binding")
check(keg:GetAttribute("macrotext") == "/use item:4926", "the slot uses its item: " .. tostring(keg:GetAttribute("macrotext")))
check(keg.questMark:IsShown(), "an item that begins a quest wears the quest mark")
check(keg.keyText:GetText() ~= "", "the bound key shows")
keg:Fire("OnEnter")
check(GameTooltip:GetText() == ns.modules.Names:DescribeItem(4926), "the keg's tooltip names it over the item's own")
keg:Fire("OnLeave")
-- The step that presses the picks, not the tools it counts.
bags[4926] = nil
bags[4702], bags[4703] = 3, 2
node = goTo(guide, 4)
check(node and node.use, "the fixture's pick step: " .. tostring(node and node.kind))
check(shownSlots(ItemPanel) == 1 and ItemPanel.slots[1].data.itemID == 4702, "the strip offers the pick")
check(ItemPanel.slots[1].countText:GetText() == "3", "with the count in the bags")
check(not ItemPanel.slots[1].questMark:IsShown(), "and no quest mark")
check(ItemPanel:Waiting(4702) and not ItemPanel:Waiting(4926), "a shown item is waited on, another is not")
Config:Set("itemPanel.shown", false)
check(not items:IsShown(), "the setting off hides the item strip")
Config:Reset("itemPanel.shown")
check(items:IsShown(), "the setting on shows it")
bags[4702] = nil
ItemPanel:Refresh()
check(not items:IsShown(), "nothing to press, no strip")
ctx.noErrors("the item strip")

-- The materials list --------------------------------------------------------------------------

guide = fixture("nuuroad:fixture:materials-by-section")
bags[2835] = 4
node = goTo(guide, 1)
local list = MaterialsPanel.frame
check(list:IsShown(), "the materials list shows for a guide that needs materials")
check(list.title:GetText() == "Rough Sharpening Stone 1-10", "the list names its section: " .. tostring(list.title:GetText()))
check(#MaterialsPanel.rows == 1, "one material in the first section: " .. #MaterialsPanel.rows)
local row = MaterialsPanel.rows[1]
check(row.count:GetText() == "4/10", "what is carried of what is needed: " .. row.count:GetText())
check(row.check:GetText() == "[ ]", "not enough yet")
check(MaterialsPanel.summary:GetText() == "1 still needed", "the band counts what is missing")
check(list:GetHeight() > 30, "the list is as tall as its rows: " .. list:GetHeight())
-- Enough in the bags: the same rows repainted in place.
bags[2835] = 10
MaterialsPanel:Refresh()
check(MaterialsPanel.rows[1] == row, "the same shape is repainted, not built again")
check(row.check:GetText() == "[x]" and MaterialsPanel.summary:GetText() == "all carried", "ticked, all carried")
-- The next section: another shape, built again.
node = goTo(guide, 3)
check(list.title:GetText() == "Bolt of Linen Cloth 10-20", "the list moves on to the next section")
check(MaterialsPanel.rows[1] ~= row or MaterialsPanel.shape:match("2589"), "the list is built again for linen")
Config:Set("materials.shown", false)
check(not list:IsShown(), "the setting off hides the list")
Config:Reset("materials.shown")
check(list:IsShown(), "the setting on shows it")
ctx.noErrors("the materials list")

-- The profession fixture: a guide with craft steps shows its list too, and
-- its step with no creatures hides the NPC strip.
guide = fixture("nuuroad:fixture:professions")
node = goTo(guide, 1)
check(not NPCPanel.frame:IsShown(), "no creatures, no NPC strip")
ctx.noErrors("the profession fixture")

-- The arrow window ----------------------------------------------------------------------------

local arrow = Navigation.frame
check(arrow.kitIsWindow, "the arrow window is a kit panel")
check(arrow.teleportIcon and arrow.arrowGraphic and arrow.special, "the arrow's art is on it")
Navigation:SetWaypoint(1413, 0.5, 0.5, "Somewhere in the Barrens")
settle()
check(arrow:IsShown(), "a waypoint shows the arrow window")
check((arrow.destination:GetText() or "") ~= "", "the window says where it points: " .. tostring(arrow.destination:GetText()))
check((arrow.status:GetText() or "") ~= "", "and how far, or why it cannot say")
check(arrow:GetWidth() == 250, "the window keeps its fixed width")
-- A plain left click is not the window's: it neither takes the mouse nor moves.
local mouse
arrow.EnableMouse = function(_, on) mouse = on end
arrow.shiftWatcher:Fire("OnUpdate", 0)
check(not mouse, "without shift the window lets clicks through")
local savedPlace = ns.db.windows.arrow
ns.db.windows.arrow = nil
arrow:Fire("OnMouseDown", "LeftButton")
arrow:Fire("OnMouseUp", "LeftButton")
check(not ns.db.windows.arrow, "a plain left click does not move the arrow")
-- Shift-dragged: the place is kept where the kit keeps windows'.
local savedShift = _G.IsShiftKeyDown
_G.IsShiftKeyDown = function() return true end
arrow.shiftWatcher:Fire("OnUpdate", 0)
check(mouse == true, "with shift down the window takes the mouse")
arrow:Fire("OnMouseDown", "LeftButton")
arrow:Fire("OnMouseUp", "LeftButton")
check(ns.db.windows.arrow and ns.db.windows.arrow.x, "the arrow's place is saved in NuuRoadDB.windows")
_G.IsShiftKeyDown = savedShift
arrow.shiftWatcher:Fire("OnUpdate", 0)
check(mouse == false, "and lets it go with shift")
arrow.EnableMouse = nil
if not ns.db.windows.arrow then ns.db.windows.arrow = savedPlace end
-- The menu answers a right click on the arrow, not on the text.
local opened = 0
local savedOpen = Navigation.OpenMenu
Navigation.OpenMenu = function() opened = opened + 1 end
arrow:Fire("OnMouseUp", "RightButton")
check(opened == 0, "a right click on the text opens no menu")
arrow.menuHit:Fire("OnMouseUp", "RightButton")
check(opened == 1, "a right click on the arrow opens its menu")
Navigation.OpenMenu = savedOpen
Navigation:ClearWaypoint()
settle()

-- The look ------------------------------------------------------------------------------------

local fontBefore = arrow.destination.fontSize
UI:SetLook({ theme = "slate", textSize = "large" })
settle()
check(arrow.destination.fontSize ~= fontBefore, "the arrow's texts follow the look's text size: "
    .. tostring(fontBefore) .. " -> " .. tostring(arrow.destination.fontSize))
UI:SetLook({ theme = "horde" })
settle()
UI:SetLook(nil)
settle()
ctx.noErrors("the look")

-- Back as it was -------------------------------------------------------------------------------

Progress:Deselect()
NPCPanel:Refresh(); ItemPanel:Refresh(); MaterialsPanel:Refresh()
for _, name in ipairs(STUBS) do _G[name] = saved[name] end
if not savedAttribute then Object.SetAttribute, Object.GetAttribute = nil, nil end
ctx.noErrors("the panels")
