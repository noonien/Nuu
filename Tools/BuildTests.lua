-- The built addons (Tools/Build.py) loaded as the client loads a release:
-- every file of each built TOC, in order, with the addon's own ns, on the
-- kit's stand-in for the client (NuuKit/Tests/Support/Frames.lua), with no
-- NuuKit addon. Each is initialized and its window opened. Run from the
-- repository root; Tools/Build.py runs it on each addon alone, then on all
-- of them together.
--
--   lua Tools/BuildTests.lua <dist folder> <Addon> [<Addon> ...]
_G = _G or _ENV

local out = assert(arg[1], "usage: lua Tools/BuildTests.lua <dist folder> <Addon> ...")
local names = { select(2, unpack(arg)) }
assert(#names > 0, "name at least one built addon")

local frames = dofile("NuuKit/Tests/Support/Frames.lua")
local Object = frames.Object

-- Text measured from its font size, as the UI suites do.
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 11, "" end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end

local errors = {}
_G.geterrorhandler = function() return function(err) table.insert(errors, tostring(err)) end end

local function check(value, message)
    if not value then error(message, 2) end
end

local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close() end
    return file ~= nil
end

-- A client path under Interface\AddOns, as a file in the dist folder.
local function builtFile(path)
    local rel = path:gsub("\\", "/"):match("^Interface/AddOns/(.+)$")
    if not rel then return nil end
    if not rel:match("%.%w+$") then rel = rel .. ".tga" end
    return out .. "/" .. rel
end

-- The globals the addons may add: their ns, saved variables, slash commands,
-- key binding names, and the kit's named windows (<addon>_<key>_Window).
local before = {}
for key in pairs(_G) do before[key] = true end
local function allowedGlobal(key)
    if type(key) ~= "string" then return false end
    if key:match("^SLASH_") or key:match("^BINDING_") then return true end
    for _, name in ipairs(names) do
        if key:sub(1, #name) == name then return true end
    end
    return false
end

-- Each addon's files in its built TOC's order.
local loaded = {}
for _, name in ipairs(names) do
    local ns = {}
    local count = 0
    for line in io.lines(out .. "/" .. name .. "/" .. name .. ".toc") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then
            check(not file:match("^Dev/") and not file:match("NuuKit%.lua$"), name .. ": ships " .. file)
            assert(loadfile(out .. "/" .. name .. "/" .. file))(name, ns)
            count = count + 1
        end
    end
    loaded[#loaded + 1] = { name = name, ns = ns, files = count }
end
check(rawget(_G, "NuuKit") == nil, "a release publishes no _G.NuuKit")

local WINDOWS = { NuuRoad = "MainWindow", NuuProfessions = "PlannerPanel" }
for _, entry in ipairs(loaded) do
    local name, ns = entry.name, entry.ns
    local Kit = ns.Kit
    check(rawget(_G, name) == ns, name .. ": _G." .. name .. " is the addon's ns")
    check(Kit and Kit.UI, name .. ": the embedded kit is loaded")
    check(Kit.folder == "Libs\\NuuKit\\", name .. ": the kit knows where it sits")
    check(Kit.Loaded == nil and Kit.loadOrder == nil, name .. ": the load probe is left out")
    check(not Kit.UI.audit and Kit.UI.AuditFlags == nil, name .. ": the reset audit is left out")
    for _, other in ipairs(loaded) do
        check(other == entry or other.ns.Kit ~= Kit, name .. " and " .. other.name .. " share a kit")
    end

    -- Every theme's art is where the kit will look for it.
    local prefix = "Interface\\AddOns\\" .. name .. "\\Libs\\NuuKit\\Media\\"
    check(Kit.UI.MediaPath("x") == prefix .. "x", name .. ": media path " .. Kit.UI.MediaPath("x"))
    for key, theme in pairs(Kit.UI.themes) do
        for part, value in pairs(theme.art or {}) do
            local file = type(value) == "table" and value.file or value
            check(exists(builtFile(Kit.UI.MediaPath(file))), name .. ": theme " .. key .. " " .. part .. " is missing")
        end
    end

    ns:Initialize()
    local window = WINDOWS[name] and ns.modules[WINDOWS[name]]
    if window then window:Toggle() end
    Kit.UI.LayoutNow()
    frames.tick()
    check(#errors == 0, name .. ": " .. table.concat(errors, "\n"))
end

-- Every texture the addons set from their own folders is shipped.
for _, o in ipairs(frames.objects) do
    local path = type(o.texture) == "string" and builtFile(o.texture)
    if path then check(exists(path), "texture set but not shipped: " .. o.texture) end
end

local added, bindings = {}, 0
for key in pairs(_G) do
    if not before[key] then
        check(allowedGlobal(key), "unexpected global: " .. tostring(key))
        if key:match("^BINDING_") then bindings = bindings + 1 else added[#added + 1] = key end
    end
end
table.sort(added)
if bindings > 0 then added[#added + 1] = bindings .. " key binding names" end

local parts = {}
for _, entry in ipairs(loaded) do parts[#parts + 1] = entry.name .. " (" .. entry.files .. " files)" end
print("built " .. table.concat(parts, " + ") .. " loaded, initialized and opened; globals: " .. table.concat(added, ", "))
