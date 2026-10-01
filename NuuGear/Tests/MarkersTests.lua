-- UI/Markers.lua and UI/Commands.lua on the kit's stand-in for the client:
-- the arrow on a bag slot, a quest reward, a loot slot, a roll and an
-- EllesmereUIBags slot, and /nuugear changing the spec. Last: the stand-in
-- stays in _G.
local Frames = dofile("../NuuKit/Tests/Support/Frames.lua")
local ns, client = NewDomain()
Load(ns, "UI/Markers.lua")
Load(ns, "UI/Commands.lua")
local Markers, Commands = ns.modules.Markers, ns.modules.Commands

local hooks = {}
_G.hooksecurefunc = function(target, method, fn)
    if type(target) == "string" then target, method, fn = _G, target, method end
    local original = target[method]
    target[method] = function(...)
        local a, b, c = original(...)
        fn(...)
        return a, b, c
    end
    hooks[method] = true
end

local function button(name, parent, id)
    local made = CreateFrame("Button", name, parent)
    made.GetID = function() return id end
    return made
end

local ARROW = "Interface\\AddOns\\NuuGear\\Art\\UpgradeArrow.tga"
local function arrowOn(owner)
    for _, region in ipairs(owner.regionList or {}) do
        if region.texture == ARROW then return region:IsShown() and true or false end
    end
    return false
end

-- The items: one upgrade, one not.
client.class = "WARRIOR"
local belt = client:Item("Strong belt", "INVTYPE_WAIST", { ITEM_MOD_STRENGTH_SHORT = 5 })
local cloth = client:Item("Cloth belt", "INVTYPE_WAIST", { ITEM_MOD_INTELLECT_SHORT = 5 })
client.bags = { ["0:1"] = belt, ["0:2"] = cloth }
client.GetBagSlotLink = function(self, bag, slot) return self.bags[bag .. ":" .. slot] end
client.GetQuestRewardLink = function(_, kind, index) return kind == "choice" and ({ cloth, belt })[index] or nil end
client.GetLootSlotLink = function(_, slot) return slot == 1 and belt or nil end
client.GetLootRollLink = function(_, rollID) return rollID == 7 and belt or nil end

-- The game's windows, as the client names them.
local bagFrame = CreateFrame("Frame", "ContainerFrame1")
bagFrame.size = 2
rawset(bagFrame, "EnumerateValidItems", false) -- the stand-in answers every method; this frame is the old kind
bagFrame.GetID = function() return 0 end
local slot1, slot2 = button("ContainerFrame1Item1", bagFrame, 1), button("ContainerFrame1Item2", bagFrame, 2)
_G.ContainerFrame_Update = function() end
local rewards = CreateFrame("Frame", "QuestInfoRewardsFrame")
local choice1, choice2 = button("QuestInfoRewardsFrameQuestInfoItem1", rewards, 1),
    button("QuestInfoRewardsFrameQuestInfoItem2", rewards, 2)
choice1.type, choice2.type = "choice", "choice"
_G.QuestInfo_Display = function() end
local loot = CreateFrame("Frame", "LootFrame")
local lootButton = button("LootButton1", loot, 1)
lootButton.slot = 1
_G.LootFrame_Update = function() end
local roll = CreateFrame("Frame", "GroupLootFrame1")
local rollIcon = CreateFrame("Button", "GroupLootFrame1IconFrame", roll)
roll.rollID = 7
-- EllesmereUIBags' painter registry.
local painters = {}
_G.EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame")
_G.EUI_Bags.RegisterItemOverlayIcon = function(name, fn) painters[name] = fn end
_G.EUI_Bags.RefreshInventory = function() painters.repainted = true end

ns.characterDB = {}
ns.db = { settings = {} }
ns.modules.Config.characterStore = {}
Markers:Initialize()
Commands:Initialize()
assert(hooks.ContainerFrame_Update and hooks.QuestInfo_Display and hooks.LootFrame_Update, "hooked what exists")
assert(type(painters.NuuGear) == "function", "registered with EllesmereUIBags")

-- The game's own calls draw the arrows, on the upgrade only.
_G.ContainerFrame_Update(bagFrame)
assert(arrowOn(slot1) and not arrowOn(slot2), "bags")
_G.QuestInfo_Display()
assert(not arrowOn(choice1) and arrowOn(choice2), "quest choices")
_G.LootFrame_Update()
assert(arrowOn(lootButton), "loot window")
Markers:RefreshRolls()
assert(arrowOn(roll), "group loot roll (drawn on the frame, over its icon)")
local euiButton = CreateFrame("Button", nil, _G.EUI_Bags)
euiButton._textOverlay = CreateFrame("Frame", nil, euiButton)
painters.NuuGear(euiButton, { bag = 0, slot = 1, itemLink = belt })
assert(arrowOn(euiButton._textOverlay), "EllesmereUIBags slot, on its text overlay")
painters.NuuGear(euiButton, { bag = 0, slot = 2, itemLink = cloth })
assert(not arrowOn(euiButton._textOverlay), "a pooled button loses the arrow")

-- A reward button hidden or reused for money loses it.
choice2:Hide()
Markers:RefreshQuests()
assert(not arrowOn(choice2))
choice2:Show()

-- A setting turns a place off.
ns.modules.Config:Set("markers.bags", false)
Markers:RefreshBags()
assert(not arrowOn(slot1), "bags off")
ns.modules.Config:Reset("markers.bags")

-- Picking another spec redraws everything: to a holy paladin's eye the
-- intellect belt is the upgrade. (No C_Timer in the stand-in: at once.)
client.class = "PALADIN"
SlashCmdList.NUUGEAR("spec holy")
assert(ns.printed[#ns.printed - 1]:find("Scoring gear as Holy %(picked by you%)"))
assert(not arrowOn(slot1) and arrowOn(slot2), "bags redrawn for the new spec")
assert(painters.repainted, "EllesmereUIBags asked to draw again")
SlashCmdList.NUUGEAR("spec nonsense")
assert(ns.printed[#ns.printed - 2]:find("No spec called"))

-- /nuugear check explains a verdict.
SlashCmdList.NUUGEAR("check " .. cloth)
local said = table.concat(ns.printed, "\n")
assert(said:find("upgrade, 3.5 against 0.0 %(Holy, slot 6%)") and said:find("Stats read: Intellect 5"))

-- Events: equipment changes forget every verdict; an item coming in only
-- redraws; a tooltip that is not ours is ignored.
local forgotten = 0
local forget = ns.modules.Upgrades.Forget
ns.modules.Upgrades.Forget = function(self) forgotten = forgotten + 1; return forget(self) end
Markers.frame:Fire("OnEvent", "PLAYER_EQUIPMENT_CHANGED")
assert(forgotten == 1)
Markers.frame:Fire("OnEvent", "GET_ITEM_INFO_RECEIVED", 5)
Markers.frame:Fire("OnEvent", "TOOLTIP_DATA_UPDATE", 12345)
assert(forgotten == 1)
Frames.tick()
return true
