local _, ns = ...

-- Which client this is and which of the API families the Nuu addons lean on
-- it has. Kept running at login (once per build) as the baseline every other
-- result is read against.
ns:Experiment({
    id = "client",
    title = "Client build and API families",
    run = function(t)
        t:Try("GetBuildInfo", GetBuildInfo)
        t:Try("GetLocale", GetLocale)
        t:Try("GetPhysicalScreenSize", GetPhysicalScreenSize)
        t:Set("WOW_PROJECT_ID", rawget(_G, "WOW_PROJECT_ID"))
        t:Set("uiScale", UIParent and UIParent:GetEffectiveScale())

        t:Exists({
            "C_AddOns.GetAddOnInfo", "C_Container.GetContainerItemLink", "C_Item.GetItemInfo",
            "C_Item.GetItemStats", "C_QuestLog.IsFailed", "C_Timer.After", "C_TooltipInfo.GetHyperlink",
            "C_TradeSkillUI.GetAllRecipeIDs", "C_PlayerInfo.CanUseItem", "C_MerchantFrame.GetItemInfo",
            "TooltipDataProcessor.AddTooltipPostCall", "Settings.RegisterAddOnCategory",
            "GetItemInfo", "GetItemStats", "GetQuestLogTitle", "GetTradeSkillInfo", "GetMerchantItemInfo",
        })

        -- Every C_ namespace the client has, by name.
        local namespaces = {}
        for name, value in pairs(_G) do
            if type(name) == "string" and string.match(name, "^C_") and type(value) == "table" then
                namespaces[#namespaces + 1] = name
            end
        end
        table.sort(namespaces)
        t:Set("namespaces", namespaces)
    end,
})
