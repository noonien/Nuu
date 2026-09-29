-- The UI suites' shared start: the whole addon, every file of NuuRoad.toc,
-- loaded on NuuKit and the kit's stand-in for the client's frame API
-- (../NuuKit/Tests/Support/Frames.lua), then PLAYER_LOGIN. The kit's reset
-- audit is on, as in development, so every change a screen makes to a kit
-- widget must be marked.
--
--   local ctx = dofile("Tests/UI/Harness.lua")
--   ctx.ns, ctx.UI, ctx.Kit, ctx.frames
--   ctx.check(value, message)   ctx.settle()   ctx.noErrors(when)
--   ctx.errors                  what reached the error handler so far
--
-- Loaded once per run: later suites get the same addon and stand-in. It
-- installs the stand-in in _G, so the UI suites run last.
if rawget(_G, "NuuRoadUIHarness") then return rawget(_G, "NuuRoadUIHarness") end
_G = _G or _ENV

local frames = dofile("../NuuKit/Tests/Support/Frames.lua")
local Object = frames.Object

-- Text measured from its font size, as the kit's smoke tests do: about 6
-- units a letter and 2 of leading at size 12.
function Object:SetFont(_, size) self.fontSize = size; return true end
function Object:GetFont() return "Fonts\\FRIZQT__.TTF", self.fontSize or 11, "" end
function Object:GetStringHeight() return (self.fontSize or 12) + 2 end
function Object:GetStringWidth() return #(self.text or "") * 6 * (self.fontSize or 12) / 12 end
function Object:GetUnboundedStringWidth() return self:GetStringWidth() end
local createFontString = Object.CreateFontString
function Object:CreateFontString(name, layer, template)
    local text = createFontString(self, name, layer, template)
    if template then text.fontSize = 12 end
    return text
end
function Object:SetToDefaults()
    self.alpha, self.strata = 1, nil
    self.level = (self.parent and self.parent.level or 0) + 1
    self.shown, self.enabled = true, true
    self.width, self.height, self.points = 0, 0, {}
    self.scripts, self.hooks = {}, {}
    self.mouse, self.attributes = false, nil
    self.text = nil
    if self.kind == "FontString" then self.fontSize = nil end
end
function Object:EnableMouse(on) self.mouse = on and true or false end
function Object:IsMouseEnabled() return self.mouse ~= false end

-- Where each line of the stack is, as the client names addon files: the
-- kit's under NuuKit, the planner's under NuuRoad, so the audit tells
-- the addon's calls from the kit's.
_G.debugstack = function(start, count)
    local lines, level = {}, (start or 1) + 1
    for _ = 1, count or 12 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.what == "C" then
            lines[#lines + 1] = "[C]: ?"
        elseif info.what == "tail" then
            lines[#lines + 1] = "(tail call): ?"
        else
            local src = info.short_src:gsub("^%./", "")
            local path = src:match("^%.%./NuuKit/(.*)$")
            path = path and ("Interface/AddOns/NuuKit/" .. path) or ("Interface/AddOns/NuuRoad/" .. src)
            lines[#lines + 1] = path .. ":" .. (info.currentline or 0) .. ": in function"
        end
        level = level + 1
    end
    return table.concat(lines, "\n") .. "\n"
end

-- What reaches the error handler: the screens report there, and the
-- audit's findings on release.
local errors = {}
_G.geterrorhandler = function() return function(err) table.insert(errors, tostring(err)) end end

-- The kit as the client loads it in development, the audit included.
local kitNS = {}
for line in io.lines("../NuuKit/NuuKit.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file and file ~= "NuuKit.lua" and (not file:match("^Dev/") or file == "Dev/Audit.lua") then
        assert(loadfile("../NuuKit/" .. file))("NuuKit", kitNS)
    end
end
local Kit = kitNS.Kit
local UI = Kit.UI
_G.NuuKit = Kit
assert(UI.SetAudit(true), "the audit runs on the stand-in")

-- The addon, every file in its TOC's order, then PLAYER_LOGIN.
local ns = {}
for line in io.lines("NuuRoad.toc") do
    local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if file then assert(loadfile(file))("NuuRoad", ns) end
end
ns:Initialize()

local function check(value, message)
    if not value then error(message, 2) end
end
local function settle()
    UI.LayoutNow()
    frames.tick()
    UI.LayoutNow()
end
local function noErrors(when)
    if #errors > 0 then error(when .. ": " .. table.concat(errors, "\n"), 2) end
end

local ctx = {
    ns = ns, Kit = Kit, UI = ns:GetUI(), frames = frames, errors = errors,
    check = check, settle = settle, noErrors = noErrors,
}
_G.NuuRoadUIHarness = ctx
noErrors("login")
return ctx
