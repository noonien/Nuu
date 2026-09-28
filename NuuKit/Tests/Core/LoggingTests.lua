local Kit = _G.LoadKit().Kit

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local printed = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(printed, message) end }

-- Each addon gets its own prefix and its own debug switch, kept on its table.
local debugging = false
local road = Kit.AddLogging({ name = "NuuRoad" }, { debug = function() return debugging end })
local prof = Kit.AddLogging({ name = "NuuProfessions" }, { label = "Nuu Professions" })

road:Print("hello")
assertEquals(printed[1], "|cff4cc9f0NuuRoad|r: hello", "Print names the addon")
prof:Print("hi")
assertEquals(printed[2], "|cff4cc9f0Nuu Professions|r: hi", "and a label replaces the name")

road:Log("quiet")
assertEquals(#printed, 2, "Log is silent while the addon is not debugging")
debugging = true
road:Log("loud")
assertEquals(printed[3], "|cff4cc9f0NuuRoad|r: |cff8899aa[debug]|r loud", "and prints while it is")
prof:Log("never")
assertEquals(#printed, 3, "an addon without a debug switch never logs")
local broken = Kit.AddLogging({ name = "Broken" }, { debug = function() error("settings not loaded") end })
broken:Log("guarded")
assertEquals(#printed, 3, "a debug switch that throws is read as off")

-- Without a recorder the log calls are safe and keep nothing.
assertEquals(road:Record("rec", {}), nil, "Record before a recorder keeps nothing")
assertEquals(road:RecordHere("rec", {}), nil, "nor RecordHere")
assertEquals(road:Trace("rec", {}), nil, "nor Trace")
assertEquals(road:Tracing(), false, "and tracing is off")

-- With one, they reach it.
local calls = {}
road.recorder = {
    Record = function(_, channel) table.insert(calls, "Record " .. channel); return "r" end,
    RecordHere = function(_, channel) table.insert(calls, "RecordHere " .. channel); return "h" end,
    Trace = function(_, channel) table.insert(calls, "Trace " .. channel); return "t" end,
    Tracing = function() return true end,
}
assertEquals(road:Record("a", {}), "r", "Record reaches the recorder")
assertEquals(road:RecordHere("b", {}), "h", "and RecordHere")
assertEquals(road:Trace("c", {}), "t", "and Trace")
assertEquals(road:Tracing(), true, "and Tracing")
assertEquals(table.concat(calls, ","), "Record a,RecordHere b,Trace c", "each to its own call")
assertEquals(prof:Record("a", {}), nil, "and another addon's recorder is its own")

_G.DEFAULT_CHAT_FRAME = nil
print("NuuKit logging tests passed")
