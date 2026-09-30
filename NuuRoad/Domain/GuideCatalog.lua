local _, ns = ...

-- What the guide browser knows about guides, kept free of frames so it can be
-- tested: where a guide files itself, the folder tree those places make,
-- whether a guide suits the character, and what a search matches.
--
-- A guide's `meta.category` is a path of folders, outermost first, split on
-- "/": "Leveling/Kalimdor/The Barrens". Any depth is allowed, and a single
-- word ("leveling") is a path of one. Folders are matched without regard to
-- case, so two guides writing "Dungeons" and "dungeons" share one; the
-- first spelling met is the one shown.
local Catalog = {}

Catalog.SEPARATOR = "/"

local function trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

function Catalog:Path(guide)
    local category = guide and guide.meta and guide.meta.category
    local path = {}
    if type(category) == "string" then
        for part in (category .. self.SEPARATOR):gmatch("(.-)" .. self.SEPARATOR) do
            part = trim(part)
            if part ~= "" then table.insert(path, part) end
        end
    end
    if #path == 0 then path[1] = "Other" end
    return path
end

-- The path written back the way an author would type it.
function Catalog:PathText(path, from)
    local parts = {}
    for index = from or 1, #path do table.insert(parts, path[index]) end
    return table.concat(parts, " / ")
end

-- The folder key a path names: its parts lower-cased and joined.
function Catalog:Key(path, depth)
    local parts = {}
    for index = 1, depth or #path do table.insert(parts, string.lower(path[index])) end
    return table.concat(parts, self.SEPARATOR)
end

-- Fixtures are regression aids, filed under a top folder of that name.
function Catalog:IsFixture(guide)
    local top = string.lower(self:Path(guide)[1])
    return top == "fixtures" or top == "fixture"
end

local function levelKey(guide)
    local levels = guide.meta and guide.meta.levels
    return levels and levels[1] or 0
end

-- A folder's level is the lowest of the guides beneath it.
local function byLevelThenName(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return string.lower(a.name) < string.lower(b.name)
end

local function byLevelThenTitle(a, b)
    local la, lb = levelKey(a), levelKey(b)
    if la ~= lb then return la < lb end
    return string.lower(a.meta.title or "") < string.lower(b.meta.title or "")
end

-- The folder tree of `guides`. Every folder is
-- { name, path, key, depth, children = { folder... }, guides = { guide... }, total, level },
-- `path` the folder names from the top down to it, `guides` holding only the
-- ones filed directly in it, `total` counting the whole subtree and `level`
-- the lowest level in it. Folders sort by level then name, guides by level
-- then title. The root's `byKey` finds any
-- folder by its key.
function Catalog:Tree(guides)
    local root = { name = "", path = {}, key = "", depth = 0, children = {}, guides = {}, total = 0, level = math.huge }
    local folders = { [""] = root }
    for _, guide in ipairs(guides) do
        local path = self:Path(guide)
        local parent = root
        root.total = root.total + 1
        root.level = math.min(root.level, levelKey(guide))
        for depth = 1, #path do
            local key = self:Key(path, depth)
            local folder = folders[key]
            if not folder then
                local names = {}
                for index = 1, depth do names[index] = parent.path[index] or path[index] end
                folder = { name = path[depth], path = names, key = key, depth = depth, children = {}, guides = {}, total = 0,
                    level = math.huge }
                folders[key] = folder
                table.insert(parent.children, folder)
            end
            folder.total = folder.total + 1
            folder.level = math.min(folder.level, levelKey(guide))
            parent = folder
        end
        table.insert(parent.guides, guide)
    end
    local function order(folder)
        table.sort(folder.children, byLevelThenName)
        table.sort(folder.guides, byLevelThenTitle)
        for _, child in ipairs(folder.children) do order(child) end
    end
    order(root)
    root.byKey = folders
    return root
end

-- Every guide in `folder` and below it, in the order the tree shows them:
-- the folder's own guides first, then each subfolder's.
function Catalog:Under(folder)
    local list = {}
    local function walk(node)
        for _, guide in ipairs(node.guides) do table.insert(list, guide) end
        for _, child in ipairs(node.children) do walk(child) end
    end
    if folder then walk(folder) end
    return list
end

-- `guides` by level, then title, whatever folders they are filed in. Sorts
-- in place and returns the list.
function Catalog:Sort(guides)
    table.sort(guides, byLevelThenTitle)
    return guides
end

-- Where the character stands against the guide's level range: "now" inside
-- it, "later" below it, "past" above it; nil when either is unknown.
function Catalog:LevelFit(guide, level)
    local levels = guide.meta and guide.meta.levels
    if type(level) ~= "number" or level <= 0 or not levels then return nil end
    if level < levels[1] then return "later" end
    if level > levels[2] then return "past" end
    return "now"
end

-- Whether the guide's own `only` lets this character run it. `evaluate`
-- answers a condition true, false, or nil for unknown; only a definite no
-- rules a guide out.
function Catalog:ForCharacter(guide, evaluate)
    if not guide.condition or not evaluate then return true end
    return evaluate(guide.condition) ~= false
end

-- Everything a search looks through, lower-cased: title, folders, tags,
-- author, and whatever else the caller adds (quest titles, zone names).
function Catalog:SearchText(guide, extra)
    local meta = guide.meta or {}
    local parts = { meta.title or "", table.concat(self:Path(guide), " "), meta.author or "" }
    for _, tag in ipairs(meta.tags or {}) do table.insert(parts, tag) end
    if extra and extra ~= "" then table.insert(parts, extra) end
    return string.lower(table.concat(parts, " "))
end

-- A search is words, and a guide matches when it matches every word. A
-- number is a level: it matches a guide whose range holds it, and only a
-- guide with no range falls back to finding the digits in its text.
function Catalog:Matches(guide, query, text)
    local levels = guide.meta and guide.meta.levels
    for word in string.lower(query or ""):gmatch("%S+") do
        local number = word:match("^%d+$") and tonumber(word)
        if number and levels then
            if number < levels[1] or number > levels[2] then return false end
        elseif not string.find(text, word, 1, true) then
            return false
        end
    end
    return true
end

ns:RegisterModule("GuideCatalog", Catalog)
