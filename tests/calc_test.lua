-- Offline check of Calc.lua with stubbed prices. Run: lua tests/calc_test.lua
local ns = { Opt = function() return 0.05 end }
local prices = { [1] = {10, "vendor"}, [2] = {50, "ah"} }
ns.VENDOR_SEED = {}
ns.BuyPrice = function(id) local p = prices[id]; if p then return p[1], p[2] end end
ns.AHPrice = function(id) return id == 9 and 1000 or nil end
ns.VendorSell = function(id) return id == 9 and 300 or nil end
assert(loadfile("Margin/Calc.lua"))("Margin", ns)

local recipe = { out = 9, qty = 1, diff = 0, ups = 1, reagents = { {item = 1, count = 4}, {item = 2, count = 2} } }
local cost = ns.RecipeCost(recipe)
assert(cost == 140, cost)
local v, a = ns.Revenue(recipe)
assert(v == 300 and a == 950)

local rows = ns.Evaluate({ recipes = { recipe, { out = 9, qty = 1, diff = 3, ups = 1, reagents = { {item = 3, count = 1} } } } })
assert(rows[1].vendorProfit == 160 and rows[1].ahProfit == 810)
assert(rows[2].missing == 1)
assert(#ns.ProfitRows(rows, "vendor") == 2 and #ns.ProfitRows(rows, "vendor", true) == 2)
local lv = ns.LevelingRows(rows)
assert(lv[1].perUp == 140)

-- crafted intermediate: item 5 is unpriced but craftable from 2x item 1 (10c each)
local inter = { out = 5, qty = 2, diff = 0, ups = 1, reagents = { {item = 1, count = 4} } }
local user = { out = 9, qty = 1, diff = 0, ups = 1, reagents = { {item = 5, count = 3} } }
local prof = { recipes = { inter, user } }
local r2 = ns.Evaluate(prof, { prof })
assert(r2[2].missing == 0 and r2[2].cost == 60, r2[2].cost) -- 3 * (40/2)
assert(r2[2].lines[1].src == "craft")
-- cycle guard: A needs B needs A, nothing priced
local a = { out = 7, qty = 1, diff = 0, ups = 1, reagents = { {item = 8, count = 1} } }
local b = { out = 8, qty = 1, diff = 0, ups = 1, reagents = { {item = 7, count = 1} } }
local pc = { recipes = { a, b } }
assert(ns.Evaluate(pc, { pc })[1].missing == 1)

-- route: at skill 10 -> 14. A is orange to 14 (cheap, 10c), B is orange but dearer (50c).
local A = { id = 1, out = 20, qty = 1, diff = 0, ups = 1, trivial = 30, reagents = { {item = 1, count = 1} } }
local B = { id = 2, out = 21, qty = 1, diff = 0, ups = 1, trivial = 30, reagents = { {item = 2, count = 1} } }
local pr = { skill = 10, max = 30, recipes = { A, B } }
local plan = ns.Plan(pr, 14, { pr })
assert(#plan.segs == 1 and plan.segs[1].row.r == A, "A wins")
assert(plan.segs[1].from == 10 and plan.segs[1].to == 14)
assert(plan.cost == 40 and plan.crafts == 4, plan.cost)
assert(plan.shop[1].item == 1 and plan.shop[1].count == 4)
-- an unpriced recipe is never chosen; with nothing priced the route is one gap
local C = { id = 3, out = 22, qty = 1, diff = 0, ups = 1, trivial = 30, reagents = { {item = 3, count = 1} } }
local pc2 = { skill = 10, max = 30, recipes = { C } }
local gp = ns.Plan(pc2, 13, { pc2 })
assert(#gp.segs == 1 and gp.segs[1].gap and gp.segs[1].to == 13)
-- yellow recipe turns to chance .25 once past the estimated green edge
assert(ns.RouteChance({ trivial = 30, diff = 1 }, 10, 10) == 0.75)
assert(ns.RouteChance({ trivial = 30, diff = 1 }, 10, 25) == 0.25)
assert(ns.RouteChance({ trivial = 30, diff = 3 }, 10, 10) == 0)
-- missing items: item 3 only
local mi = ns.MissingItems({ pc2 })
assert(#mi == 1 and mi[1] == 3)

-- trainer recipes: learned L costs 100c/craft; trainer recipe T costs 1c/craft, fee 50c, rank 12.
local L = { id = 1, out = 30, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 4, count = 1} } }
local Tr = { id = 2, out = 31, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 1, count = 1} },
  train = { rank = 12, fee = 50 } }
prices[4] = {100, "vendor"}; prices[1] = {10, "vendor"}
local pt = { skill = 10, max = 40, recipes = { L }, unlearned = { Tr } }
local noT = ns.Plan(pt, 20, { pt }, false)
assert(noT.cost == 1000 and #noT.learn == 0)             -- 10 points x 100c
local withT = ns.Plan(pt, 20, { pt }, true)
assert(#withT.learn == 1 and withT.learn[1].fee == 50, "trainer recipe chosen")
assert(withT.segs[1].row.r == L and withT.segs[1].to == 12)  -- before rank 12 only L
assert(withT.cost == 200 + 80, withT.cost)                -- 2 pts x100 + 8 pts x10c
-- fee too high: not worth learning
Tr.train.fee = 100000
local no2 = ns.Plan(pt, 20, { pt }, true)
assert(#no2.learn == 0 and no2.cost == 1000)
print("calc ok")
