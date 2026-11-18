time = os.time -- the WoW global
-- Offline check of Calc.lua with stubbed prices. Run: lua tests/calc_test.lua
local resaleMode = "off"
local oddsMode = "typical"
local ns = { Opt = function(k) if k == "resale" then return resaleMode elseif k == "ahChance" then return 0.8 elseif k == "odds" then return oddsMode end return 0.05 end }
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
local A = { id = 1, out = 20, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} } }
local B = { id = 2, out = 21, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 2, count = 1} } }
local pr = { skill = 10, max = 30, recipes = { A, B } }
local plan = ns.Plan(pr, 14, { pr })
assert(#plan.segs == 1 and plan.segs[1].row.r == A, "A wins")
assert(plan.segs[1].from == 10 and plan.segs[1].to == 14)
assert(plan.cost == 40 and plan.crafts == 4, plan.cost)
assert(plan.shop[1].item == 1 and plan.shop[1].count == 4)
-- an unpriced recipe is never chosen; with nothing priced the route is one gap
local C = { id = 3, out = 22, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 3, count = 1} } }
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
local L = { id = 1, out = 30, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 4, count = 1} } }
local Tr = { id = 2, out = 31, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} },
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
local W = { id = 7, out = 8, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 5, count = 1} } }   -- 10c, no sale value
local V = { id = 8, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 6, count = 1} } }   -- 100c, sells 300c
local pv = { skill = 10, max = 40, recipes = { W, V } }
local plv = ns.Plan(pv, 12, { pv }, false)
assert(plv.segs[1].row.r == V, "net-best recipe wins")
assert(plv.cost == -400 and plv.gross == 200, plv.cost) -- 2 pts: net -200 each, gross 100 each
resaleMode = "off"
assert(ns.Plan(pv, 12, { pv }, false).segs[1].row.r == W, "off: gross-cheapest wins")

-- recipes taught by an item: pattern item 50 is on the AH for 200c
resaleMode = "off"
local T2 = { id = 20, out = 32, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} },
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
local user2 = { id = 41, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 15, count = 3} } }
local prof3 = { skill = 10, max = 40, recipes = { inter2, user2 } }
local plan3 = ns.Plan(prof3, 12, { prof3 }, false)
local seg3 = plan3.segs[1]
assert(seg3.row.r == user2 and #seg3.prep == 1, "one prep step")
assert(seg3.prep[1].item == 15 and seg3.prep[1].units == 6 and seg3.prep[1].crafts == 3, seg3.prep[1].crafts)
assert(seg3.prep[1].recipe == inter2)

-- locking and skill drift: forced picks win while usable; the route starts from the current skill
local FA = { id = 60, out = 70, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} } }   -- 10c
local FB = { id = 61, out = 71, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 2, count = 1} } }   -- 50c
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

-- worst-case odds: yellow plans at 25%, green at the 5% floor, orange stays 100%, bands fade sooner
oddsMode = "worst"
assert(ns.Odds(0) == 1 and ns.Odds(1) == 0.25 and ns.Odds(2) == 0.05 and ns.Odds(3) == 0)
assert(ns.RouteChance({ trivial = 30, diff = 1 }, 10, 10) == 0.25)
assert(ns.RouteChance({ trivial = 30, diff = 0 }, 10, 10) == 1)
-- orange at s0=10, grey at 40, no Classic entry (gap 12): yellow from 40-24-2=14, green from 40-12-2=26
assert(ns.RouteChance({ trivial = 40, diff = 0 }, 10, 13) == 1)
assert(ns.RouteChance({ trivial = 40, diff = 0 }, 10, 14) == 0.25)
assert(ns.RouteChance({ trivial = 40, diff = 0 }, 10, 25) == 0.25)
assert(ns.RouteChance({ trivial = 40, diff = 0 }, 10, 26) == 0.05)
-- a yellow recipe plans 4 crafts per skill-up in worst case, not 1.33
local Yw = { id = 80, out = 81, qty = 1, diff = 1, ups = 1, trivial = 60, reagents = { {item = 1, count = 1} } }
local pyw = { skill = 10, max = 60, recipes = { Yw } }
local rowsYw = ns.Evaluate(pyw, { pyw })
assert(rowsYw[1].chance == 0.25 and rowsYw[1].perUp == 40, rowsYw[1].perUp)
oddsMode = "typical"
assert(ns.Evaluate(pyw, { pyw })[1].chance == 0.75)

-- unpriced patterns: skipped when the recipe's reagents cannot be priced, and when searched recently
MarginDB = { searched = {} }
local T3 = { id = 90, out = 91, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} },
  teach = { { item = 61, rank = 20, rep = false } } }
local T4 = { id = 92, out = 93, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 998, count = 1} },
  teach = { { item = 62, rank = 20, rep = false } } }
local pm = { skill = 10, max = 60, recipes = {}, unlearned = { T3, T4 } }
local m1 = ns.MissingItems({ pm }, false, true)
assert(#m1 == 1 and m1[1] == 61, "only the usable recipe's pattern")
MarginDB.searched[61] = time()
assert(#ns.MissingItems({ pm }, false, true) == 0, "recently searched items are not counted again")

-- profit must not make a low-odds recipe look better: a 1.0-chance profitable recipe beats a 0.05 one
oddsMode = "worst"; resaleMode = "vendor"
prices[7] = {10, "vendor"}; prices[8] = {10, "vendor"}
local Lo = { id = 100, out = 9, qty = 1, diff = 2, ups = 1, trivial = 400, reagents = { {item = 7, count = 1} } } -- green: 5%
local Hi = { id = 101, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 8, count = 1} } } -- orange: 100%
local pq = { skill = 10, max = 90, recipes = { Lo, Hi } }
local rq = ns.Evaluate(pq, { pq })
assert(rq[1].rankPer == 0 and rq[2].rankPer == 0)
local lvl = ns.LevelingRows(rq, true)
assert(lvl[1].r == Hi, "the reliable recipe ranks first")
local planq = ns.Plan(pq, 12, { pq }, false)
assert(planq.segs[1].row.r == Hi, "route uses the reliable recipe")
oddsMode = "typical"; resaleMode = "off"

-- all-recipes scope: unlearned and extra recipes join the evaluation only when asked
prices[20] = {10, "vendor"}
local known = { id = 200, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 20, count = 1} } }
local extra = { id = 201, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, extra = true, reagents = { {item = 20, count = 1} } }
local trn = { id = 202, out = 9, qty = 1, diff = 0, ups = 1, trivial = 400, train = { rank = 20, fee = 100 }, reagents = { {item = 20, count = 1} } }
local pall = { skill = 10, max = 60, recipes = { known }, unlearned = { trn }, every = { extra } }
assert(#ns.Evaluate(pall, { pall }, false, false) == 1)
assert(#ns.Evaluate(pall, { pall }, true, false) == 2)
local allRows = ns.Evaluate(pall, { pall }, false, true)
assert(#allRows == 3 and allRows[2].learn and allRows[2].learn.how == "trainer" and allRows[3].learn == nil)

-- observed colour edges narrow the estimate
MarginDB = { bands = {} }
oddsMode = "worst"
local rb = { id = 500, trivial = 60, diff = 0 }
assert(ns.RouteChance(rb, 10, 30) == 1, "no observations: the model keeps it orange until 60-24-2=34")
MarginDB.bands[500] = { y1 = 35, y2 = 40 }
assert(ns.RouteChance(rb, 10, 30) == 1, "observed orange until at least 35")
MarginDB.bands[500] = { y1 = 20, y2 = 25 }
assert(ns.RouteChance(rb, 10, 30) == 0.25, "observed yellow by 25: the model's 34 is pulled in")
MarginDB.bands[500] = { y1 = 35, y2 = 40 }
assert(ns.RouteChance(rb, 10, 36) == 0.25 or ns.RouteChance(rb, 10, 36) == 1) -- inside the range: either side is fine
-- observing: orange at 120, then yellow at 130
MarginDB.bands = {}
ns.ObserveBands({ { id = 7, diff = 0 } }, 120)
ns.ObserveBands({ { id = 7, diff = 1 } }, 130)
assert(MarginDB.bands[7].y1 == 121 and MarginDB.bands[7].y2 == 130 and MarginDB.bands[7].g1 == 131)
ns.ObserveBands({ { id = 7, diff = 1, train = true } }, 135) -- unlearned entries are not observations
assert(MarginDB.bands[7].g1 == 131)
oddsMode = "typical"
MarginDB = nil

-- owned intermediates reduce what is left to make, and the raw materials with it
local ownedNow = { [15] = 4 }
ns.Owned = function(id) return ownedNow[id] or 0 end
local plan4 = ns.Plan(prof3, 12, { prof3 }, false)
local pr4 = plan4.segs[1].prep[1]
assert(pr4.have == 4 and pr4.units == 2 and pr4.crafts == 1, pr4.crafts)   -- needs 6, holds 4: make 2 (one craft of 2)
local base1
for _, it in ipairs(plan4.shop) do if it.item == 1 then base1 = it.count end end
assert(base1 == 4, base1)                                                    -- one craft takes 4 of item 1
ownedNow[15] = 10
local plan5 = ns.Plan(prof3, 12, { prof3 }, false)
assert(plan5.segs[1].prep[1].crafts == 0 and plan5.segs[1].prep[1].have == 6)
local base1b = 0
for _, it in ipairs(plan5.shop) do if it.item == 1 then base1b = it.count end end
assert(base1b == 0, "nothing left to make, so no raw materials needed")
ns.Owned = function() return 0 end

-- the edges come from the grey level and the gap (Forever's gap is half Classic's)
oddsMode = "typical"
MarginDB = nil
-- Hillman's Leather Boots on Forever: grey at 160, orange at 134 turned yellow at 135-136
local boots = { id = 1255103, trivial = 160, diff = 0 }
assert(ns.RouteChance(boots, 134, 135) == 1 and ns.RouteChance(boots, 134, 136) == 0.75)
ns.GAP = { [900] = 20 }                      -- Classic gap 20 -> Forever gap 10: yellow from 100-20, green from 100-10
local gapped = { id = 900, trivial = 100, diff = 0 }
assert(ns.RouteChance(gapped, 10, 79) == 1 and ns.RouteChance(gapped, 10, 80) == 0.75)
assert(ns.RouteChance(gapped, 10, 89) == 0.75 and ns.RouteChance(gapped, 10, 90) == 0.25)
-- a recipe seen yellow now is yellow even when the model says it should still be orange
assert(ns.RouteChance({ id = 901, trivial = 200, diff = 1 }, 100, 100) == 0.75)
ns.GAP = nil
oddsMode = "typical"

-- all-recipes scope: unlearned recipes' reagents and every recipe's sale price join the unpriced list
MarginDB = { searched = {} }
local ek = { id = 300, out = 301, qty = 1, diff = 0, ups = 1, trivial = 50, extra = true, reagents = { {item = 777, count = 1} } }
local pe = { skill = 10, max = 60, recipes = {}, unlearned = {}, every = { ek } }
local plain = ns.MissingItems({ pe }, false, true, false)
assert(#plain == 0, "without the all scope the extra recipes are not looked up")
local withAll = ns.MissingItems({ pe }, false, true, true)
local got = {}
for _, id in ipairs(withAll) do got[id] = true end
assert(got[777] and got[301] and #withAll == 2, "reagent and sale price of the unlearned recipe")
MarginDB = nil

-- limiting the lookup to one profession
MarginDB = { searched = {} }
local ra = { id = 310, out = 311, qty = 1, diff = 0, ups = 1, trivial = 50, reagents = { {item = 880, count = 1} } }
local rbb = { id = 312, out = 313, qty = 1, diff = 0, ups = 1, trivial = 50, reagents = { {item = 881, count = 1} } }
local pa, pb = { skill = 10, max = 60, recipes = { ra } }, { skill = 10, max = 60, recipes = { rbb } }
local both = ns.MissingItems({ A = pa, B = pb }, false, false, false)
assert(#both == 2)
local onlyA = ns.MissingItems({ A = pa, B = pb }, false, false, false, "A")
assert(#onlyA == 1 and onlyA[1] == 880)
MarginDB = nil

-- the searched-recently memory can be ignored to explain an empty list
MarginDB = { searched = { [880] = time() } }
local pz = { skill = 10, max = 60, recipes = { { id = 320, out = 321, qty = 1, diff = 0, ups = 1, trivial = 50, reagents = { {item = 880, count = 1} } } } }
assert(#ns.MissingItems({ Z = pz }, false, false, false) == 0)
assert(#ns.MissingItems({ Z = pz }, false, false, false, nil, true) == 1)
MarginDB = nil

-- items that do not exist in the game are never "unpriced"
MarginDB = { searched = {} }
ns.ItemExists = function(id) return id ~= 881 end
local pn2 = { skill = 10, max = 60, recipes = { { id = 330, out = 331, qty = 1, diff = 0, ups = 1, trivial = 50, reagents = { {item = 880, count = 1}, {item = 881, count = 1} } } } }
local found = ns.MissingItems({ N = pn2 }, false, false, false)
assert(#found == 1 and found[1] == 880, "the item that does not exist is left out")
ns.ItemExists = nil
MarginDB = nil

-- a pattern with a known vendor price (from Polestar) is priced without ever being seen on the AH
ns.AHPrice = function(id) return nil end
ns.VendorBuy = function(id) return nil end
local mv = { teach = { { item = 61000, rank = 140, rep = false, vendorPrice = 2200 } } }
local ov = ns.TeachOption(mv)
assert(ov and ov.how == "vendor" and ov.fee == 2200 and ov.rank == 140)
mv.teach[1].rep = true
assert(ns.TeachOption(mv) == nil, "a reputation-locked vendor pattern is still out of reach")

-- AH depth: supply, walking the listings, and a route that runs a scarce item out
assert(loadfile("Margin/Depth.lua"))("Margin", ns)
MarginDB = { depth = {} }
ns.NoteDepth(90, { 100, 4, 120, 6, 200, 10 }, false)        -- 20 units: 4 @1s, 6 @1s20c, 10 @2s
assert(ns.Supply(90) == 20)
local c, got = ns.WalkCost(90, 8)
assert(got == 8 and c == 4 * 100 + 4 * 120, c)              -- cheapest first
c, got = ns.WalkCost(90, 50)
assert(got == 20 and c == 4 * 100 + 6 * 120 + 10 * 200, "only 20 exist")
ns.NoteDepth(91, { 100, 5 }, true)                           -- more listings than were kept: supply unknown
assert(ns.Supply(91) == nil)
MarginDB.depth[92] = { t = time() - 10 * 86400, p = { 100, 5 } }
assert(ns.Supply(92) == nil, "stale data is ignored")

ns.Owned = function() return 0 end
prices[90] = { 100, "ah" }; prices[93] = { 500, "ah" }
local Cheap = { id = 120, out = 121, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 90, count = 1} } }   -- 1s, but only 20 of item 90 exist
local Dear = { id = 122, out = 123, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 93, count = 1} } }    -- 5s, plenty
local ps = { skill = 10, max = 60, recipes = { Cheap, Dear } }
local nosup = ns.Plan(ps, 40, { ps }, false)                     -- 30 points: unlimited supply would use Cheap throughout
assert(#nosup.segs == 2 and nosup.segs[1].row.r == Cheap and nosup.segs[1].to == 30 and nosup.segs[2].row.r == Dear, nosup.segs[1].to)
assert(nosup.constrained[90], "the plan says what ran out")
ns.Owned = function(id) return id == 90 and 5 or 0 end         -- holding 5 more stretches it to 25 points
local held = ns.Plan(ps, 40, { ps }, false)
assert(held.segs[1].to == 35, held.segs[1].to)
ns.Owned = function() return 0 end
MarginDB = nil

-- folding a full scan into per-item prices and listings, for watched items only
MarginDB = { depth = {} }
local by, watch = {}, { [500] = true, [501] = true, [502] = true }
ns.AddListing(by, watch, 500, 4, 600)    -- 4 units for 6s: 1s 50c each
ns.AddListing(by, watch, 500, 10, 1000)  -- 10 units for 10s: 1s each (cheaper)
ns.AddListing(by, watch, 999, 1, 100)    -- not watched: ignored
ns.AddListing(by, watch, 501, 0, 100)    -- nothing for sale in that row: ignored
ns.AddListing(by, watch, 501, 3, 0)      -- no buyout: ignored
local fin = ns.FinishListings(by, watch, 40)
assert(fin[500].price == 100 and #fin[500].flat == 4 and fin[500].flat[1] == 100 and fin[500].flat[2] == 10, "cheapest first")
assert(fin[501].price == nil and #fin[501].flat == 0, "watched but nobody lists it: supply 0")
assert(fin[999] == nil)
local many = {}
for i = 1, 60 do ns.AddListing(many, { [700] = true }, 700, 1, i * 100) end
local cut = ns.FinishListings(many, { [700] = true }, 40)
assert(#cut[700].flat == 80 and cut[700].capped, "keeps the 40 cheapest and says there were more")
MarginDB = nil

-- crafted stock: the route's products you hold, never its reagents, most valuable first
local held = { [140] = 7, [142] = 3, [20] = 5 }
GetItemCount = function(id) return held[id] or 0 end
ns.VendorSell = function(id) return ({ [140] = 100, [142] = 1000, [20] = 50 })[id] end
ns.AHNetPerUnit = function(id) return ({ [140] = 300, [142] = nil })[id] end
local boot = { id = 150, name = "Boot", out = 140, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 1, count = 1} } }
local belt = { id = 151, name = "Belt", out = 142, qty = 1, diff = 0, ups = 1, trivial = 400, reagents = { {item = 140, count = 1} } }  -- uses Boot as a reagent
local ps2 = { skill = 10, max = 60, recipes = { boot, belt } }
local fake = { segs = { { from = 10, to = 12, row = { r = boot } }, { from = 12, to = 14, row = { r = belt } } }, shop = {} }
local stock = ns.RouteStock(fake, true)
assert(#stock == 1 and stock[1].item == 142 and stock[1].count == 3, "Boot is a reagent of a later step: not stock")
fake.segs[2] = nil
stock = ns.RouteStock(fake, true)
assert(#stock == 1 and stock[1].item == 140 and stock[1].count == 7 and stock[1].vendor == 100 and stock[1].ah == 300)
GetItemCount = nil
print("calc ok")
