local addonName, ns = ...

-- Development only, never shipped: lets the addons find the one working copy
-- of the kit through `ns.Kit = ns.Kit or _G.NuuKit`.
_G.NuuKit = ns.Kit

ns.Kit.Loaded(addonName, "NuuKit.lua")
