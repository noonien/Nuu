-- What every architecture shares: two themes, text sizes, colour maths and
-- the stack sum. None of it is what the bench compares.

local C = {}

C.themes = {
    midnight = {
        window = { 0.05, 0.06, 0.08, 1 }, surface = { 0.08, 0.09, 0.11, 1 }, raised = { 0.12, 0.13, 0.16, 1 },
        border = { 0.22, 0.24, 0.28, 1 }, text = { 0.92, 0.93, 0.95, 1 }, muted = { 0.6, 0.63, 0.7, 1 },
        accent = { 0.3, 0.6, 1, 1 }, danger = { 0.9, 0.3, 0.3, 1 }, done = { 0.3, 0.8, 0.4, 1 },
    },
    slate = {
        window = { 0.09, 0.1, 0.12, 1 }, surface = { 0.12, 0.13, 0.15, 1 }, raised = { 0.16, 0.17, 0.2, 1 },
        border = { 0.28, 0.3, 0.34, 1 }, text = { 0.9, 0.9, 0.92, 1 }, muted = { 0.58, 0.6, 0.64, 1 },
        accent = { 0.9, 0.6, 0.2, 1 }, danger = { 0.9, 0.3, 0.3, 1 }, done = { 0.3, 0.8, 0.4, 1 },
    },
}

C.looks = { { theme = "midnight", textScale = 1 }, { theme = "slate", textScale = 1.15 } }

C.textStyles = { body = { size = 12 }, title = { size = 16 }, number = { size = 11 }, label = { size = 11 } }

C.tones = { "neutral", "accent", "danger", "done" }

function C.Alpha(c, a) return { c[1], c[2], c[3], a } end

function C.Mix(a, b, x)
    return { a[1] + (b[1] - a[1]) * x, a[2] + (b[2] - a[2]) * x, a[3] + (b[3] - a[3]) * x, a[4] or 1 }
end

-- Hands out `available` along a stack: { size } fixed, { grow, min } growing.
function C.Distribute(items, available, gap)
    local fixed, weights = 0, 0
    for _, item in ipairs(items) do
        if item.grow then weights = weights + item.grow else fixed = fixed + (item.size or 0) end
    end
    local spare = math.max(0, available - fixed - gap * math.max(0, #items - 1))
    local out, offset = {}, 0
    for index, item in ipairs(items) do
        local size = item.size or 0
        if item.grow then size = math.max(item.min or 0, weights > 0 and spare * item.grow / weights or 0) end
        out[index] = { offset = offset, size = size }
        offset = offset + size + gap
    end
    return out
end

function C.AlignStart(align, available, total)
    if align == "center" then return math.max(0, (available - total) / 2) end
    if align == "right" then return math.max(0, available - total) end
    return 0
end

-- The sample screen's data: settings keys and item rows.
C.KEYS = { "sellBack", "showMap", "autoLoot" }
function C.Items(n)
    local items = {}
    for i = 1, n do items[i] = { name = "Item " .. i, count = 8 + (i % 3) } end
    return items
end

return C
