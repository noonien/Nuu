-- How big each guide is through the codec, not shipped behaviour. Run from
-- the addon root:
--
--   lua Tools/GuideSizes.lua
--
-- Every guide NuuRoad.toc lists (fixtures included) and the format's worked
-- example, as its file on disk, as guide text (the editor's Copy as text),
-- as the codec's bytes (Data/GuideShare.lua) and as the nuu: string a player
-- shares. Fails on a guide that does not encode.
dofile("Tests/Support/Namespace.lua")
local ns = NewNamespace()
Load(ns, "Data/IDNames.lua")
Load(ns, "Data/GuideText.lua")
Load(ns, "Domain/GuideDraft.lua")
Load(ns, "Data/GuideCodec.lua")
Load(ns, "Data/GuideShare.lua")
local GuideShare, GuideCodec, GuideText = ns.modules.GuideShare, ns.modules.GuideCodec, ns.modules.GuideText
local Codec = ns.Kit.Codec

local function size(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local n = file:seek("end")
    file:close()
    return n
end

local rows, files = {}, {}
local function add(guide, path)
    local bytes, problem = GuideShare:Encode(guide)
    assert(bytes, guide.id .. " encodes: " .. tostring(problem))
    local steps = 0
    for _, section in ipairs(guide.data and guide.data.sections or {}) do
        for _, entry in ipairs(section.steps or {}) do
            steps = steps + (entry.group and #entry.group or 1)
        end
    end
    -- A file holding several guides counts once in the total.
    local file = size(path)
    rows[#rows + 1] = { id = guide.id, steps = steps, file = file, fileOnce = not files[path] and file or 0,
        text = #GuideText:Write(guide), bytes = #bytes, shared = #Codec.ToText(GuideCodec.SCHEMA, bytes) }
    files[path] = true
end

ns.packagedGuides = {}
for line in io.lines("NuuRoad.toc") do
    local path = line:match("^%s*(Data/Guides/[^%s]*%.lua)%s*$") or line:match("^%s*(Dev/Fixtures/[^%s]*%.lua)%s*$")
    if path then
        local before = #ns.packagedGuides
        Load(ns, path)
        for i = before + 1, #ns.packagedGuides do add(ns.packagedGuides[i], path) end
    end
end
add(dofile("docs/examples/guide-source.lua"), "docs/examples/guide-source.lua")
table.sort(rows, function(a, b) return a.bytes > b.bytes end)

local function kb(n) return n and ("%.1f"):format(n / 1024) or "-" end
local function pct(n, of) return ("%d%%"):format(math.floor(n * 100 / of + 0.5)) end
local line = "%-48s %6s %9s %9s %9s %9s %7s %7s"
print(line:format("guide", "steps", "file KB", "text KB", "bytes KB", "nuu: KB", "b/text", "B/step"))
local total = { steps = 0, fileOnce = 0, text = 0, bytes = 0, shared = 0 }
for _, row in ipairs(rows) do
    print(line:format(row.id, row.steps, kb(row.file), kb(row.text), kb(row.bytes), kb(row.shared),
        pct(row.bytes, row.text), row.steps > 0 and math.floor(row.bytes / row.steps + 0.5) or "-"))
    for key in pairs(total) do total[key] = total[key] + (row[key] or 0) end
end
print(line:format(("total (%d guides)"):format(#rows), total.steps, kb(total.fileOnce), kb(total.text), kb(total.bytes),
    kb(total.shared), pct(total.bytes, total.text), math.floor(total.bytes / total.steps + 0.5)))
