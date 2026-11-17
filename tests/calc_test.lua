-- Offline check of Calc.lua with stubbed prices. Run: lua tests/calc_test.lua
local resaleMode = "off"
local ns = { Opt = function(k) if k == "resale" then return resaleMode elseif k == "ahChance" then return 0.8 end return 0.05 end }
local depositEach = 0
ns.Deposit = function() return depositEach end
ns.AHNetPerUnit = function(id)
  local ah = ns.AHPrice(id)
  return ah and math.floor(ah * 0.95 - depositEach * 0.2) or nil
end
local prices = { [1] = {10, "vendor"}, [2] = {50, "ah"} }
ns.VENDOR_SEED = {}
ns.BuyPrice = function(id) local p = prices[id]; if p then return p[1], p[2] end end
ns.AHPrice = function(id) if id == 9 then return 1000 elseif id == 50 then return 200 end end
ns.VendorBuy = function(id) return nil end
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

-- resale: A costs 140c and vendors for 300c; with resale on its net is -160c
resaleMode = "vendor"
local rr = ns.Evaluate({ recipes = { { out = 9, qty = 1, diff = 0, ups = 1, reagents = { {item = 1, count = 4}, {item = 2, count = 2} } } } })
assert(rr[1].cost == 140 and rr[1].resale == 300 and rr[1].net == -160 and rr[1].perUp == -160)
resaleMode = "ah" -- AH net 950
rr = ns.Evaluate({ recipes = { { out = 9, qty = 1, diff = 0, ups = 1, reagents = { {item = 1, count = 4}, {item = 2, count = 2} } } } })
assert(rr[1].resale == 950)
-- the route prefers the recipe with the better NET: cheap-but-worthless vs dear-but-vendors-high
resaleMode = "vendor"
prices[5] = {10, "vendor"}; prices[6] = {100, "vendor"}
local W = { id = 7, out = 8, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 5, count = 1} } }   -- 10c, no sale value
local V = { id = 8, out = 9, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 6, count = 1} } }   -- 100c, sells 300c
local pv = { skill = 10, max = 40, recipes = { W, V } }
local plv = ns.Plan(pv, 12, { pv }, false)
assert(plv.segs[1].row.r == V, "net-best recipe wins")
assert(plv.cost == -400 and plv.gross == 200, plv.cost) -- 2 pts: net -200 each, gross 100 each
resaleMode = "off"
assert(ns.Plan(pv, 12, { pv }, false).segs[1].row.r == W, "off: gross-cheapest wins")

-- recipes taught by an item: pattern item 50 is on the AH for 200c
resaleMode = "off"
local T2 = { id = 20, out = 32, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 1, count = 1} },
  teach = { { item = 50, rank = 12, rep = false } } }
local pt2 = { skill = 10, max = 40, recipes = { L }, unlearned = { T2 } }
local pl = ns.Plan(pt2, 20, { pt2 }, true)
assert(#pl.learn == 1 and pl.learn[1].how == "ah" and pl.learn[1].fee == 200 and pl.learn[1].item == 50)
local hasRecipeItem
for _, it in ipairs(pl.shop) do if it.recipe and it.item == 50 then hasRecipeItem = true end end
assert(hasRecipeItem, "recipe item on the shopping list")
assert(pl.cost == 200 + 80 and pl.learnCost == 200)
-- no price for the pattern: recipe unavailable, route stays on the learned recipe
T2.teach[1].item = 51
local pl2 = ns.Plan(pt2, 20, { pt2 }, true)
assert(#pl2.learn == 0 and pl2.cost == 1000)
-- and the AH search list asks for the pattern item
local miss = ns.MissingItems({ pt2 }, false, true)
local found51 = false
for _, id in ipairs(miss) do if id == 51 then found51 = true end end
assert(found51)
-- a reputation-locked vendor pattern with no AH price stays unavailable
ns.VendorBuy = function(id) if id == 52 then return 300 end end
T2.teach = { { item = 52, rank = 12, rep = true } }
assert(ns.TeachOption(T2) == nil)
T2.teach[1].rep = false
assert(ns.TeachOption(T2).how == "vendor")

-- deposit: with 100c deposit and an 80% sale chance the AH figure loses 20c
depositEach = 100
local _, ah2 = ns.Revenue({ out = 9, qty = 1 })
assert(ah2 == 930, ah2)
depositEach = 0

-- intermediates become inline prep steps: user recipe needs 3 of item 15, made 2 at a time from 4 of item 1
local inter2 = { id = 40, out = 15, qty = 2, diff = 3, ups = 1, trivial = 5, reagents = { {item = 1, count = 4} } }
local user2 = { id = 41, out = 9, qty = 1, diff = 0, ups = 1, trivial = 40, reagents = { {item = 15, count = 3} } }
local prof3 = { skill = 10, max = 40, recipes = { inter2, user2 } }
local plan3 = ns.Plan(prof3, 12, { prof3 }, false)
local seg3 = plan3.segs[1]
assert(seg3.row.r == user2 and #seg3.prep == 1, "one prep step")
assert(seg3.prep[1].item == 15 and seg3.prep[1].units == 6 and seg3.prep[1].crafts == 3, seg3.prep[1].crafts)
assert(seg3.prep[1].recipe == inter2)

-- locking and skill drift: forced picks win while usable; the route starts from the current skill
local FA = { id = 60, out = 70, qty = 1, diff = 0, ups = 1, trivial = 60, reagents = { {item = 1, count = 1} } }   -- 10c
local FB = { id = 61, out = 71, qty = 1, diff = 0, ups = 1, trivial = 60, reagents = { {item = 2, count = 1} } }   -- 50c
local pf = { skill = 14, scanSkill = 10, max = 60, recipes = { FA, FB } }
local free = ns.Plan(pf, 18, { pf }, false)
assert(free.segs[1].from == 14 and free.segs[1].row.r == FA, "starts from the current skill")
local locked = ns.Plan(pf, 18, { pf }, false, ns.ForceFromPicks({ { id = 61, from = 14, to = 16 } }))
assert(locked.segs[1].row.r == FB and locked.segs[1].to == 16 and locked.segs[2].row.r == FA, "forced picks first, then best")
local picks = ns.PlanPicks(locked)
assert(#picks == 2 and picks[1].id == 61 and picks[2].id == 60)
-- a forced recipe that became unusable is dropped
FB.reagents = { {item = 999, count = 1} }
local fallback = ns.Plan(pf, 18, { pf }, false, ns.ForceFromPicks({ { id = 61, from = 14, to = 16 } }))
assert(fallback.segs[1].row.r == FA)
print("calc ok")
