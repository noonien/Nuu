local Kit = _G.LoadKit().Kit
local UI = Kit.UI

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function near(a, b) return math.abs(a - b) < 0.002 end

-- Table columns: fixed widths first, the rest shared by weight, in order.
local spots = UI.TableColumns({ { grow = true }, { width = 50 }, { grow = 2 }, { width = 100 } }, 500)
-- 500 less 10 + 8 padding and 3 gaps of 12 leaves 446; 296 to share 1:2.
assertEquals(spots[1].x, 10, "the first column starts in from the edge")
assertEquals(near(spots[1].w, 296 / 3), true, "a growing column takes its share")
assertEquals(spots[2].w, 50, "a fixed column keeps its width")
assertEquals(near(spots[3].w, 296 * 2 / 3), true, "and a heavier one takes more")
assertEquals(near(spots[4].x + spots[4].w, 492), true, "the last ends at the right padding")
assertEquals(UI.TableColumns({ { width = 400 }, { grow = true } }, 300)[2].w, 0, "a column with no room left is empty, never negative")

print("NuuKit UI display tests passed")
