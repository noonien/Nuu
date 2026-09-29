-- Build-time reader for the RestedXP guide DSL. Developer tooling: it is not
-- in NuuRoad.toc, never ships, and the addon never reads a source addon's
-- directory at runtime.
--
-- It reads text and only text. `RXPGuides.RegisterGuide([[ ... ]])` is found by
-- scanning, the long-string body is taken verbatim, and every line is matched
-- with patterns. Nothing is loadstring'd, nothing is executed, and no WoW API
-- is called, so a malformed or hostile source file can only produce a parse
-- error. Every step and command keeps the source line it came from, so the
-- conversion report can point at the input.
local RestedXP = {}

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- A trailing `<< Warrior/Shaman` or `<< !Tauren` gates the line it sits on.
local function splitGate(text)
    local body, gate = text:match("^(.-)%s*<<%s*(.+)$")
    if not body then return text, nil end
    return trim(body), trim(gate)
end

-- `.accept 747 >>Accept The Hunt Begins` is one command, its arguments, and the
-- text RestedXP shows for it. The text is the author's prose and is kept for
-- the reviewer; NuuRoad writes its own.
local function parseCommand(line, number)
    local name, rest = line:match("^%.([%a]+)%s*(.*)$")
    if not name then return nil end
    rest = trim(rest)
    local args, display = rest:match("^(.-)%s*>>%s*(.*)$")
    if not args then args, display = rest, nil end
    local gate
    args, gate = splitGate(args)
    local command = { name = name, args = trim(args), display = display and trim(display) or nil,
        gate = gate, line = number }
    -- A gate can also sit after the display text.
    if command.display then
        local body, displayGate = splitGate(command.display)
        if displayGate then command.display, command.gate = body, command.gate or displayGate end
    end
    return command
end

-- Returns a list of registrations. Each is { meta, steps, line }, where a step
-- is { gate, directives, commands, display, line }.
function RestedXP:Parse(text, sourceName)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end

    local registrations = {}
    local index = 1
    while index <= #lines do
        if lines[index]:find("RegisterGuide%s*%(%s*%[%[") then
            local registration = { meta = { flags = {}, source = sourceName, line = index }, steps = {} }
            local step = nil
            index = index + 1
            while index <= #lines and not lines[index]:match("^%s*%]%]%s*%)") do
                local raw = lines[index]
                local line = trim(raw)
                if line == "" or line:match("^%-%-") then
                    -- blank or comment
                elseif line == "step" or line:match("^step%s") then
                    local _, gate = splitGate(line)
                    step = { gate = gate, directives = {}, commands = {}, display = {}, line = index }
                    table.insert(registration.steps, step)
                elseif line:match("^#") then
                    local name, value = line:match("^#([%a/%-]+)%s*(.*)$")
                    if name then
                        local entry = { name = name, value = trim(value), line = index }
                        if step then table.insert(step.directives, entry)
                        else
                            -- Header directives before the first step describe
                            -- the guide itself.
                            local meta = registration.meta
                            if name == "name" then meta.name = entry.value
                            elseif name == "group" then meta.group = entry.value
                            elseif name == "subgroup" then meta.subgroup = entry.value
                            elseif name == "next" then meta.next = entry.value
                            elseif name == "version" then meta.version = entry.value
                            elseif name == "defaultfor" then meta.defaultFor = entry.value
                            elseif name == "xprate" then meta.xprate = entry.value
                            else meta.flags[name] = entry.value ~= "" and entry.value or true end
                        end
                    end
                elseif line:match("^%.") then
                    local command = parseCommand(line, index)
                    if not command then error(sourceName .. ":" .. index .. ": cannot read command '" .. line .. "'") end
                    if step then
                        table.insert(step.commands, command)
                    elseif not registration.meta.flags.internal then
                        -- An #internal registration is the author's scratch list of
                        -- points, not a guide; anywhere else a stray command is an error.
                        error(sourceName .. ":" .. index .. ": command outside a step")
                    end
                elseif line:match("^>>") or line:match("^%+") or line:match("^%*") then
                    -- `>>` is the step's text; `+` and `*` are further lines of it.
                    local body = line:gsub("^>>", ""):gsub("^[%+%*]", "")
                    local text, gate = splitGate(trim(body))
                    if step then table.insert(step.display, { text = text, gate = gate, line = index }) end
                elseif line:match("^<<") then
                    -- A faction gate on the guide as a whole.
                    registration.meta.faction = trim(line:gsub("^<<", ""))
                else
                    error(sourceName .. ":" .. index .. ": unrecognised line '" .. line .. "'")
                end
                index = index + 1
            end
            table.insert(registrations, registration)
        end
        index = index + 1
    end
    return registrations
end

function RestedXP:ParseFile(path)
    local handle = assert(io.open(path, "r"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return self:Parse(text, path:match("([^/]+)$") or path)
end

-- Every construct the parse found, counted, for the coverage gate.
function RestedXP:Census(registrations)
    local commands, directives = {}, {}
    for _, registration in ipairs(registrations) do
        for _, step in ipairs(registration.steps) do
            for _, command in ipairs(step.commands) do
                commands[command.name] = (commands[command.name] or 0) + 1
            end
            for _, directive in ipairs(step.directives) do
                directives[directive.name] = (directives[directive.name] or 0) + 1
            end
        end
    end
    return commands, directives
end

return RestedXP
