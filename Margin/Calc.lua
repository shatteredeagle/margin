local _, ns = ...

-- Skill-up chance by relative difficulty (orange, yellow, green, grey).
local CHANCE = { [0] = 1.0, [1] = 0.75, [2] = 0.25, [3] = 0 }
ns.CHANCE = CHANCE

-- Output item -> recipe, over every scanned profession of this character, so a
-- reagent you can craft yourself is priced at its craft cost when that is cheaper.
local function craftIndex(profs)
  local idx = {}
  for _, prof in pairs(profs) do
    for _, r in ipairs(prof.recipes) do
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
  local ah = ns.AHPrice(r.out)
  if vend then vend = vend * r.qty end
  if ah then ah = math.floor(ah * r.qty * (1 - ns.Opt("ahCut"))) end
  return vend, ah
end

-- One row per craftable recipe with cost, both profit figures and cost per skill-up.
function ns.Evaluate(prof, profs)
  local rows = {}
  local idx = craftIndex(profs or (ns.Char and ns.Char().profs) or { prof })
  for _, r in ipairs(prof.recipes) do
    local cost, lines, missing = ns.RecipeCost(r, idx)
    local vend, ah = ns.Revenue(r)
    local chance = (CHANCE[r.diff] or 0) * r.ups
    rows[#rows + 1] = {
      r = r, cost = cost, lines = lines, missing = missing,
      vendorProfit = vend and (vend - cost) or nil,
      ahProfit = ah and (ah - cost) or nil,
      chance = chance,
      perUp = chance > 0 and cost / chance or nil,
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
  table.sort(ups, function(a, b) return a.perUp < b.perUp end)
  table.sort(grey, function(a, b) return a.cost < b.cost end)
  for _, row in ipairs(grey) do ups[#ups + 1] = row end
  for _, row in ipairs(unpriced) do ups[#ups + 1] = row end
  return ups
end

-- Items Margin cannot price at all (reagents, or with includeOutputs the results
-- of recipes that have no AH price), as a list of item IDs.
function ns.MissingItems(profs, includeOutputs)
  local idx = craftIndex(profs)
  local out, seen = {}, {}
  local function add(id)
    if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
  end
  for _, prof in pairs(profs) do
    for _, r in ipairs(prof.recipes) do
      for _, rg in ipairs(r.reagents) do
        if not ns.UnitPrice(rg.item, idx) then add(rg.item) end
      end
      if includeOutputs and r.out and not ns.AHPrice(r.out) then add(r.out) end
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
  local Y, G = -1, -1
  if r.diff == 0 then
    Y = s0 + (H - s0) / 2
    G = (Y + H) / 2
  elseif r.diff == 1 then
    G = (s0 + H) / 2
  end
  if s < Y then return 1 end
  if s < G then return 0.75 end
  return 0.25
end

-- Expand r x mult into base (non-crafted) materials, following craft-priced reagents.
local function expand(r, mult, idx, acc)
  for _, rg in ipairs(r.reagents) do
    local _, src = unitPrice(rg.item, idx, { [r.out or 0] = true })
    local sub = idx[rg.item]
    if src == "craft" and sub then
      expand(sub, mult * rg.count / sub.qty, idx, acc)
    else
      acc[rg.item] = (acc[rg.item] or 0) + mult * rg.count
    end
  end
end

-- Cheapest route from the scanned skill up to target. At each skill point the
-- recipe with the lowest expected cost per skill-up wins (points are independent,
-- so greedy per point is optimal). Returns segments, totals and a shopping list.
function ns.Plan(prof, target, profs)
  profs = profs or (ns.Char and ns.Char().profs) or { prof }
  local idx = craftIndex(profs)
  local rows = ns.Evaluate(prof, profs)
  local s0 = prof.skill
  local segs, cur = {}, nil
  local total, crafts = 0, 0
  for s = s0, target - 1 do
    local best, bestPer, bestCh
    for _, row in ipairs(rows) do
      if row.missing == 0 then
        local ch = ns.RouteChance(row.r, s0, s) * row.r.ups
        if ch > 0 then
          local per = row.cost / ch
          if not best or per < bestPer or (per == bestPer and ch > bestCh) then
            best, bestPer, bestCh = row, per, ch
          end
        end
      end
    end
    if best then
      if cur and cur.row == best then
        cur.to = s + 1; cur.crafts = cur.crafts + 1 / bestCh; cur.cost = cur.cost + bestPer
      else
        cur = { row = best, from = s, to = s + 1, crafts = 1 / bestCh, cost = bestPer }
        segs[#segs + 1] = cur
      end
      total = total + bestPer
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
  local acc = {}
  for _, seg in ipairs(segs) do
    if not seg.gap then expand(seg.row.r, math.ceil(seg.crafts), idx, acc) end
  end
  local shop, shopCost = {}, 0
  for item, n in pairs(acc) do
    n = math.ceil(n - 1e-9)
    local unit, src = ns.BuyPrice(item)
    shop[#shop + 1] = { item = item, count = n, unit = unit, src = src }
    if unit then shopCost = shopCost + unit * n end
  end
  table.sort(shop, function(a, b) return (a.unit or 0) * a.count > (b.unit or 0) * b.count end)
  return { segs = segs, cost = total, crafts = crafts, shop = shop, shopCost = shopCost, target = target }
end
