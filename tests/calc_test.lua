-- Offline check of Calc.lua with stubbed prices. Run: lua tests/calc_test.lua
local ns = { Opt = function() return 0.05 end }
local prices = { [1] = {10, "vendor"}, [2] = {50, "ah"} }
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
assert(#ns.ProfitRows(rows, "vendor") == 2)
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
print("calc ok")
