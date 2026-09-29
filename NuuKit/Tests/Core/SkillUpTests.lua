local Kit = _G.LoadKit().Kit
local SkillUp = Kit.SkillUp
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Orange 10, yellow 20, green 25, grey 30.
local skills = { 10, 20, 25, 30 }
assert(SkillUp:Chance(skills, 9) == 0, "below the learn skill it cannot be made")
assert(SkillUp:Chance(skills, 10) == 1 and SkillUp:Chance(skills, 19) == 1, "orange always gives a point")
assert(SkillUp:Chance(skills, 20) == 1, "yellow starts at (R - Y) / (R - Y)")
assert(near(SkillUp:Chance(skills, 25), 0.5), "green is about half")
assert(near(SkillUp:Chance(skills, 29), 0.1))
assert(SkillUp:Chance(skills, 30) == 0 and SkillUp:Chance(skills, 90) == 0, "grey gives nothing")
assert(SkillUp:Chance({ 1, 20, 20, 20 }, 15) == 1, "yellow not below grey is read as orange until grey")

assert(SkillUp:Color(skills, 5) == "unknown")
assert(SkillUp:Color(skills, 10) == "orange")
assert(SkillUp:Color(skills, 20) == "yellow")
assert(SkillUp:Color(skills, 25) == "green")
assert(SkillUp:Color(skills, 30) == "grey")

assert(SkillUp:AboveFloor(skills, 25) and not SkillUp:AboveFloor(skills, 29), "the floor is 0.15 by default")
assert(SkillUp:AboveFloor(skills, 29, 0.05), "and a parameter")

-- One point is geometric: expected 1/p, variance (1-p)/p^2.
local e, v = SkillUp:Point(skills, 25)
assert(near(e, 2) and near(v, 2))
assert(SkillUp:Point(skills, 30) == nil)

-- A span adds the points up.
e, v = SkillUp:Span(skills, 10, 20)
assert(near(e, 10) and near(v, 0), "an orange span is one craft a point, no spread")
e, v = SkillUp:Span(skills, 25, 27)
assert(near(e, 1 / 0.5 + 1 / 0.4) and near(v, 2 + 0.6 / 0.16), "two green points: " .. e .. " " .. v)
assert(SkillUp:Span(skills, 28, 31) == nil, "a span into grey cannot be finished")
e, v = SkillUp:Span(skills, 12, 12)
assert(e == 0 and v == 0, "an empty span costs nothing")

-- Confidence: z standard deviations over the expected count, whole crafts.
assert(SkillUp:Z("typical") == 0 and SkillUp:Z("safe") == 1.3 and SkillUp:Z("sure") == 2.3)
assert(SkillUp:Z(nil) == 1.3, "safe is the default")
assert(SkillUp:Count(4.5, 5.75, 0) == 5)
assert(SkillUp:Count(4.5, 5.75, 1.3) == math.ceil(4.5 + 1.3 * math.sqrt(5.75)))
assert(SkillUp:Count(10, 0, 2.3) == 10, "no spread, no margin")
local low, high = SkillUp:Range(4.5, 5.75, 1.3, 2)
assert(low == 2 and high == 8, "never fewer crafts than points: " .. low .. " " .. high)
low, high = SkillUp:Range(10, 0, 1.3, 10)
assert(low == 10 and high == 10)

-- Goals have a count, not a skill: the expected points they give.
assert(near(SkillUp:Gain(skills, 10, 5), 5), "five orange crafts, five points")
assert(SkillUp:Gain(skills, 30, 5) == 0, "grey crafts give nothing")
local gain = SkillUp:Gain(skills, 25, 2)
assert(near(gain, 0.5 + 0.5), "two crafts at a half chance give about one point")

return true
