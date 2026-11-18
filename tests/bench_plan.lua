-- Plan() timing on data the size of a real profession: run `lua5.1 tests/bench_plan.lua`.
-- Not part of CI (timings vary); it is the way to see whether planning got slower.
time = os.time
local ns = { Opt = function(k)
  if k == "odds" then return "worst" elseif k == "resale" then return "vendor" elseif k == "ahCut" then return 0.05
  elseif k == "ahChance" then return 0.8 elseif k == "useTrainer" then return true end
  return nil
end }
MarginDB = { depth = {}, bands = {} }
local prices, N_ITEMS = {}, 80
math.randomseed(7)
for i = 1, N_ITEMS do prices[i] = { 20 + math.random(0, 400), (i % 3 == 0) and "vendor" or "ah" } end
ns.VENDOR_SEED = {}
ns.BuyPrice = function(id) local p = prices[id]; if p then return p[1], p[2] end end
ns.AHPrice = function(id) local p = prices[id]; return p and p[2] == "ah" and p[1] or nil end
ns.VendorBuy = function() return nil end
ns.VendorSell = function(id) return 50 + (id * 37) % 900 end
ns.Deposit = function() return 0 end
ns.AHNetPerUnit = function(id) return math.floor((ns.AHPrice(id) or 100) * 0.95) end
ns.Owned = function() return 0 end
assert(loadfile("Margin/Depth.lua"))("Margin", ns)
for i = 1, N_ITEMS do
  if prices[i][2] == "ah" then
    local flat = {}
    for k = 1, 30 do flat[#flat + 1] = prices[i][1] + k * 3; flat[#flat + 1] = math.random(1, 40) end
    ns.NoteDepth(i, flat, false)
  end
end
assert(loadfile("Margin/Calc.lua"))("Margin", ns)

local function recipe(id, extra)
  local r = { id = id, name = "R" .. id, out = 1000 + id, qty = 1, diff = math.random(0, 2), ups = 1,
    trivial = 120 + math.random(0, 130), reagents = {} }
  for k = 1, 3 do r.reagents[k] = { item = math.random(1, N_ITEMS), count = math.random(1, 6) } end
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
local learned, unlearned = {}, {}
for i = 1, 90 do learned[i] = recipe(i) end
for i = 1, 40 do unlearned[i] = recipe(200 + i, { train = { rank = 100 + math.random(0, 100), fee = 200 + math.random(0, 3000) } }) end
for i = 1, 60 do unlearned[#unlearned + 1] = recipe(300 + i, { teach = { { item = 5000 + i, rank = 100 + math.random(0, 120), rep = false } } }) end
ns.AHPrice = (function(f) return function(id) if id >= 5000 then return 500 + id % 700 end return f(id) end end)(ns.AHPrice)
local prof = { skill = 150, scanSkill = 150, max = 225, recipes = learned, unlearned = unlearned }
local t0 = os.clock()
local plan = ns.Plan(prof, 225, { Bench = prof }, true)
local dt = os.clock() - t0
print(("rows %d, one plan: %.2f s, segments %d"):format(#learned + #unlearned, dt, #plan.segs))
local t1 = os.clock()
for i = 1, 4 do ns.Plan(prof, 225, { Bench = prof }, i % 2 == 0) end
print(("four plans (the Route tab's cards): %.2f s"):format(os.clock() - t1))

-- A locked route replays the recipe picked for each skill point; replaying must reproduce the plan it came from.
do
  local free = ns.Plan(prof, 225, { Bench = prof }, true)
  local forced = ns.Plan(prof, 225, { Bench = prof }, true, ns.ForceFromPicks(ns.PlanPicks(free)))
  local function sig(p) local t = {} for _, s in ipairs(p.segs) do t[#t + 1] = (s.gap and "gap" or s.row.r.id) .. ":" .. s.from .. "-" .. s.to end return table.concat(t, " ") end
  print("free  :", sig(free), free.cost, free.shopCost)
  print("forced:", sig(forced), forced.cost, forced.shopCost)
  print(sig(free) == sig(forced) and "lock replay matches" or "LOCK REPLAY DIFFERS")
end
