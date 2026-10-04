local _, ns = ...

-- Results as text to copy out of the game, in the kit's copy window. The
-- experiments themselves never touch the kit, so they still see the client as
-- it is; only the windows are the kit's (the development copy, _G.NuuKit):
-- this one and the experiments window (Window.lua).
-- Without it, chat says where the results are instead.

-- "|" too: the window would draw a colour code instead of showing it.
local function escape(s)
    return (string.gsub(s, "[%c\"\\|\127-\255]", function(c)
        if c == "\n" then return "\\n" end
        if c == "\"" or c == "\\" then return "\\" .. c end
        return string.format("\\%03d", string.byte(c))
    end))
end

local function scalar(value)
    if type(value) == "string" then return "\"" .. escape(value) .. "\"" end
    return tostring(value)
end

local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta == "number" end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- One value as indented Lua-like lines; a list stays in its order.
local function write(lines, value, indent, prefix)
    if type(value) ~= "table" then
        lines[#lines + 1] = indent .. prefix .. scalar(value)
        return
    end
    if next(value) == nil then
        lines[#lines + 1] = indent .. prefix .. "{}"
        return
    end
    lines[#lines + 1] = indent .. prefix .. "{"
    local inner = indent .. "  "
    local n = #value
    for i = 1, n do write(lines, value[i], inner, "") end
    for _, key in ipairs(sortedKeys(value)) do
        if not (type(key) == "number" and key >= 1 and key <= n and key % 1 == 0) then
            local name = type(key) == "string" and string.match(key, "^[%a_][%w_]*$") and key
                or ("[" .. scalar(key) .. "]")
            write(lines, value[key], inner, name .. " = ")
        end
    end
    lines[#lines + 1] = indent .. "}"
end

function ns:ResultText(ids)
    local results = self:DB().results
    local lines = {}
    for _, id in ipairs(ids) do
        local result = results[id]
        if #lines > 0 then lines[#lines + 1] = "" end
        if not result then
            lines[#lines + 1] = id .. ": no results"
        else
            lines[#lines + 1] = string.format("%s: %s (%s)", id, tostring(result.status), tostring(result.title))
            lines[#lines + 1] = string.format("build %s, interface %s, %s, %s, %sms%s", tostring(result.build),
                tostring(result.interface), tostring(result.date), tostring(result.character), tostring(result.ms),
                result.inCombat and ", in combat" or "")
            ns.WriteResult(lines, result)
        end
    end
    return table.concat(lines, "\n")
end

-- What a run saw, as lines added to `lines`: its values, log and errors.
function ns.WriteResult(lines, result)
    write(lines, result.values or {}, "", "values = ")
    if result.log then write(lines, result.log, "", "log = ") end
    if result.errors then write(lines, result.errors, "", "errors = ") end
    return lines
end

-- The kit's UI, made once; nil when the development kit is not loaded.
function ns:UI()
    if self.ui then return self.ui end
    local Kit = rawget(_G, "NuuKit")
    if type(Kit) ~= "table" or type(Kit.NewUI) ~= "function" then return nil end
    self.ui = Kit.NewUI(self)
    return self.ui
end

-- Opens the copy window on the results of `ids` (a list); false when the
-- kit is not loaded.
function ns:ShowResults(ids)
    if not self:UI() then
        self:Print("NuuKit is not loaded, so there is no window: /reload, then "
            .. "python3 NuuExperiments/Tools/Results.py " .. table.concat(ids, " "))
        return false
    end
    if not self.copyWindow then
        self.copyWindow = self.ui:CopyWindow{ title = "Experiment results", width = 640, height = 520 }
    end
    self.copyWindow:Show(self:ResultText(ids), #ids == 1 and ("Experiment: " .. ids[1]) or "Experiment results")
    return true
end

-- The ids a /nuux run asked to see, shown together as each one finishes.
ns.showing = nil

function ns:ShowWhenDone(ids)
    self.showing = ids
end

function ns:Finished(id)
    local ids = self.showing
    if not ids then return end
    local wanted = false
    for _, each in ipairs(ids) do
        if each == id then wanted = true end
    end
    if not wanted then return end
    for _, each in ipairs(ids) do
        if self.running[each] then return end
    end
    self.showing = nil
    self:ShowResults(ids)
end
