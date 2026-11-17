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
    if id and not seen[id] and not (searched[id] and searched[id] > recent)
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
local function route(rows, base, start, target, skip, force, byId)
  local segs, cur = {}, nil
  local total, crafts, gross = 0, 0, 0
  for s = start, target - 1 do
    local best, bestPer, bestCh
    -- a locked route keeps its earlier pick for this skill point while it is still usable
    local pick = force and force[s] and byId[force[s]]
    if pick and pick.missing == 0 and not skip[pick] and not pick.unavailable then
      local ch = chanceAt(pick, base, s) * pick.r.ups
      if ch > 0 then best, bestPer, bestCh = pick, math.max(pick.net, 0) / ch, ch end
    end
    for _, row in ipairs(best and {} or rows) do
      if row.missing == 0 and not skip[row] and not row.unavailable then
        local ch = chanceAt(row, base, s) * row.r.ups
        if ch > 0 then
          local per = math.max(row.net, 0) / ch -- see rankPer in Evaluate
          if not best or per < bestPer or (per == bestPer and ch > bestCh) then
            best, bestPer, bestCh = row, per, ch
          end
        end
      end
    end
    if best then
      if cur and cur.row == best then
        cur.to = s + 1; cur.crafts = cur.crafts + 1 / bestCh; cur.cost = cur.cost + best.net / bestCh
      else
        cur = { row = best, from = s, to = s + 1, crafts = 1 / bestCh, cost = best.net / bestCh }
        segs[#segs + 1] = cur
      end
      total = total + best.net / bestCh
      gross = gross + best.cost / bestCh
      crafts = crafts + 1 / bestCh
    else
      if cur and cur.gap then
        cur.to = s + 1
      else
        cur = { gap = true, from = s, to = s + 1, crafts = 0, cost = 0 }
        segs[#segs + 1] = cur
      end
    end
  end
  return segs, total, crafts, gross
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
  local skip = {}
  local segs, total, crafts, gross
  while true do
    segs, total, crafts, gross = route(rows, base, start, target, skip, force, byId)
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
    target = target, learn = learn, learnCost = learnCost }
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
