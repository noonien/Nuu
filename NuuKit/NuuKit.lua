local addonName, ns = ...

-- Development only, never shipped: lets the addons find the one working copy
-- of the kit through `ns.Kit = ns.Kit or _G.NuuKit`.
_G.NuuKit = ns.Kit

-- Development builds audit the addons' marks for resetting widgets (Dev/Audit.lua).
ns.Kit.UI.SetAudit(true)

-- Development builds keep every Lua error of the addons in their session logs (Dev/Errors.lua).
ns.Kit.Errors.Install()

ns.Kit.Loaded(addonName, "NuuKit.lua")
