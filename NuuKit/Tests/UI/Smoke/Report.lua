-- The in-client report runs its every step on the stand-in: both kits' screens,
-- every scenario, and the copy window. It measures nothing here.
-- `lua -e SHOW_REPORT=true Tests/UI/Smoke/Run.lua Report` prints what it wrote.

local ctx = ...
local Kit, assertTrue = ctx.Kit, ctx.assertTrue

assertTrue(type(Kit.RunReport) == "function", "the report is there")
local shown
local oldPrint = print
print = function(text) shown = text end
Kit.RunReport()
print = oldPrint
local text = Kit.lastReport or ""
if SHOW_REPORT then print(text) end
assertTrue(shown and shown:find("report ready"), "the report finishes")
assertTrue(not text:find("ERROR"), "no step fails:\n" .. text)
assertTrue(text:find("Kit methods: [sC]") and text:find("clear and rebuild"), "it reports the method path and the benchmark")
