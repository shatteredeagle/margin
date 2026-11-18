local _, ns = ...

-- Skill-up chance by relative difficulty (orange, yellow, green, grey).
-- Skill-up chance by colour (0 orange, 1 yellow, 2 green, 3 grey). Orange always raises the skill.
-- Within a colour the chance falls as you level: roughly 75% -> 25% across yellow and 25% -> 0% across
-- green. "worst" (the default, so you do not run short of materials) plans with the bottom of each band;
-- "typical" with the middle. Green keeps a 5% floor so a stretch with only green recipes still plans.
local ODDS = {
  worst = { [0] = 1.0, [1] = 0.25, [2] = 0.05, [3] = 0 },
  typical = { [0] = 1.0, [1] = 0.75, [2] = 0.25, [3] = 0 },
}
function ns.Odds(band)
  local t = ODDS[ns.Opt("odds")] or ODDS.worst
  return t[band] or 0
end
ns.CHANCE = ODDS.typical -- kept for older callers; use ns.Odds

-- Output item -> recipe, over every scanned profession of this character, so a
-- reagent you can craft yourself is priced at its craft cost when that is cheaper.
local function craftIndex(profs)
  local idx = {}
  for name, prof in pairs(profs) do
    for _, r in ipairs(prof.recipes) do
      r.prof = r.prof or name
      if r.out and not idx[r.out] then idx[r.out] = r end
    end
  end
  return idx
end

-- Unit price of an item: cheapest of vendor, AH, or crafting it. Returns
-- copper, source ("vendor" | "ah" | "craft") or nil.
local function unitPrice(item, idx, visiting)
  local buy, src = ns.BuyPrice(item)
  local r = idx[item]
  if r and not visiting[item] then
    visiting[item] = true
    local total, ok = 0, true
    for _, rg in ipairs(r.reagents) do
      local u = unitPrice(rg.item, idx, visiting)
      if u then total = total + u * rg.count else ok = false break end
    end
    visiting[item] = nil
    if ok then
      local craft = total / r.qty
      if not buy or craft < buy then return craft, "craft" end
    end
  end
  return buy, src
end

ns.CraftIndex = craftIndex
function ns.UnitPrice(item, idx) return unitPrice(item, idx or {}, {}) end

-- Cost of one craft. Returns total copper, list of reagent lines, missing count.
function ns.RecipeCost(r, idx)
  idx = idx or {}
  local total, lines, missing = 0, {}, 0
  for _, rg in ipairs(r.reagents) do
    local unit, src = unitPrice(rg.item, idx, { [r.out or 0] = true })
    lines[#lines + 1] = { item = rg.item, count = rg.count, unit = unit, src = src }
    if unit then total = total + unit * rg.count else missing = missing + 1 end
  end
  return math.floor(total), lines, missing
end

-- Net proceeds of selling the result: vendor sell price, and AH price after the cut.
function ns.Revenue(r)
  if not r.out then return nil, nil end
  local vend = ns.VendorSell(r.out)
  local perUnit = ns.AHNetPerUnit(r.out) -- after the cut and the deposit lost on unsold listings
  if vend then vend = vend * r.qty end
  local ah = perUnit and math.floor(perUnit * r.qty) or nil
  return vend, ah
end

-- What selling the crafted item gives back, per the "resale" option: "vendor" (the
-- vendor sale price), "ah" (the AH price after the cut, vendor when it has none),
-- or "off". Subtracted from the reagent cost for leveling.
function ns.ResaleValue(vend, ah)
  local mode = ns.Opt("resale")
  if mode == "off" then return 0 end
  if mode == "ah" then return ah or vend or 0 end
  return vend or 0
end

-- Cheapest way to get a recipe that an item teaches (pattern, plan, recipe): buy the item
-- on the AH, or from a vendor that has no reputation requirement. nil when nothing is priced.
function ns.TeachOption(r)
  local best
  for _, o in ipairs(r.teach) do
    local ah, vend = ns.AHPrice(o.item), ns.VendorBuy(o.item)
    -- Worst case by default: a reputation-locked pattern is out of reach. With "use my
    -- reputation" it counts once your standing with that faction is high enough.
    local vendorOK = not o.rep
      or (ns.Opt("useRep") and o.repFaction and o.repStanding and (ns.RepStanding(o.repFaction) or 0) >= o.repStanding)
    -- the price Polestar lists for the vendor that sells it counts as a vendor price too
    if o.vendorPrice and (not vend or o.vendorPrice < vend) then vend = o.vendorPrice end
    local fee, how
    if ah and (not vend or ah < vend) then
      fee, how = ah, "ah"
    elseif vend and vendorOK then
      fee, how = vend, "vendor"
    end
    if fee and (not best or fee < best.fee) then
      best = { rank = o.rank, fee = fee, how = how, item = o.item }
    end
  end
  return best
end

-- One row per craftable recipe with cost, both profit figures and cost per skill-up.
function ns.Evaluate(prof, profs, includeTrainer, includeAll)
  local rows = {}
  local idx = craftIndex(profs or (ns.Char and ns.Char().profs) or { prof })
  local list = prof.recipes
  if (includeTrainer or includeAll) and ((prof.unlearned and #prof.unlearned > 0) or (includeAll and prof.every)) then
    list = {}
    for _, r in ipairs(prof.recipes) do list[#list + 1] = r end
    for _, r in ipairs(prof.unlearned or {}) do list[#list + 1] = r end
    if includeAll then
      for _, r in ipairs(prof.every or {}) do list[#list + 1] = r end
    end
  end
  for _, r in ipairs(list) do
    local cost, lines, missing = ns.RecipeCost(r, idx)
    local vend, ah = ns.Revenue(r)
    local chance = ns.Odds(r.diff) * r.ups
    local resale = ns.ResaleValue(vend, ah)
    local learn, unavailable
    if r.train then
      learn = { rank = r.train.rank, fee = r.train.fee, how = "trainer" }
    elseif r.teach then
      learn = ns.TeachOption(r)
      unavailable = learn == nil -- no price for any recipe item that teaches it
    end
    rows[#rows + 1] = {
      learn = learn, unavailable = unavailable,
      r = r, cost = cost, lines = lines, missing = missing,
      vendorProfit = vend and (vend - cost) or nil,
      ahProfit = ah and (ah - cost) or nil,
      chance = chance,
      resale = resale, net = cost - resale, -- reagents minus what the result sells for
      perUp = chance > 0 and (cost - resale) / chance or nil,
      -- What recipes are ranked by. A craft that sells for more than it costs has a negative net; dividing
      -- that by a low chance would make it look better the less often it works, so profit only ever
      -- brings the cost down to zero, and the more reliable recipe wins a tie.
      rankPer = chance > 0 and math.max(cost - resale, 0) / chance or nil,
    }
  end
  return rows
end

-- Priced recipes best profit first, then unpriced ones. showAll keeps the
-- unprofitable priced recipes too (they sort between the two groups).
function ns.ProfitRows(rows, key, showAll)
  local out, unpriced = {}, {}
  local field = key == "ah" and "ahProfit" or "vendorProfit"
  for _, row in ipairs(rows) do
    if row.missing > 0 or row[field] == nil then
      unpriced[#unpriced + 1] = row
    elseif showAll or row[field] > 0 then
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b) return a[field] > b[field] end)
  for _, row in ipairs(unpriced) do out[#out + 1] = row end
  return out, field
end

-- Cheapest skill-ups first, then (showAll) grey recipes by cost, then unpriced.
function ns.LevelingRows(rows, showAll)
  local ups, grey, unpriced = {}, {}, {}
  for _, row in ipairs(rows) do
    if row.missing > 0 then
      if showAll or row.chance > 0 then unpriced[#unpriced + 1] = row end
    elseif row.chance > 0 then
      ups[#ups + 1] = row
    elseif showAll then
      grey[#grey + 1] = row
    end
  end
  table.sort(ups, function(a, b)
    if a.rankPer ~= b.rankPer then return a.rankPer < b.rankPer end
    if a.chance ~= b.chance then return a.chance > b.chance end
    return a.perUp < b.perUp
  end)
  table.sort(grey, function(a, b) return a.cost < b.cost end)
  for _, row in ipairs(grey) do ups[#ups + 1] = row end
  for _, row in ipairs(unpriced) do ups[#ups + 1] = row end
  return ups
end

-- Items Margin cannot price at all (reagents, or with includeOutputs the results
-- of recipes that have no AH price), as a list of item IDs.
function ns.MissingItems(profs, includeOutputs, includeRecipes, includeAll, only, ignoreSearched)
  local idx = craftIndex(profs)
  local out, seen = {}, {}
  local recent = time() - 12 * 3600
  local searched = (not ignoreSearched and MarginDB and MarginDB.searched) or {}
  local function add(id)
    -- an item looked up in the last 12 hours that still has no price has no listing: do not nag
    -- a full scan or search that showed an empty book (nothing for sale) already answered for this item
    local d = ns.Depth and ns.Depth(id)
    local known = d and not d.capped and #d.p == 0
    if id and not seen[id] and not (searched[id] and searched[id] > recent) and not known
      and not (ns.ItemExists and not ns.ItemExists(id)) then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  -- `only` limits the lookup to one profession; the others still count for pricing what can be crafted
  for name, prof in pairs(profs) do
    if not only or name == only then
      for _, r in ipairs(prof.recipes) do
        for _, rg in ipairs(r.reagents) do
          if not ns.UnitPrice(rg.item, idx) then add(rg.item) end
        end
        if includeOutputs and r.out and not ns.AHPrice(r.out) then add(r.out) end
      end
      -- the Profit tab's "all recipes" view: the reagents and the sale price of the unlearned ones too, so
      -- every profit figure can be filled in (known recipes' sale prices as well, for the AH column)
      if includeAll then
        for _, list in ipairs({ prof.recipes, prof.unlearned or {}, prof.every or {} }) do
          for _, r in ipairs(list) do
            for _, rg in ipairs(r.reagents) do
              if not ns.UnitPrice(rg.item, idx) then add(rg.item) end
            end
            if r.out and not ns.AHPrice(r.out) then add(r.out) end
          end
        end
      end
      -- recipe items (patterns, plans) that teach an unlearned craft and have no price yet
      -- (only for recipes whose reagents are all priced: otherwise the route could not use them anyway)
      for _, r in ipairs(includeRecipes and prof.unlearned or {}) do
        if r.teach and not ns.TeachOption(r) then
          local usable = true
          for _, rg in ipairs(r.reagents) do
            if not ns.UnitPrice(rg.item, idx) then usable = false; break end
          end
          if usable then
            for _, o in ipairs(r.teach) do if o.rank <= (prof.max or 0) then add(o.item) end end
          end
        end
      end
    end
  end
  return out
end

-- Skill-up chance of recipe r when the skill is s, given it was scanned at skill
-- s0 with difficulty r.diff. Forever's colour thresholds are not exposed, so the
-- next band edge is estimated halfway to the grey level. Re-scanning corrects it.
function ns.RouteChance(r, s0, s)
  local H = r.trivial
  if not H or s >= H or r.diff == 3 then return 0 end
  -- Where the colours change. The game only tells us the grey level, but the colours sit at fixed
  -- distances below it: green starts one gap below, yellow two gaps below. The gap is about half of
  -- Classic's for the same recipe (checked against 41 Forever recipes: all matched); 12 points is
  -- the typical gap where Classic has no entry (recipes only Forever has). Worst-case odds also
  -- assume the colours change two points sooner than that.
  local classic = ns.GAP and r.id and ns.GAP[r.id]
  local w = classic and classic / 2 or 12
  local early = ns.Opt("odds") ~= "typical" and 2 or 0
  local Y = H - 2 * w - early
  local G = H - w - early
  -- what the game showed at the skill it was read: that is certain, so the edges must agree with it
  if r.diff == 0 then
    Y = math.max(Y, s0 + 1)                  -- orange now: yellow starts later
  elseif r.diff == 1 then
    Y = math.min(Y, s0); G = math.max(G, s0 + 1)
  elseif r.diff == 2 then
    Y = math.min(Y, s0); G = math.min(G, s0)
  end
  -- and what earlier scans showed narrows it further: the edge is somewhere in [y1, y2] / [g1, g2]
  local b = MarginDB and MarginDB.bands and r.id and MarginDB.bands[r.id]
  if b then
    local function clamp(v, lo, hi)
      if lo and v < lo then v = lo end
      if hi and v > hi then v = hi end
      return v
    end
    Y = clamp(Y, b.y1, b.y2)
    G = clamp(G, b.g1, b.g2)
  end
  if G < Y then G = Y end
  if s < Y then return ns.Odds(0) end
  if s < G then return ns.Odds(1) end
  return ns.Odds(2)
end

-- Remember the colour each learned recipe had at a skill. Orange at 120 means it stays orange
-- until at least 121; yellow at 130 means it has turned yellow by 130 and not green before 131.
-- The edges come out as ranges that tighten with every scan, shared by all your characters.
function ns.ObserveBands(recipes, skill)
  if not (MarginDB and skill) then return end
  MarginDB.bands = MarginDB.bands or {}
  for _, r in ipairs(recipes) do
    local d = r.diff
    if r.id and d and d < 3 and not r.train and not r.teach and not r.extra and not r.learnedAt then
      local b = MarginDB.bands[r.id]
      if not b then b = {}; MarginDB.bands[r.id] = b end
      local function lo(k, v) if not b[k] or v > b[k] then b[k] = v end end
      local function hi(k, v) if not b[k] or v < b[k] then b[k] = v end end
      if d == 0 then
        lo("y1", skill + 1)
      elseif d == 1 then
        hi("y2", skill); lo("g1", skill + 1)
      else
        hi("y2", skill); hi("g2", skill)
      end
    end
  end
end

-- What you hold of an item: bags and bank, plus AH purchases still in the mail.
function ns.Owned(item)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  return (f(item, true) or 0) + (ns.Transit and ns.Transit(item) or 0)
end

-- Expand r x mult into base (non-crafted) materials, following craft-priced reagents. `prep`
-- collects the intermediate crafts on the way, deepest first (what has to be made before what).
local function expand(r, mult, idx, acc, prep, left)
  for _, rg in ipairs(r.reagents) do
    local _, src = unitPrice(rg.item, idx, { [r.out or 0] = true })
    local sub = idx[rg.item]
    if src == "craft" and sub then
      local need = mult * rg.count
      -- what you already hold of the intermediate counts first (shared across steps, in route order)
      local use = 0
      if left then
        local have = left[rg.item]
        if have == nil then have = ns.Owned(rg.item) end
        use = math.min(have, need)
        left[rg.item] = have - use
      end
      local units = need - use
      if units > 0 then expand(sub, units / sub.qty, idx, acc, prep, left) end -- ingredients only for what is left to make
      if prep then
        local e = prep.byItem[rg.item]
        if not e then
          e = { item = rg.item, recipe = sub, units = 0, used = 0 }
          prep.byItem[rg.item] = e
          prep.order[#prep.order + 1] = e
        end
        e.units, e.used = e.units + units, e.used + use
      end
    else
      acc[rg.item] = (acc[rg.item] or 0) + mult * rg.count
    end
  end
end

-- Skill-up chance of row.r at skill s for the route. Learned recipes use the
-- difficulty seen at the scanned skill; trainer recipes start orange at the rank
-- the trainer needs and are unavailable before it.
local function chanceAt(row, s0, s)
  local r = row.r
  if row.learn then
    if s < row.learn.rank then return 0 end
    return ns.RouteChance(r, row.learn.rank, s)
  end
  return ns.RouteChance(r, s0, s)
end

-- One pass of the planner: at each skill point the available recipe with the
-- lowest expected cost per skill-up wins (points are independent, so greedy per
-- point is optimal). `skip` is a set of rows that may not be used.
-- A listing book ({ price, qty, price, qty, ... } cheapest first) with prefix sums, so the cost of the first n
-- units is a binary search. Past the end of the book the last price carries on (what lies beyond is unknown).
local function makeBook(p)
  local units, cost = { 0 }, { 0 }
  local last = 0
  for i = 1, #p, 2 do
    units[#units + 1] = units[#units] + p[i + 1]
    cost[#cost + 1] = cost[#cost] + p[i] * p[i + 1]
    last = p[i]
  end
  local book = { first = p[1] or 0 }
  function book.costTo(n)
    if n <= 0 then return 0 end
    local lo, hi = 1, #units
    if n >= units[hi] then return cost[hi] + (n - units[hi]) * last end
    while hi - lo > 1 do
      local mid = math.floor((lo + hi) / 2)
      if units[mid] >= n then hi = mid else lo = mid end
    end
    -- units[lo] < n <= units[hi]: the rest comes from listing `lo`
    return cost[lo] + (n - units[lo]) * p[(hi - 1) * 2 - 1]
  end
  return book
end

local function route(rows, base, start, target, skip, force, byId)
  local segs, cur = {}, nil
  local total, crafts, gross = 0, 0, 0
  -- What the AH can still supply of each item the route buys there (listed units plus what you hold).
  -- Skill points are spent in order, so when something runs out, later points use other recipes.
  local left, constrained = {}, {}
  -- Units of each AH item the route has used so far. Buying them takes the cheapest listings first, so each
  -- skill point costs the premium of the dearer listings it reaches over the lowest price; what you hold is
  -- used before any is bought.
  local used, heldOf = {}, {}
  local function extraFor(row, ch)
    if not row.walk then return 0 end
    local extra = 0
    for _, w in ipairs(row.walk) do
      local held = heldOf[w.item]
      if held == nil then held = ns.Owned(w.item); heldOf[w.item] = held end
      local before = used[w.item] or 0
      local b0, b1 = math.max(0, before - held), math.max(0, before + w.per / ch - held)
      if b1 > b0 then extra = extra + (w.book.costTo(b1) - w.book.costTo(b0)) - (b1 - b0) * w.book.first end
    end
    return math.max(0, extra)
  end
  local function supplyOf(item)
    local v = left[item]
    if v == nil then v = (ns.Supply and ns.Supply(item) or math.huge) + ns.Owned(item); left[item] = v end
    return v
  end
  local function fits(row, ch)
    if not row.limits then return true end
    for item, per in pairs(row.limits) do
      if per / ch > supplyOf(item) + 1e-9 then constrained[item] = true; return false end
    end
    return true
  end
  for s = start, target - 1 do
    local best, bestPer, bestCh, bestExtra
    -- a locked route keeps its earlier pick for this skill point while it is still usable
    local pick = force and force[s] and byId[force[s]]
    if pick and pick.missing == 0 and not skip[pick] and not pick.unavailable then
      local ch = chanceAt(pick, base, s) * pick.r.ups
      if ch > 0 and fits(pick, ch) then
        bestExtra = extraFor(pick, ch)
        best, bestPer, bestCh = pick, math.max(pick.net, 0) / ch + bestExtra, ch
      end
    end
    for _, row in ipairs(best and {} or rows) do
      if row.missing == 0 and not skip[row] and not row.unavailable then
        local ch = chanceAt(row, base, s) * row.r.ups
        if ch > 0 and fits(row, ch) then
          local extra = extraFor(row, ch)
          local per = math.max(row.net, 0) / ch + extra -- see rankPer in Evaluate
          if not best or per < bestPer or (per == bestPer and ch > bestCh) then
            best, bestPer, bestCh, bestExtra = row, per, ch, extra
          end
        end
      end
    end
    if best then
      local pointCost = best.net / bestCh + bestExtra
      if cur and cur.row == best then
        cur.to = s + 1; cur.crafts = cur.crafts + 1 / bestCh; cur.cost = cur.cost + pointCost
      else
        cur = { row = best, from = s, to = s + 1, crafts = 1 / bestCh, cost = pointCost }
        segs[#segs + 1] = cur
      end
      total = total + pointCost
      gross = gross + best.cost / bestCh + bestExtra
      crafts = crafts + 1 / bestCh
      for item, per in pairs(best.limits or {}) do left[item] = supplyOf(item) - per / bestCh end
      for _, w in ipairs(best.walk or {}) do used[w.item] = (used[w.item] or 0) + w.per / bestCh end
    else
      if cur and cur.gap then
        cur.to = s + 1
      else
        cur = { gap = true, from = s, to = s + 1, crafts = 0, cost = 0 }
        segs[#segs + 1] = cur
      end
    end
  end
  return segs, total, crafts, gross, constrained
end

-- Cheapest route from the scanned skill up to target, with a shopping list.
-- With useTrainer, unlearned recipes a trainer teaches are candidates too, and a
-- recipe stays in only if it saves more than its trainer fee.
function ns.Plan(prof, target, profs, useTrainer, force)
  profs = profs or (ns.Char and ns.Char().profs) or { prof }
  local idx = craftIndex(profs)
  local rows = ns.Evaluate(prof, profs, useTrainer)
  -- recipes' skill-up colours were read at scanSkill; the route starts from the skill you have now
  local base = prof.scanSkill or prof.skill
  local start = prof.skill
  local byId = {}
  for _, row in ipairs(rows) do if not byId[row.r.id] then byId[row.r.id] = row end end
  -- per craft, how much of each AH-bought item a recipe uses: `limits` for items whose total supply is known
  -- (a cap), `walk` for items whose listings are known at all (the price rises as they are used)
  if ns.Supply and ns.Depth and MarginDB and MarginDB.depth and next(MarginDB.depth) then
    local books = {}
    for _, row in ipairs(rows) do
      local acc = {}
      expand(row.r, 1, idx, acc, nil, nil)
      for item, per in pairs(acc) do
        local _, src = ns.BuyPrice(item)
        if src == "ah" then
          if ns.Supply(item) then
            row.limits = row.limits or {}
            row.limits[item] = per
          end
          local d = ns.Depth(item)
          if d and #d.p > 0 then
            books[item] = books[item] or makeBook(d.p)
            row.walk = row.walk or {}
            row.walk[#row.walk + 1] = { item = item, per = per, book = books[item] }
          end
        end
      end
    end
  end
  local skip = {}
  local segs, total, crafts, gross, constrained
  while true do
    segs, total, crafts, gross, constrained = route(rows, base, start, target, skip, force, byId)
    local used = {}
    for _, seg in ipairs(segs) do
      if not seg.gap and seg.row.learn then used[seg.row] = true end
    end
    local worst, worstNet
    for row in pairs(used) do
      skip[row] = true
      local _, alt = route(rows, base, start, target, skip, force, byId)
      skip[row] = nil
      local net = alt - total - row.learn.fee -- what dropping this recipe would save
      if net < 0 and (not worstNet or net < worstNet) then worst, worstNet = row, net end
    end
    if not worst then break end
    skip[worst] = true
  end

  local learn, learnCost = {}, 0
  for _, seg in ipairs(segs) do
    if not seg.gap and seg.row.learn then
      local seen = false
      for _, l in ipairs(learn) do if l.row == seg.row then seen = true end end
      if not seen then
        local L = seg.row.learn
        learn[#learn + 1] = { row = seg.row, rank = L.rank, fee = L.fee, how = L.how, item = L.item }
        learnCost = learnCost + L.fee
      end
    end
  end

  local acc, left = {}, {}
  for _, seg in ipairs(segs) do
    if not seg.gap then
      local prep = { order = {}, byItem = {} }
      expand(seg.row.r, math.ceil(seg.crafts), idx, acc, prep, left)
      seg.prep = {} -- intermediates to make before this step, in order
      for _, e in ipairs(prep.order) do
        seg.prep[#seg.prep + 1] = {
          item = e.item, recipe = e.recipe,
          units = math.ceil(e.units - 1e-9), crafts = math.ceil(e.units / e.recipe.qty - 1e-9),
          have = e.used, -- already in your bags or bank
          unit = ns.UnitPrice(e.item, idx), -- what one costs to make
        }
      end
    end
  end
  local shop, shopCost = {}, 0
  for item, n in pairs(acc) do
    n = math.ceil(n - 1e-9)
    local unit, src = ns.BuyPrice(item)
    shop[#shop + 1] = { item = item, count = n, unit = unit, src = src }
    if unit then shopCost = shopCost + unit * n end
  end
  table.sort(shop, function(a, b) return (a.unit or 0) * a.count > (b.unit or 0) * b.count end)
  for _, l in ipairs(learn) do
    if l.how ~= "trainer" and l.item then
      shop[#shop + 1] = { item = l.item, count = 1, unit = l.fee, src = l.how, recipe = true }
    end
  end
  return { segs = segs, cost = total, gross = gross, crafts = crafts, shop = shop, shopCost = shopCost,
    target = target, learn = learn, learnCost = learnCost, constrained = constrained }
end

-- The recipe chosen for each stretch of a plan, to lock a route, and back to a skill -> recipe table.
function ns.PlanPicks(plan)
  local out = {}
  for _, seg in ipairs(plan.segs) do
    if not seg.gap then out[#out + 1] = { id = seg.row.r.id, from = seg.from, to = seg.to } end
  end
  return out
end

function ns.ForceFromPicks(picks)
  local f = {}
  for _, p in ipairs(picks) do
    for s = p.from, p.to - 1 do f[s] = p.id end
  end
  return f
end

-- Items looked up recently that still have no price (nobody lists them).
function ns.SearchedUnpriced()
  local n, recent = 0, time() - 12 * 3600
  for id, t in pairs(MarginDB and MarginDB.searched or {}) do
    if t > recent and not ns.AHPrice(id) then n = n + 1 end
  end
  return n
end

-- What the route makes that you are holding: the products of its steps, never anything a step or the
-- shopping list uses as a reagent (that is materials, not stock). Each with what it would fetch from a
-- vendor and on the AH (after the cut and the expected lost deposit), most valuable first.
function ns.RouteStock(plan, includeBank)
  local reagent = {}
  for _, seg in ipairs(plan.segs) do
    if not seg.gap then
      for _, rg in ipairs(seg.row.r.reagents) do reagent[rg.item] = true end
    end
  end
  for _, it in ipairs(plan.shop) do reagent[it.item] = true end
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount
  local out, seen = {}, {}
  for _, seg in ipairs(plan.segs) do
    local r = not seg.gap and seg.row.r
    if r and r.out and not reagent[r.out] then
      local row = seen[r.out]
      if not row then
        local n = count and count(r.out, includeBank and true or false) or 0
        if n > 0 then
          row = { item = r.out, name = r.name, icon = r.icon, count = n, steps = {},
            vendor = ns.VendorSell(r.out) or 0, ah = ns.AHNetPerUnit and ns.AHNetPerUnit(r.out) or nil }
          seen[r.out] = row
          out[#out + 1] = row
        end
      end
      if row then row.steps[#row.steps + 1] = ("%d-%d"):format(seg.from, seg.to) end
    end
  end
  local function worth(row) return row.count * math.max(row.vendor, row.ah or 0) end
  table.sort(out, function(a, b) return worth(a) > worth(b) end)
  return out
end

-- What a run of `crafts` crafts of recipe r would involve: everything to buy (after what you hold),
-- the intermediates to make first, what it costs, and what it earns. Used by the craft planner window.
--   cash        what you still have to pay (the shopping list, listings walked cheapest first)
--   fullCost    every reagent at market price, including what you already hold
--   revenue     { vendor, ah } for the units made (the AH figure is after the cut and the deposit risk)
--   profit      { vendor, ah } revenue minus fullCost (nil when a reagent has no price)
function ns.Quote(r, crafts, profs)
  profs = profs or ns.Char().profs
  crafts = math.max(1, math.floor(crafts or 1))
  local idx = craftIndex(profs)
  local acc, prep, left = {}, { order = {}, byItem = {} }, {}
  expand(r, crafts, idx, acc, prep, left)

  local shop, cash, fullCost, unpriced, short = {}, 0, 0, 0, {}
  for item, n in pairs(acc) do
    n = math.ceil(n - 1e-9)
    local unit, src = ns.BuyPrice(item)
    local have = ns.Owned(item)
    local buy = math.max(0, n - have)
    local sup = (src == "ah" and ns.Supply) and ns.Supply(item) or nil
    local cost = unit and unit * buy or nil
    if src == "ah" and ns.WalkCost and buy > 0 then
      local c = ns.WalkCost(item, math.min(buy, sup or buy))
      if c then cost = c end
    end
    local market = unit and unit * n or nil
    if src == "ah" and ns.WalkCost then
      local c = ns.WalkCost(item, math.min(n, sup or n))
      if c then market = c end
    end
    local shortBy = (sup and buy > sup) and (buy - sup) or 0
    if shortBy > 0 then short[#short + 1] = item end
    if unit then
      cash = cash + (cost or 0)
      fullCost = fullCost + (market or 0)
    else
      unpriced = unpriced + 1
    end
    shop[#shop + 1] = { item = item, need = n, have = have, buy = buy, unit = unit, src = src, cost = cost,
      sup = sup, short = shortBy }
  end
  table.sort(shop, function(a, b)
    if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
    return (a.cost or 0) > (b.cost or 0)
  end)

  local made = {}
  for _, e in ipairs(prep.order) do
    made[#made + 1] = { item = e.item, recipe = e.recipe, have = e.used, units = math.ceil(e.units - 1e-9),
      crafts = math.ceil(e.units / e.recipe.qty - 1e-9), unit = ns.UnitPrice(e.item, idx) }
  end

  local units = crafts * (r.qty or 1)
  local vendorEach = r.out and ns.VendorSell(r.out) or nil
  local ahEach = r.out and ns.AHNetPerUnit and ns.AHNetPerUnit(r.out) or nil
  local revenue = { vendor = vendorEach and vendorEach * units or nil, ah = ahEach and ahEach * units or nil }
  local profit = {}
  if unpriced == 0 then
    profit.vendor = revenue.vendor and (revenue.vendor - fullCost) or nil
    profit.ah = revenue.ah and (revenue.ah - fullCost) or nil
  end

  -- the most crafts the base materials you already hold allow
  local one, perCraft = {}, {}
  expand(r, 1, idx, one, nil, nil)
  local most = math.huge
  for item, per in pairs(one) do
    if per > 0 then most = math.min(most, math.floor(ns.Owned(item) / per + 1e-9)) end
  end
  if most == math.huge then most = 0 end

  return { crafts = crafts, units = units, shop = shop, made = made, cash = cash, fullCost = fullCost,
    revenue = revenue, profit = profit, unpriced = unpriced, short = short, maxHeld = most,
    perCraftCost = fullCost / crafts, flip = ns.FlipLimit(r, profs) }
end

-- Cost of buying units (from, to] of a listing book ({ price, qty, price, qty, ... }, cheapest first); nil when
-- the book holds fewer than `to` units.
local function bookCost(p, from, to)
  local cost, pos = 0, 0
  for i = 1, #p, 2 do
    local price, q = p[i], p[i + 1]
    local a, b = math.max(pos, from), math.min(pos + q, to)
    if b > a then cost = cost + (b - a) * price end
    pos = pos + q
    if pos >= to then return cost end
  end
  return nil
end

-- How many crafts of recipe r are still worth doing when the ingredients are bought off the AH, cheapest
-- listing first. The lowest price only holds for the first few units: each craft after that costs more,
-- until one costs more than it sells for. Per sale mode ("vendor", "ah"): { crafts, profit (the total over
-- those crafts), next (what the first craft past the limit would lose), bySupply (stopped because the AH ran
-- out, not because it stopped paying) }. Ingredients whose listings are unknown are priced at their lowest
-- price and named in `unknown`. Held items are ignored: this is the market, not your bags.
function ns.FlipLimit(r, profs)
  profs = profs or ns.Char().profs
  local idx = craftIndex(profs)
  local per = {}
  expand(r, 1, idx, per, nil, nil)
  local books, fixed, cap, unknown = {}, 0, math.huge, {}
  for item, n in pairs(per) do
    local unit, src = ns.BuyPrice(item)
    if not unit then return nil end
    local d = (src == "ah" and ns.Depth) and ns.Depth(item) or nil
    if d then
      if not d.capped then
        local total = 0
        for i = 2, #d.p, 2 do total = total + d.p[i] end
        cap = math.min(cap, math.floor(total / n + 1e-9))
      end
      books[#books + 1] = { n = n, p = d.p }
    else
      fixed = fixed + unit * n
      if src == "ah" then unknown[#unknown + 1] = item end
    end
  end
  local units = r.qty or 1
  local function craftCost(k) -- the k-th craft's ingredients
    local c = fixed
    for _, b in ipairs(books) do
      local x = bookCost(b.p, (k - 1) * b.n, k * b.n)
      if not x then return nil end
      c = c + x
    end
    return c
  end
  local function limit(each)
    if not each then return nil end
    local revenue, total, k = each * units, 0, 0
    local top = math.min(cap, 2000)
    while k < top do
      local c = craftCost(k + 1)
      if not c then break end
      if revenue - c < 0 then return { crafts = k, profit = total, next = revenue - c } end
      k, total = k + 1, total + (revenue - c)
    end
    return { crafts = k, profit = total, bySupply = cap ~= math.huge and k >= cap }
  end
  local vendorEach = r.out and ns.VendorSell(r.out) or nil
  local ahEach = r.out and ns.AHNetPerUnit and ns.AHNetPerUnit(r.out) or nil
  return { vendor = limit(vendorEach), ah = limit(ahEach), supplyCap = cap ~= math.huge and cap or nil, unknown = unknown }
end
