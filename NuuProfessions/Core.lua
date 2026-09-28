local addonName, ns = ...

ns.name = addonName
ns.version = "0.1.0-dev"

-- In a release the embedded kit files have already filled ns.Kit; in
-- development it comes from the NuuKit addon.
ns.Kit = ns.Kit or _G.NuuKit
assert(ns.Kit, addonName .. ": NuuKit is not loaded")

-- The one intentional global of this addon.
_G.NuuProfessions = ns

ns.Kit.Loaded(addonName, "Core.lua")
