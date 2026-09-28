local addonName, ns = ...

-- Scaffolding for the split: reports the load order at login. Remove once the
-- real files are in.
ns.Kit.Loaded(addonName, "LoadProbe.lua")
ns.Kit.ReportLoad(addonName, ns, "Core.lua")
